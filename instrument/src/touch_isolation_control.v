`timescale 1ns/1ps
// One placed/routed image, seven runtime windows. Touch/ADC are never reset at
// a window boundary. Count failure events, not deltas of the sticky 8-bit F.
module touch_isolation_control #(
    parameter integer SECOND_CLOCKS=50000000,
    parameter integer SETTLE_SECONDS=2,
    parameter integer MEASURE_SECONDS=20
)(
    input wire clk,rst,
    input wire [1:0] chip_online,failure_event,
    input wire [3:0] error_a,error_b,
    output wire core_run,i2s_run,visual_run,led_run,
    output wire [255:0] report
);
    localparam integer TOTAL_SECONDS=SETTLE_SECONDS+MEASURE_SECONDS;
    localparam integer TIMER_BITS=SECOND_CLOCKS>1 ? $clog2(SECOND_CLOCKS) : 1;
    reg [TIMER_BITS-1:0] timer=0;
    reg [4:0] seconds=0;
    reg [2:0] stage=0;
    reg finished=0;
    reg [7:0] fail_a[0:6],fail_b[0:6];
    reg [3:0] last_a[0:6],last_b[0:6];
    reg [6:0] seen_up_a=0,seen_up_b=0,seen_down_a=0,seen_down_b=0,valid=0;
    reg was_reset=0;
    reg [7:0] reset_count=0;
    integer n;
    initial for(n=0;n<7;n=n+1) begin
        fail_a[n]=0;fail_b[n]=0;last_a[n]=0;last_b[n]=0;
    end
    // BASE keeps the original wiring diagnostic's live LED scan/combination.
    assign core_run=stage!=0 && stage!=6;
    assign i2s_run=stage==2 || stage==4 || stage==5;
    assign visual_run=stage==3 || stage==4 || stage==5;
    assign led_run=stage!=4;
    genvar g;
    generate for(g=0;g<7;g=g+1) begin: pack
        assign report[g*32 +: 32]={3'd0,valid[g],seen_up_b[g],seen_up_a[g],
            seen_down_b[g],seen_down_a[g],last_b[g],last_a[g],fail_b[g],fail_a[g]};
    end endgenerate
    wire [4:0] remaining=finished ? 5'd0 : TOTAL_SECONDS-seconds;
    assign report[255:224]={8'd0,reset_count,6'd0,(seconds<SETTLE_SECONDS),finished,remaining,stage};
    // Preserve evidence that the system reset/restarted during the experiment.
    // Configuration initializes this counter; runtime reset deliberately does not.
    always @(posedge clk) begin
        was_reset<=rst;
        if(rst && !was_reset && reset_count!=255) reset_count<=reset_count+1'b1;
    end
    always @(posedge clk) begin
        if(rst) begin
            timer<=0;seconds<=0;stage<=0;finished<=0;
            seen_up_a<=0;seen_up_b<=0;seen_down_a<=0;seen_down_b<=0;valid<=0;
            for(n=0;n<7;n=n+1) begin
                fail_a[n]<=0;fail_b[n]<=0;last_a[n]<=0;last_b[n]<=0;
            end
        end else if(!finished) begin
            if(seconds>=SETTLE_SECONDS) begin
                valid[stage]<=1;
                if(chip_online[0]) seen_up_a[stage]<=1; else seen_down_a[stage]<=1;
                if(chip_online[1]) seen_up_b[stage]<=1; else seen_down_b[stage]<=1;
                if(failure_event[0]) begin
                    if(fail_a[stage]!=255) fail_a[stage]<=fail_a[stage]+1'b1;
                    last_a[stage]<=error_a;
                end
                if(failure_event[1]) begin
                    if(fail_b[stage]!=255) fail_b[stage]<=fail_b[stage]+1'b1;
                    last_b[stage]<=error_b;
                end
            end
            if(timer==SECOND_CLOCKS-1) begin
                timer<=0;
                if(seconds==TOTAL_SECONDS-1) begin
                    seconds<=0;
                    if(stage==6) finished<=1;
                    else stage<=stage+1'b1;
                end else seconds<=seconds+1'b1;
            end else timer<=timer+1'b1;
        end
    end
endmodule
