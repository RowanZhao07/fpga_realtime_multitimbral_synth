`timescale 1ns/1ps
// Measures digital touch-status -> first nonzero I2S frame, not electrode latency.
module tb_latency #(parameter EXPRESSION=1'b0);
    reg clk=0;always #10 clk=~clk;
    reg rst=1;reg [17:0] touched=0;
    wire bck,lrck,din;wire [7:0] led;
    instrument_core #(.ENABLE_EXPRESSION(EXPRESSION),.ENABLE_JOYSTICK(EXPRESSION),.ENABLE_EC11(EXPRESSION)) dut(
        .joystick_online(1'b0),.joystick_sample_valid(1'b0),.joystick_mv(12'd0),.joystick_sw_n(1'b1),
        .y_online(1'b0),.y_sample_valid(1'b0),.y_mv(12'd0),.pressure_sample_valid(1'b0),
        .encoder_a(1'b1),.encoder_b(1'b1),.encoder_sw_n(1'b1),.sustain_info(),.sustain_request(1'b0),.clk(clk),.rst(rst),.online(1'b1),.touched(touched),.chip_online(2'b11),
        .control_rx(1'b1),.control_tx(),.control_status(),.pressure_online(1'b0),.pressure_mv(12'd0),
        .dac_bck(bck),.dac_lrck(lrck),.dac_din(din),.led(led),
        .status(),.monitor_sample(),.monitor_ce());
    reg [15:0] received=0;
    reg measuring=0,seen=0;
    time start_time,delay_ns,max_delay=0;
    integer k,trial,f;
    initial forever begin
        @(negedge lrck);@(posedge bck);
        received=0;
        for(k=15;k>=0;k=k-1) begin @(posedge bck);received[k]=din;end
        if(measuring && !seen && received!=0) begin
            delay_ns=$time-start_time;
            if(delay_ns>200000) $fatal(1,"Digital response over 0.2 ms: %d ns",delay_ns);
            if(delay_ns>max_delay) max_delay=delay_ns;
            $fdisplay(f,"%0d,%0d",trial,delay_ns);seen=1;
        end
    end
    initial begin
        f=$fopen(EXPRESSION ? "latency_expression.csv" : "latency.csv","w");
        for(trial=0;trial<8;trial=trial+1) begin
            rst=1;touched=0;measuring=0;seen=0;
            repeat(5) @(negedge clk);rst=0;
            // Settle gain and vary note event phase relative to I2S boundaries.
            repeat(2120000+trial*127) @(negedge clk);
            touched=1;start_time=$time;measuring=1;
            wait(seen);measuring=0;touched=0;
        end
        $fclose(f);
        $display("PASS: touch-status to decoded nonzero I2S maximum %0d ns over 8 phases",max_delay);
        $display("ALL TESTS PASSED");$finish;
    end
    initial begin #500000000;$fatal(1,"Latency watchdog");end
endmodule

module tb_expression_latency;
 tb_latency #(.EXPRESSION(1)) suite();
endmodule
