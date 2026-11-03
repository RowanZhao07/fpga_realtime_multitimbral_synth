`timescale 1ns/1ps
// Model the physical 595, including unknown power-up contents. The reset input
// resets only protocol-check bookkeeping; SRCLR on the actual chip stays high.
module hc595_test_device #(parameter CASCADED_INPUT=0)(input wire rst,ser,srclk,rclk,oe_n,
    output wire serial_out,output wire [7:0] pins,output reg [7:0] storage=8'hxx);
    reg [7:0] shift=8'hxx;
    integer bit_count=0;
    reg initialized=0;
    time data_time=0,shift_rise=0,shift_fall=0,latch_rise=0;
    assign pins=oe_n ? 8'hzz : storage;
    assign serial_out=shift[7];
    always @(ser) begin
        if(!rst && srclk && !CASCADED_INPUT) $fatal(1,"SER changed while shift clock was high");
        data_time=$time;
    end
    always @(posedge srclk) begin
        shift<={shift[6:0],ser}; // Both cascaded chips sample the pre-edge QH'.
        if(!rst) begin
            if($time-data_time<125) $fatal(1,"Insufficient SER setup time");
            if(shift_fall && $time-shift_fall<100) $fatal(1,"Short SRCLK low pulse");
            bit_count=bit_count+1;
            shift_rise=$time;
        end
    end
    always @(negedge srclk) if(!rst && shift_rise) begin
        if($time-shift_rise<100) $fatal(1,"Short SRCLK high pulse");
        shift_fall=$time;
    end
    always @(posedge rclk) begin
        storage=shift;
        if(!rst) begin
            if(bit_count!=16 || srclk || $time-shift_rise<94)
                $fatal(1,"PCB chain latch did not follow exactly sixteen stable shift bits");
            if(!initialized && (!oe_n || shift!==8'h00))
                $fatal(1,"Must latch zero with outputs disabled before enabling");
            initialized=1; bit_count=0; latch_rise=$time;
        end
    end
    always @(negedge rclk) if(!rst && latch_rise && $time-latch_rise<100)
        $fatal(1,"Short latch pulse");
    always @(negedge oe_n) if(!rst && (!initialized || storage!==0))
        $fatal(1,"Enabled unknown or nonzero startup outputs");
    always @(posedge rst) begin
        bit_count=0;initialized=0;shift_rise=0;shift_fall=0;latch_rise=0;
    end
endmodule

module hc595_chain_test_device(input wire rst,ser,srclk,rclk,oe_n,
    output wire [15:0] pins,storage);
    wire cascade;
    hc595_test_device u5(.rst(rst),.ser(ser),.srclk(srclk),.rclk(rclk),.oe_n(oe_n),
        .serial_out(cascade),.pins(pins[7:0]),.storage(storage[7:0]));
    hc595_test_device #(.CASCADED_INPUT(1)) u6(.rst(rst),.ser(cascade),.srclk(srclk),.rclk(rclk),.oe_n(oe_n),
        .serial_out(),.pins(pins[15:8]),.storage(storage[15:8]));
endmodule

module tb_hc595;
    reg clk=0; always #10 clk=~clk;
    reg rst=1;
    reg [12:0] lights=13'h10A5;
    wire ser,srclk,rclk,oe_n;
    wire [15:0] pins,storage;
    hc595_driver #(.HALF_PERIOD(10),.REFRESH_CYCLES(100)) dut(
        .clk(clk),.rst(rst),.lights(lights),.serial_data(ser),
        .shift_clock(srclk),.latch_clock(rclk),.oe_n(oe_n));
    hc595_chain_test_device chip(.rst(rst),.ser(ser),.srclk(srclk),.rclk(rclk),
        .oe_n(oe_n),.pins(pins),.storage(storage));
    task wait_pattern(input [15:0] expected);
        integer timeout_count;
        begin
            timeout_count=0;
            while(pins!==expected && timeout_count<1500) begin
                @(negedge clk); timeout_count=timeout_count+1;
            end
            if(pins!==expected) $fatal(1,"595 output mismatch: %h expected %h",pins,expected);
        end
    endtask
    initial begin
        repeat(5) @(negedge clk); rst=0;
        // First enabled output is zero even though requested data is nonzero.
        wait_pattern(0); wait_pattern(16'h10A5);
        $display("PASS: blank startup then correct MSB-first shift/latch");
        for(integer index=0;index<13;index=index+1) begin
            lights=13'b1<<index; wait_pattern(16'b1<<index);
        end
        lights=13'h1FFF; wait_pattern(16'h1FFF);
        lights=13'h10A5; wait_pattern(16'h10A5);
        repeat(3) @(posedge srclk);
        @(negedge clk); lights=13'h055A;
        @(posedge rclk); #1;
        if(storage!==16'h10A5) $fatal(1,"Input changes tore a transmitted LED frame");
        wait_pattern(16'h055A);
        $display("PASS: all output positions, all-on current-test pattern and coherent updates");
        repeat(3) @(posedge srclk);
        @(negedge clk); rst=1;
        repeat(3) @(negedge clk);
        if(oe_n!==1 || srclk!==0 || rclk!==0) $fatal(1,"Reset failed to blank partial frame");
        rst=0; wait_pattern(0); wait_pattern(16'h055A);
        lights=0; wait_pattern(0);
        $display("PASS: reset during shift clears stale LEDs before re-enabling");
        $display("ALL TESTS PASSED");$finish;
    end
    initial begin #1000000; $fatal(1,"595 watchdog"); end
endmodule

module tb_key_lights;
    reg clk=0;always #10 clk=~clk;
    reg rst=1,online=1;
    reg [17:0] touched=0;
    wire [12:0] lights;
    wire [15:0] pins;
    wire ser,srclk,rclk,oe_n;
    wire [52:0] status;
    wire sample_ce;
    instrument_core core(.encoder_a(1'b1),.encoder_b(1'b1),.encoder_sw_n(1'b1),.sustain_info(),.sustain_request(1'b0),.clk(clk),.rst(rst),.online(online),.touched(touched),
        .chip_online(2'b11),.control_rx(1'b1),.control_tx(),.control_status(),.pressure_online(1'b0),.pressure_mv(12'd0),
        .key_lights(lights),.led(),.status(status),.monitor_sample(),.monitor_ce(sample_ce),
        .dac_bck(),.dac_lrck(),.dac_din());
    defparam core.controls.HOLD_SAMPLES=8;
    defparam core.guide.TICK_DENOM=32'd983040;
    hc595_driver #(.HALF_PERIOD(10),.REFRESH_CYCLES(100)) driver(
        .clk(clk),.rst(rst),.lights(lights),.serial_data(ser),
        .shift_clock(srclk),.latch_clock(rclk),.oe_n(oe_n));
    hc595_chain_test_device chip(.rst(rst),.ser(ser),.srclk(srclk),.rclk(rclk),
        .oe_n(oe_n),.pins(pins),.storage());
    task check(input [15:0] expected);
        begin
            repeat(1300) @(negedge clk);
            if(pins!==expected) $fatal(1,"Physical key LEDs %h expected %h",pins,expected);
        end
    endtask
    task frames(input integer count);
        repeat(count) begin @(posedge sample_ce); @(negedge clk); end
    endtask
    // Independent note-name lookup: C,D,E,F,G,A,B,C5 then C#,D#,F#,G#,A#.
    function [15:0] note_lamp(input integer key);
        case(key)
        0:note_lamp=16'h0001; 1:note_lamp=16'h0004; 2:note_lamp=16'h0010;
        3:note_lamp=16'h0020; 4:note_lamp=16'h0080; 5:note_lamp=16'h0200;
        6:note_lamp=16'h0800; 7:note_lamp=16'h1000; 8:note_lamp=16'h0002;
        9:note_lamp=16'h0008; 10:note_lamp=16'h0040; 11:note_lamp=16'h0100;
        12:note_lamp=16'h0400; default:note_lamp=0;
        endcase
    endfunction
    reg [15:0] expected_mask;
    initial begin
        repeat(5) @(negedge clk); rst=0; check(0);
        for(integer key=0;key<13;key=key+1) begin
            touched=18'b1<<(key<8 ? key : key+4); check(note_lamp(key));
        end
        // All 256 combinations include every F4/G4 pairing. The real core,
        // serializer and latched outputs must keep each held key independent.
        for(integer mask=0;mask<256;mask=mask+1) begin
            expected_mask=0;
            for(integer key=0;key<8;key=key+1)
                if(mask & (1<<key)) expected_mask=expected_mask | note_lamp(key);
            touched=mask;check(expected_mask);
            if(oe_n!==0) $fatal(1,"Chord changed LED output-enable duty");
        end
        touched=18'h95; check(16'h1091);
        touched=18'h1F000; check(16'h054A);
        touched=18'h1F0FF; check(16'h1FFF);
        touched=18'h08001; check(16'h0101); // C4 + G#4, across the two chips.
        touched=18'h00001; check(16'h0001); // LED9 must clear despite held C4.
        touched=18'h20000; check(16'h1FFF);
        touched=18'h20800; check(16'h1FFF); // Legacy octave modifier still retains lamp check.
        if(status[7:0]!=0 || status[44:40]!=0) $fatal(1,"Lamp check triggered notes");
        touched=0; check(0);
        $display("PASS: all 13 PCB LEDs, white/sharp chords, no stale LED1/LED9 mirroring, X0 all-on");
        touched=18'h600; frames(12); touched=0; frames(2); check(4);
        if(!status[27]) $fatal(1,"Guide did not enable");
        touched=4; frames(2); check(16'h14);
        if(status[36:31]!=0) $fatal(1,"Wrong key advanced guide");
        // Targets stay lit even between tempo flashes.
        force core.tempo.flash_left=0; check(16'h14);
        // Vocal excerpt starts D5, B4, D5. Target advances on press,
        // while the held D LED is still overlaid on the new B target.
        touched=0;frames(2);touched=2;frames(1);check(16'h804);
        if(core.guide_position!=1) $fatal(1,"Correct press did not immediately advance guide");
        frames(10);if(core.guide_position!=1)$fatal(1,"Held note advanced twice");
        touched=0;frames(3);check(16'h800);
        if(core.octave_select!=1 || core.guide_position!=1)
            $fatal(1,"Guide failed to select B4 and its physical LED");
        touched=64;frames(1);check(16'h804);touched=0;frames(3);check(16'h4);
        if(status[30:28]!=1 || core.guide_position!=2)
            $fatal(1,"Guide target did not advance to D5");
        release core.tempo.flash_left;
        online=0; check(0);
        $display("PASS: steady target overlays held keys, immediate advance and offline blanking");
        online=1; touched=18'hF00; frames(12); touched=0; frames(2); check(16'h1AB5);
        if(!status[26]) $fatal(1,"Eight-sine test mode did not enable");
        touched=18'hF00; frames(12); touched=0; frames(2);
        if(status[26]) $fatal(1,"Eight-sine test mode did not exit");
        // Guide remains selected across calibration mode; disable it before idle.
        touched=18'h600; frames(12); touched=0;frames(2);check(0);
        $display("PASS: eight-sine calibration lights all sounding notes and exits cleanly");
        $display("ALL TESTS PASSED");$finish;
    end
    initial begin #15000000; $fatal(1,"Key-light watchdog"); end
endmodule
