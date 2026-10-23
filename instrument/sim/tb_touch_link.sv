`timescale 1ns/1ps
// Two physically separate 0x5A slaves exercise the real I2C controllers.
module tb_touch_link;
    reg clk=0;
    always #10 clk=~clk;
    reg rst=1;
    tri1 [1:0] scl,sda;
    reg [1:0] hold_scl=0;
    reg [1:0] present=2'b01;
    assign scl[0]=hold_scl[0] ? 1'b0 : 1'bz;
    assign scl[1]=hold_scl[1] ? 1'b0 : 1'bz;
    wire online;
    wire [1:0] chip_online;
    wire [17:0] touched;
    wire [31:0] diagnostics;
    mpr121_controller #(.QUARTER(8), .TIMEOUT(50000), .POWER_WAIT(100),
        .RESET_WAIT(100), .RETRY_WAIT(500), .POLL_WAIT(100)) dut (
        .clk(clk), .rst(rst), .scl(scl[0]), .sda(sda[0]), .scl_b(scl[1]), .sda_b(sda[1]),
        .online(online), .chip_online(chip_online), .touched(touched),.diagnostics(diagnostics));
    mpr121_test_device a(.scl(scl[0]),.sda(sda[0]),.present(present[0]));
    mpr121_test_device b(.scl(scl[1]),.sda(sda[1]),.present(present[1]));
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
    function integer held_slot(input integer key);
        integer n;
        begin held_slot=0;for(n=0;n<32;n=n+1)
            if(core.engine.occupied[n] && core.engine.held[n] && core.engine.owner[n]==key) held_slot=n;
        end
    endfunction
    integer before_attacks;
    reg [1:0] before_preset;
    instrument_core core(.encoder_a(1'b1),.encoder_b(1'b1),.encoder_sw_n(1'b1),.sustain_info(),.sustain_request(1'b0),.clk(clk),.rst(rst),.online(online),.touched(touched),.chip_online(chip_online),
        .control_rx(1'b1),.control_tx(),.control_status(),.pressure_online(1'b0),.pressure_mv(12'd0),
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
    task wait_raw(input reg [11:0] a,bkeys, input reg [17:0] expected);
        integer tries;
        begin
            tb_touch_link.a.registers[0]=a[7:0]; tb_touch_link.a.registers[1]={4'b0,a[11:8]};
            b.registers[0]=bkeys[7:0]; b.registers[1]={4'b0,bkeys[11:8]};
            tries=0;
            while(touched!==expected && tries<100000) begin
                @(posedge clk); tries=tries+1;
            end
            if(touched!==expected) $fatal(1,"Touch mismatch %h != %h",touched,expected);
        end
    endtask
    // Legacy logical controls stay in bits 11:8; white notes in bits 7:0.
    task wait_touch(input reg [17:0] expected);
        reg [11:0] a,bkeys;
        begin
            a={2'b0,expected[5],expected[15],expected[4],expected[14],
                expected[3],expected[2],expected[13],expected[1],expected[12],expected[0]};
            bkeys={4'b0,expected[11:8],expected[17],expected[7],expected[6],expected[16]};
            wait_raw(a,bkeys,expected);
        end
    endtask
    task check_stuck_bus(input integer stuck);
        integer other_reads;
        begin
            // Start from idle bus lines to avoid interrupting the slave model mid-byte.
            wait((stuck==1) ? !b.transaction : !a.transaction);
            @(negedge clk);
            hold_scl[stuck]=1;
            wait(!chip_online[stuck]);
            @(negedge clk);
            if((stuck==1 ? diagnostics[19:16] : diagnostics[3:0])!=2)
                $fatal(1,"Stuck SCL diagnostic missing on bank %0d",stuck);
            other_reads=(stuck==1) ? a.reads : b.reads;
            repeat(20000) @(posedge clk);
            if(!chip_online[1-stuck] || online || touched!=0)
                $fatal(1,"Clock fault leaked from bus %0d to healthy bus",stuck);
            if(((stuck==1) ? a.reads : b.reads)<=other_reads)
                $fatal(1,"Healthy bus stopped polling during other clock fault");
            // During timeout backoff the master's SDA must be released.
            wait(sda[stuck]===1'b1);
            hold_scl[stuck]=0;
            wait(online); wait_touch(0);
            $display("PASS: bus %0d stuck-clock isolation and recovery",stuck);
        end
    endtask
    initial begin
        #200; rst=0;
        repeat(100000) @(posedge clk);
        if(chip_online!==2'b01 || online || touched!=0)
            $fatal(1,"A must initialize independently while B is absent");
        if(diagnostics[19:16]!=1 || diagnostics[27:20]==0 || diagnostics[11:0]!=0)
            $fatal(1,"Absent B must retain NACK/count without blaming healthy A");
        present[1]=1;
        repeat(100000) @(posedge clk);
        if(chip_online!==2'b11 || !online)
            $fatal(1,"Two separate 0x5A buses must both initialize: %b",chip_online);
        if(a.writes!=41 || b.writes!=41)
            $fatal(1,"Both MPR121 devices must initialize: A=%0d B=%0d",a.writes,b.writes);
        if(a.registers['h5E]!==8'h8A || b.registers['h5E]!==8'h88)
            $fatal(1,"Enable only 10 electrodes on A and 8 on B");
        if(a.registers['h5B]!==8'h11 || b.registers['h5B]!==8'h11)
            $fatal(1,"Touch/release debounce is not enabled on both devices");
        if(core.output_stage.echo_enable!==1'b0) $fatal(1,"Normal play must start without echo");
        for(integer electrode=0;electrode<12;electrode=electrode+1) begin
            if(a.registers['h41+2*electrode]!=12 || a.registers['h42+2*electrode]!=6 ||
               b.registers['h41+2*electrode]!=12 || b.registers['h42+2*electrode]!=6)
                $fatal(1,"Threshold register mismatch");
        end
        wait_raw('h001,0,'h00001); wait_raw('h002,0,'h01000);
        wait_raw('h004,0,'h00002); wait_raw('h008,0,'h02000);
        wait_raw('h010,0,'h00004); wait_raw('h020,0,'h00008);
        wait_raw('h040,0,'h04000); wait_raw('h080,0,'h00010);
        wait_raw('h100,0,'h08000); wait_raw('h200,0,'h00020);
        wait_raw(0,'h001,'h10000); wait_raw(0,'h002,'h00040);
        wait_raw(0,'h004,'h00080); wait_raw(0,'h008,'h20000);
        wait_raw(0,'h010,'h00100); wait_raw(0,'h020,'h00200);
        wait_raw(0,'h040,'h00400); wait_raw(0,'h080,'h00800);
        wait_raw('hC00,'hF00,0);
        wait_touch('h1F0FF);
        repeat(4000) @(posedge clk);
        if(core.gates!==13'h1FFF) $fatal(1,"All 13 physical notes must sound together");
        wait_touch('h20000); repeat(3000) @(posedge clk);
        if(core.gates!=0) $fatal(1,"Reserved X0 must not trigger a note");
        wait_touch(12'hA55); wait_touch(0);
        $display("PASS: two independent 0x5A buses, 18 physical electrodes, unused inputs, 13-note chord, reserved X0");
        repeat(3000) @(posedge clk);
        before_attacks=note_attacks;
        before_preset=core.timbre;
        wait_touch(12'h001); repeat(10000) @(posedge clk);
        if(core.gates!==8'h01 || note_attacks!=before_attacks+1)
            $fatal(1,"Single held key retriggered or activated another note");
        wait_touch(12'h101); repeat(3000) @(posedge clk);
        wait_touch(12'h001); repeat(3000) @(posedge clk);
        if(core.timbre!==((before_preset+1)&3) ||
           core.engine.preset[held_slot(0)]!==before_preset ||
           note_attacks!=before_attacks+1)
            $fatal(1,"Preset change must preserve the held voice");
        wait_touch(0); repeat(3000) @(posedge clk);
        if((~led & 8'hF0)!==(8'h10 << core.timbre))
            $fatal(1,"Idle preset indicator mismatch");
        wait_touch(12'h001); repeat(3000) @(posedge clk);
        if(core.engine.preset[held_slot(0)]!==core.timbre ||
           note_attacks!=before_attacks+2)
            $fatal(1,"Next note did not use the selected preset");
        wait_touch(0); repeat(3000) @(posedge clk);
        $display("PASS: debounce configured, default echo bypass, one attack per held key, next-note preset and LED");
        wait_touch('h10001);
        present[1]=0;
        wait(!online);
        if(touched!=0) $fatal(1,"Stale touch after NACK");
        repeat(3000) @(posedge clk);
        if(core.gates!=0) $fatal(1,"Missing B must release notes from both boards");
        present[1]=1; wait(online); wait_touch(0);
        present[0]=0; wait(!online);
        if(touched!=0) $fatal(1,"Stale touch after A NACK");
        present[0]=1; wait(online);
        $display("PASS: either board NACK clears all gates and retries initialization");
        a.registers[1]=8'h80; wait(!online); @(negedge clk);
        if(diagnostics[3:0]!=6) $fatal(1,"A OVCF reason missing");
        wait(online);
        b.registers[1]=8'h80; wait(!online); @(negedge clk);
        if(diagnostics[19:16]!=6) $fatal(1,"B OVCF reason missing");
        wait(online);
        $display("PASS: overcurrent status triggers reinitialization");
        // Hold each clock low in turn; the other bus must keep polling.
        check_stuck_bus(1);
        check_stuck_bus(0);
        wait_touch(12'h095);
        repeat(100000) @(posedge clk);
        if(decoded<20 || nonzero<5 || core.gates!==8'h95)
            $fatal(1,"Touch to polyphonic I2S integration failed");
        $display("PASS: I2C touch -> note gates -> synthesis -> decoded stereo I2S (%0d frames)",decoded);
        wait_touch(12'hF00); repeat(40000) @(posedge clk);
        if(!core.spectrum_mode || core.active!=8'hFF || core.engine.preset[held_slot(0)]!=0)
            $fatal(1,"Spectrum mode reset and eight-voice restart failed");
        wait_touch(0); repeat(4000) @(posedge clk);
        wait_touch(12'hF00); repeat(40000) @(posedge clk);
        if(core.spectrum_mode) $fatal(1,"Spectrum mode exit failed");
        $display("PASS: integrated spectrum mode entry/reset/exit and continuous BCK spacing");
        $display("ALL TESTS PASSED"); $finish;
    end
    initial begin #100000000; $fatal(1,"Testbench watchdog"); end
endmodule

// Peripheral model accepts only the factory 7-bit address 0x5A.
module mpr121_test_device(inout wire scl,sda,input wire present);
    reg [7:0] registers[0:255];
    integer pointer=0;
    integer writes=0, reads=0, starts=0, stops=0;
    reg slave_sda=0;
    assign sda=slave_sda ? 1'b0 : 1'bz;
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
                    slave_ack(); receive_byte(ptr_byte);
                    pointer=ptr_byte;
                    slave_ack();
                    // Next event is either repeated START or data bit clock.
                    // Register pointer 0/5D are reads; configuration is writes.
                    if ((ptr_byte!=0 && ptr_byte!='h5D) || !registers['h5E][7]) begin
                        receive_byte(val_byte); slave_ack();
                        if(ptr_byte=='h80 && val_byte=='h63) begin
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
endmodule
