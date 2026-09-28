`timescale 1ns/1ps
// Independent behavioral I2C slave and serial I2S receiver.
module tb_touch_link;
    reg clk=0;
    always #10 clk=~clk;
    reg rst=1;
    tri1 scl,sda;
    reg slave_sda=0, hold_scl=0, present=1;
    assign sda=slave_sda ? 1'b0 : 1'bz;
    assign scl=hold_scl ? 1'b0 : 1'bz;
    wire online;
    wire [11:0] touched;
    mpr121_controller #(.QUARTER(8), .TIMEOUT(50000), .POWER_WAIT(100),
        .RESET_WAIT(100), .RETRY_WAIT(500), .POLL_WAIT(100)) dut (
        .clk(clk), .rst(rst), .scl(scl), .sda(sda),
        .online(online), .touched(touched));
    reg [7:0] registers[0:255];
    integer pointer=0, writes=0, reads=0, starts=0, stops=0;
    reg transaction=0;
    // Passive START/STOP monitor; master/slave data may change only at SCL low.
    always @(negedge sda) if (scl===1'b1) begin transaction=1; starts=starts+1; end
    always @(posedge sda) if (scl===1'b1) begin transaction=0; stops=stops+1; end
    task receive_byte(output reg [7:0] b);
        integer bitn;
        begin
            for(bitn=7;bitn>=0;bitn=bitn-1) begin
                @(posedge scl); b[bitn]=sda;
            end
        end
    endtask
    task slave_ack;
        begin
            @(negedge scl); slave_sda=1;
            @(posedge scl); @(negedge scl); slave_sda=0;
        end
    endtask
    task send_byte(input reg [7:0] b, input reg expect_ack);
        integer bitn;
        begin
            // Entry is at SCL low, immediately after the preceding ACK.
            for(bitn=7;bitn>=0;bitn=bitn-1) begin
                slave_sda=!b[bitn]; @(posedge scl); @(negedge scl);
            end
            slave_sda=0;
            @(posedge scl);
            if (sda !== !expect_ack) $fatal(1,"Wrong master read ACK/NACK");
            @(negedge scl);
        end
    endtask
    reg [7:0] b, ptr_byte, val_byte;
    integer n;
    initial begin
        for(n=0;n<256;n=n+1) registers[n]=0;
        registers['h5D]='h24;
        forever begin
            @(negedge sda);
            if (scl===1'b1) begin
                receive_byte(b);
                if (present && b==8'hB4) begin
                    slave_ack(); receive_byte(ptr_byte); pointer=ptr_byte;
                    slave_ack();
                    // Next event is either repeated START or data bit clock.
                    // Register pointer 0/5D are reads; configuration is writes.
                    if (pointer!=0 && pointer!='h5D || registers['h5E]!=8'h8C) begin
                        receive_byte(val_byte); slave_ack();
                        if(pointer=='h80 && val_byte=='h63) begin
                            for(n=0;n<256;n=n+1) registers[n]=0;
                            registers['h5D]='h24;
                        end else registers[pointer]=val_byte;
                        writes=writes+1;
                    end
                end else if (present && b==8'hB5) begin
                    slave_ack();
                    send_byte(registers[pointer],1);
                    send_byte(registers[pointer+1],0);
                    reads=reads+1;
                end
            end
        end
    end
    wire bck,lrck,din;
    wire [7:0] led;
    integer note_attacks=0;
    reg previous_gate=0;
    always @(posedge clk) begin
        if(rst) begin note_attacks<=0; previous_gate<=0; end
        else if(core.sample_ce) begin
            previous_gate<=core.gates[0];
            if(core.gates[0] && !previous_gate) note_attacks<=note_attacks+1;
        end
    end
    integer before_attacks;
    reg [1:0] before_preset;
    instrument_core core(.clk(clk),.rst(rst),.online(online),.touched(touched),
        .dac_bck(bck),.dac_lrck(lrck),.dac_din(din),.led(led));
    defparam core.controls.HOLD_SAMPLES=20;
    time last_bck=0;
    always @(bck) if(!rst) begin
        if(last_bck!=0 && $time-last_bck!=160) $fatal(1,"I2S clock spacing");
        last_bck=$time;
    end
    integer decoded=0,nonzero=0;
    reg [31:0] left_slot,right_slot;
    reg [15:0] left_sample;
    integer k;
    initial forever begin
        @(negedge lrck); @(posedge bck);
        left_sample=core.transmitter.frame_sample;
        left_slot=0;
        for(k=31;k>=0;k=k-1) begin @(posedge bck); left_slot[k]=din; end
        right_slot=0;
        for(k=31;k>=0;k=k-1) begin @(posedge bck); right_slot[k]=din; end
        if(left_slot!=={left_sample,16'd0} || right_slot!==left_slot)
            $fatal(1,"Serialized instrument output mismatch");
        decoded=decoded+1;
        if(left_sample!=0) nonzero=nonzero+1;
    end
    task wait_touch(input reg [11:0] expected);
        integer tries;
        begin
            registers[0]=expected[7:0]; registers[1]={4'b0,expected[11:8]};
            tries=0;
            while(touched!==expected && tries<100000) begin
                @(posedge clk); tries=tries+1;
            end
            if(touched!==expected) $fatal(1,"Touch mismatch %h != %h",touched,expected);
        end
    endtask
    initial begin
        #200; rst=0;
        wait(online);
        if(writes!=41) $fatal(1,"Initialization write count %d",writes);
        if(registers['h5B]!==8'h11) $fatal(1,"Touch/release debounce is not enabled");
        if(core.output_stage.echo_enable!==1'b0) $fatal(1,"Normal play must start without echo");
        for(integer electrode=0;electrode<12;electrode=electrode+1) begin
            if(registers['h41+2*electrode]!=12 || registers['h42+2*electrode]!=6)
                $fatal(1,"Threshold register mismatch");
            wait_touch(12'b1 << electrode); wait_touch(0);
        end
        wait_touch(12'hA55); wait_touch(0);
        $display("PASS: init/readback, each of 12 touch bits, simultaneous keys, release");
        repeat(3000) @(posedge clk);
        before_attacks=note_attacks;
        before_preset=core.timbre;
        wait_touch(12'h001); repeat(10000) @(posedge clk);
        if(core.gates!==8'h01 || note_attacks!=before_attacks+1)
            $fatal(1,"Single held key retriggered or activated another note");
        wait_touch(12'h101); repeat(3000) @(posedge clk);
        wait_touch(12'h001); repeat(3000) @(posedge clk);
        if(core.timbre!==((before_preset+1)&3) ||
           core.engine.voice_bank[0].voice.preset!==before_preset ||
           note_attacks!=before_attacks+1)
            $fatal(1,"Preset change must preserve the held voice");
        wait_touch(0); repeat(3000) @(posedge clk);
        if((~led & 8'hF0)!==(8'h10 << core.timbre))
            $fatal(1,"Idle preset indicator mismatch");
        wait_touch(12'h001); repeat(3000) @(posedge clk);
        if(core.engine.voice_bank[0].voice.preset!==core.timbre ||
           note_attacks!=before_attacks+2)
            $fatal(1,"Next note did not use the selected preset");
        wait_touch(0); repeat(3000) @(posedge clk);
        $display("PASS: debounce configured, default echo bypass, one attack per held key, next-note preset and LED");
        present=0;
        wait(!online);
        if(touched!=0) $fatal(1,"Stale touch after NACK");
        present=1; wait(online);
        $display("PASS: NACK clears status and retries initialization");
        registers[1]=8'h80; wait(!online); wait(online);
        $display("PASS: overcurrent status triggers reinitialization");
        hold_scl=1; wait(!online);
        if(dut.bus.scl_low || dut.bus.sda_low) $fatal(1,"Timeout failed to release lines");
        $display("PASS: stuck SCL timeout releases open-drain pins");
        hold_scl=0; wait(online); wait_touch(12'h095);
        repeat(100000) @(posedge clk);
        if(decoded<20 || nonzero<5 || core.gates!==8'h95)
            $fatal(1,"Touch to polyphonic I2S integration failed");
        $display("PASS: I2C touch -> note gates -> synthesis -> decoded stereo I2S (%0d frames)",decoded);
        wait_touch(12'hF00); repeat(40000) @(posedge clk);
        if(!core.spectrum_mode || core.active!=8'hFF || core.engine.voice_bank[0].voice.preset!=0)
            $fatal(1,"Spectrum mode reset and eight-voice restart failed");
        wait_touch(0); repeat(4000) @(posedge clk);
        wait_touch(12'hF00); repeat(40000) @(posedge clk);
        if(core.spectrum_mode) $fatal(1,"Spectrum mode exit failed");
        $display("PASS: integrated spectrum mode entry/reset/exit and continuous BCK spacing");
        $display("ALL TESTS PASSED"); $finish;
    end
    initial begin #100000000; $fatal(1,"Testbench watchdog"); end
endmodule
