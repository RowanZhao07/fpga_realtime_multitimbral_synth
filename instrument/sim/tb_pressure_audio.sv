`timescale 1ns/1ps
// Decode the real I2S outputs of two synchronous instruments. The reference
// has no ADC; the other receives pressure while both hold the same notes.
module tb_pressure_audio;
    reg clk=0; always #10 clk=~clk;
    reg rst=1, pressure_online=1;
    reg [11:0] pressure_mv=0;
    reg [17:0] touched=0;
    wire bck,lrck,din,ref_bck,ref_lrck,ref_din;
    wire [52:0] status;
    instrument_core dut(.sustain_request(1'b0),.clk(clk),.rst(rst),.online(1'b1),.touched(touched),.chip_online(2'b11),
        .control_rx(1'b1),.control_tx(),.control_status(),.pressure_online(pressure_online),.pressure_mv(pressure_mv),
        .dac_bck(bck),.dac_lrck(lrck),.dac_din(din),.led(),.status(status),
        .monitor_sample(),.monitor_ce());
    instrument_core reference(.sustain_request(1'b0),.clk(clk),.rst(rst),.online(1'b1),.touched(touched),.chip_online(2'b11),
        .control_rx(1'b1),.control_tx(),.control_status(),.pressure_online(1'b0),.pressure_mv(12'd0),
        .dac_bck(ref_bck),.dac_lrck(ref_lrck),.dac_din(ref_din),.led(),.status(),
        .monitor_sample(),.monitor_ce());
    defparam dut.controls.HOLD_SAMPLES=8;
    defparam reference.controls.HOLD_SAMPLES=8;
    integer previous_gain=0,current_gain=0;
    // A pressure step or ADC disconnect must use the existing one-unit ramp.
    always @(negedge clk) begin
        current_gain=dut.output_stage.smooth_gain;
        if(rst || dut.audio_reset) previous_gain=0;
        else begin
            if(current_gain>previous_gain+1 || current_gain<previous_gain-1)
                $fatal(1,"Pressure bypassed the sample-rate gain ramp");
            previous_gain=current_gain;
        end
        if(!rst && (bck!==ref_bck || lrck!==ref_lrck))
            $fatal(1,"Pressure changed audio timing");
    end
    task frames(input integer count);
        repeat(count) @(negedge lrck);
    endtask
    task check_audio(input integer numerator,denominator);
        integer bit_index,frame_index,actual,baseline,error,peak;
        reg [31:0] left,right,ref_left,ref_right;
        begin
            peak=0;
            for(frame_index=0;frame_index<128;frame_index=frame_index+1) begin
                @(negedge lrck); @(posedge bck);
                left=0;right=0;ref_left=0;ref_right=0;
                for(bit_index=31;bit_index>=0;bit_index=bit_index-1) begin
                    @(posedge bck); left[bit_index]=din; ref_left[bit_index]=ref_din;
                end
                for(bit_index=31;bit_index>=0;bit_index=bit_index-1) begin
                    @(posedge bck); right[bit_index]=din; ref_right[bit_index]=ref_din;
                end
                if($isunknown({left,right,ref_left,ref_right}) || left!==right || ref_left!==ref_right || left[15:0]!=0)
                    $fatal(1,"Invalid dual-mono I2S payload");
                actual=$signed(left[31:16]); baseline=$signed(ref_left[31:16]);
                error=actual*denominator-baseline*numerator;
                if(error>2*denominator || error< -2*denominator)
                    $fatal(1,"Pressure did not scale audible samples: actual=%0d reference=%0d expected=%0d/%0d",actual,baseline,numerator,denominator);
                if(actual>peak) peak=actual;
                if(-actual>peak) peak=-actual;
            end
            if(peak<50) $fatal(1,"Pressure test did not exercise an audible note");
        end
    endtask
    initial begin
        repeat(5) @(negedge clk); rst=0;
        pressure_mv=3300; frames(32);
        if(dut.monitor_sample!==0) $fatal(1,"Pressure alone triggered sound");
        pressure_mv=0; touched=1; frames(2600);
        check_audio(1,4);
        $display("PASS: released pressure pad retains audible quarter-volume notes");
        pressure_mv=2000; frames(1100); check_audio(189,256);
        $display("PASS: measured 2V light press scales actual serialized audio");
        pressure_mv=3300; frames(700); check_audio(1,1);
        pressure_mv=4095; frames(8); check_audio(1,1);
        $display("PASS: firm press reaches master volume without exceeding it");
        pressure_mv=0; frames(1700); check_audio(1,4);
        pressure_online=0; frames(1700); check_audio(1,1);
        $display("PASS: ADC failure smoothly restores ordinary keyboard volume");
        pressure_online=1; frames(1700); check_audio(1,4);
        touched=18'h201; frames(3); touched=1; frames(300);
        if(status[22:18]!=7) $fatal(1,"Master volume-down control failed");
        check_audio(1,4);
        touched=18'h401; frames(3); touched=1; frames(300);
        if(status[22:18]!=8) $fatal(1,"Master volume-up control failed");
        check_audio(1,4);
        $display("PASS: C1/C2 master-volume controls remain effective");
        touched=18'hF00; frames(12); touched=0; frames(2700);
        if(!status[26]) $fatal(1,"Spectrum calibration mode did not activate");
        check_audio(1,1);
        pressure_mv=3300; frames(8); check_audio(1,1);
        $display("PASS: calibrated spectrum mode bypasses pressure expression");
        touched=18'hF00; frames(12); touched=0; frames(3500);
        if(dut.monitor_sample!==0) $fatal(1,"Pressure kept released notes sounding");
        $display("ALL TESTS PASSED"); $finish;
    end
    initial begin #600000000; $fatal(1,"Pressure audio watchdog"); end
endmodule
