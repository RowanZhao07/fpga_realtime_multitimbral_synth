`timescale 1ns/1ps
// NXP I2S receiver contract: LRCK changes one BCK before the signed MSB.
// Read only the physical serial pins and compare to the PCM presented at
// each left-frame boundary, including both channels, padding and rate.
module tb_i2s_audio;
    reg clk=0;always #10 clk=~clk;
    reg rst=1,rx=1;reg [17:0] touched=0;
    wire bck,lrck,din,ce;wire signed [15:0] pcm;
    wire [52:0] status;
    instrument_core #(.UART_CLOCKS_PER_BIT(32)) dut(.sustain_request(1'b0),
        .clk(clk),.rst(rst),.online(1'b1),.touched(touched),.chip_online(2'b11),
        .pressure_online(1'b0),.pressure_mv(12'd0),.control_rx(rx),.control_tx(),
        .control_status(),.uart_diagnostics(),.diagnostics_visible(),.volume_low(),
        .dac_bck(bck),.dac_lrck(lrck),.dac_din(din),.led(),.key_lights(),
        .status(status),.monitor_sample(pcm),.monitor_ce(ce));
    integer frames_checked=0,frame_ce_count=0,tone=0,f,k;
    reg [15:0] expected;
    reg [31:0] left_word,right_word;
    reg capture=0;
    time last_bck=0,last_frame=0;
    reg last_lrck=1;
    always @(posedge clk) if(!rst && ce) frame_ce_count=frame_ce_count+1;
    always @(posedge bck) if(!rst) begin
        if(last_bck!=0 && $time-last_bck!=320) $fatal(1,"BCK rate is not 3.125 MHz");
        last_bck=$time;
        if(lrck!=last_lrck && din!==0) $fatal(1,"Nonzero final padding bit");
        last_lrck=lrck;
    end
    initial forever begin
        @(negedge lrck);
        if(!rst) begin
            if(last_frame!=0 && $time-last_frame!=20480) $fatal(1,"LRCK rate is not 48828.125 Hz");
            last_frame=$time;expected=pcm;
            @(posedge bck); // LRCK transition bit; I2S MSB starts next BCK.
            left_word=0;right_word=0;
            for(k=0;k<32;k=k+1) begin @(posedge bck);left_word={left_word[30:0],din};end
            // Last padding bit coincides with the next LRCK transition;
            // the independent edge checker above verifies it. Finish before
            // that transition so no following left-frame boundary is missed.
            for(k=0;k<31;k=k+1) begin @(posedge bck);right_word={right_word[30:0],din};end
            right_word={right_word[30:0],1'b0};
            if(left_word!=={expected,16'd0} || right_word!=={expected,16'd0})
                $fatal(1,"PCM/I2S mismatch expected=%h left=%h right=%h",expected,left_word,right_word);
            if(frame_ce_count!=frames_checked+1) $fatal(1,"Sample cadence changed");
            frames_checked=frames_checked+1;
            if(capture) $fdisplay(f,"%0d,%0d,%0d",tone,$signed(expected),$signed(left_word[31:16]));
        end
    end
    task byte_in(input [7:0] b);
        @(negedge clk);rx=0;repeat(32) @(negedge clk);
        for(integer i=0;i<8;i=i+1) begin rx=b[i];repeat(32) @(negedge clk);end
        rx=1;repeat(32) @(negedge clk);
    endtask
    task send(input string command_text);
        for(integer i=0;i<command_text.len();i=i+1) byte_in(command_text[i]);
        byte_in(10);repeat(500) @(negedge clk);
    endtask
    task frames(input integer count);repeat(count) @(negedge lrck);endtask
    initial begin
        f=$fopen("i2s_audio_samples.csv","w");if(!f) $fatal(1,"Capture open failed");
        repeat(5) @(negedge clk);rst=0;
        send("V4096");send("E0");frames(4200);
        for(tone=0;tone<4;tone=tone+1) begin
            send($sformatf("T%0d",tone));
            if(status[17:16]!=tone) $fatal(1,"Timbre command not applied");
            // Changing controls enters through UART; notes enter through the
            // real control mapping. No oscillator, gain or clock is forced.
            @(negedge clk);touched=1;capture=1;frames(8000);
            @(negedge clk);touched=0;frames(12000);
            @(negedge clk);capture=0;
            if(pcm!=0) $fatal(1,"Serialized preset release is not silent");
            $display("PASS: tone %0d PCM equals both I2S channels",tone);
        end
        $fclose(f);
        if(frames_checked<80000) $fatal(1,"Insufficient I2S coverage");
        $display("PASS: %0d signed stereo frames, exact PCM equality and 64 BCK/frame",frames_checked);
        $display("ALL TESTS PASSED");$finish;
    end
    initial begin #2000000000;$fatal(1,"I2S audio watchdog");end
endmodule
