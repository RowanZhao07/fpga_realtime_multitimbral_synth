`timescale 1ns/1ps
// One ADS1115, AIN0 pressure / AIN1 joystick, address 0x48.
// Single-shot: write MUX+OS, verify configuration and poll OS, then read conversion.
// Never publish the conversion register while OS=0 (it still holds the old channel).
module ads1115_scanner #(
    parameter ENABLE_Y=1'b0,
    parameter integer QUARTER=125,TIMEOUT=2500000,POWER_WAIT=5000000,
    parameter integer CONVERSION_WAIT=100000,RETRY_WAIT=25000000,
    parameter integer POLL_WAIT=10000,MAX_READY_POLLS=16
)(
    input wire clk,rst,inout wire scl,sda,
    output reg pressure_online=0,joystick_online=0,
    output reg [11:0] pressure_mv=0,joystick_mv=0,
    output reg pressure_valid=0,joystick_valid=0,
    output reg y_online=0,y_valid=0,
    output reg [11:0] y_mv=0,
    output wire [15:0] diagnostics
);
    localparam WAIT=0,ISSUE=1,FINISH=2;
    localparam CONFIGURE=0,READY=1,SAMPLE=2;
    reg [1:0] state=WAIT,mode=CONFIGURE;
    reg [1:0] channel=0;
    reg start=0,reading=0;
    reg [7:0] address=1;
    reg [31:0] delay_count=POWER_WAIT,ready_polls=0;
    // +/-4.096V, 860 SPS, single-shot, comparator disabled.
    wire [15:0] config_word=channel==2 ? 16'hE3E3 : channel==1 ? 16'hD3E3 : 16'hC3E3;
    wire busy,done,failed;
    wire [3:0] bus_error;
    wire [2:0] idle_lines;
    reg [3:0] last_error=0;
    reg [7:0] failures=0;
    // Match MPR121: busy, valid idle levels, saturating failures, sticky error.
    // 5=config mismatch; 7=conversion did not become ready within the limit.
    assign diagnostics={busy,idle_lines,failures,last_error};
    wire [15:0] result;
    wire [15:0] adc_word={result[7:0],result[15:8]};
    wire config_matches=(adc_word & 16'h7FFF)==(config_word & 16'h7FFF);
    i2c_register_master #(.QUARTER(QUARTER),.TIMEOUT(TIMEOUT),.WRITE_BYTES(2)) bus(
        .clk(clk),.rst(rst),.start(start),.reading(reading),.device_address(7'h48),
        .address(address),.value(config_word),.busy(busy),.done(done),.failed(failed),
        .result(result),.scl(scl),.sda(sda),.error_code(bus_error),.idle_lines(idle_lines));
    always @(posedge clk) begin
        start<=0;pressure_valid<=0;joystick_valid<=0;y_valid<=0;
        if(rst) begin
            last_error<=0;failures<=0;y_online<=0;y_mv<=0;
            state<=WAIT;mode<=CONFIGURE;channel<=0;delay_count<=POWER_WAIT;ready_polls<=0;
            reading<=0;address<=1;pressure_online<=0;joystick_online<=0;pressure_mv<=0;joystick_mv<=0;
        end else begin
            if(delay_count!=0) delay_count<=delay_count-1'b1;
            case(state)
                WAIT: if(delay_count==0) state<=ISSUE;
                ISSUE: if(!busy) begin
                    reading<=mode!=CONFIGURE;address<=mode==SAMPLE ? 0 : 1;
                    start<=1;state<=FINISH;
                end
                FINISH: if(done) begin
                    state<=WAIT;delay_count<=0;
                    if(failed || (mode==READY && (!config_matches || (!adc_word[15] && ready_polls==MAX_READY_POLLS-1)))) begin
                        // Shared device failure invalidates BOTH consumers, never just one.
                        pressure_online<=0;joystick_online<=0;pressure_mv<=0;joystick_mv<=0;
                        y_online<=0;y_mv<=0;
                        channel<=0;mode<=CONFIGURE;ready_polls<=0;delay_count<=RETRY_WAIT;
                        last_error<=failed ? bus_error : !config_matches ? 4'd5 : 4'd7;
                        if(failures!=255) failures<=failures+1'b1;
                    end else if(mode==CONFIGURE) begin
                        mode<=READY;ready_polls<=0;delay_count<=CONVERSION_WAIT;
                    end else if(mode==READY) begin
                        if(adc_word[15]) mode<=SAMPLE;
                        else begin ready_polls<=ready_polls+1'b1;delay_count<=POLL_WAIT;end
                    end else begin
                        if(channel==2) begin
                            y_mv<=adc_word[15] ? 0 : adc_word[14:3];
                            y_online<=1;y_valid<=1;
                        end else if(channel==1) begin
                            joystick_mv<=adc_word[15] ? 0 : adc_word[14:3];
                            joystick_online<=1;joystick_valid<=1;
                        end else begin
                            pressure_mv<=adc_word[15] ? 0 : adc_word[14:3];
                            pressure_online<=1;pressure_valid<=1;
                        end
                        channel<=channel==(ENABLE_Y ? 2 : 1) ? 0 : channel+1'b1;mode<=CONFIGURE;
                    end
                end
                default: begin state<=WAIT;mode<=CONFIGURE;end
            endcase
        end
    end
endmodule
