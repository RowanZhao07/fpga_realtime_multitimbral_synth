`timescale 1ns/1ps
module tb_visual_link;
    reg aclk=0,pclk=0; always #10 aclk=~aclk; always #12.5 pclk=~pclk;
    reg rst=1,we=0,done=0,blank=0; reg [9:0] wa=0,ra=0;reg [7:0] wd=0;
    wire ack,ready; wire [7:0] rd;
    visual_buffer dut(.audio_clk(aclk),.audio_rst(rst),.write_enable(we),
        .write_address(wa),.write_value(wd),.frame_done(done),.frame_ack(ack),
        .pixel_clk(pclk),.pixel_rst(rst),.vertical_blank(blank),.read_address(ra),
        .read_value(rd),.ready(ready));
    reg [39:0] status=0;wire [39:0] pixel_status;
    status_mailbox mailbox(.src_clk(aclk),.src_rst(rst),.src_data(status),
        .dst_clk(pclk),.dst_rst(rst),.dst_data(pixel_status));
    reg guide_enabled=0;reg [7:0] gates=0;wire [2:0] target;wire [5:0] position;wire correct;
    practice_guide guide(.clk(aclk),.rst(rst),.sample_ce(1'b1),.enabled(guide_enabled),
        .gates(gates),.target(target),.position(position),.correct(correct));
    integer pass,i,j;
    reg old_bank;
    always @(posedge pclk) if(!rst && pixel_status!=0 && pixel_status!==40'h123456789A && pixel_status!==40'hFEDCBA9876)
        $fatal(1,"Incoherent mailbox payload");
    initial begin
        repeat(3) @(negedge aclk);rst=0; status=40'h123456789A;
        repeat(30) @(negedge pclk); if(pixel_status!==status) $fatal(1,"Mailbox startup");
        status=40'hFEDCBA9876;
        for(pass=0;pass<3;pass=pass+1) begin
            old_bank=dut.read_bank;
            for(i=0;i<1024;i=i+1) begin
                @(negedge aclk); we=1;wa=i;wd=(i+pass*37)&255;
            end
            @(negedge aclk);we=0;done=1;
            repeat(10) @(negedge pclk);
            if(dut.read_bank!==old_bank || ack) $fatal(1,"Premature bank ownership change");
            blank=1; @(negedge pclk);blank=0;
            wait(ack); @(negedge aclk);done=0;
            if(!ready || dut.read_bank===old_bank) $fatal(1,"Blanking swap missing");
            for(i=0;i<1024;i=i+1) begin
                @(negedge pclk);ra=i; @(negedge pclk);
                if(rd!==((i+pass*37)&255)) $fatal(1,"Dual-clock frame mismatch %d",i);
            end
        end
        if(pixel_status!==status) $fatal(1,"Mailbox update");
        guide_enabled=1; repeat(3) @(negedge aclk);
        gates=8'h04; repeat(5) @(negedge aclk);if(position!=0) $fatal(1,"Wrong note advanced guide");
        gates=0; repeat(2) @(negedge aclk);
        for(j=0;j<14;j=j+1) begin
            gates=8'b1<<target; repeat(5) @(negedge aclk);
            if(position!==((j+1)%14)) $fatal(1,"Guide step/held-key repeat");
            gates=0; repeat(2) @(negedge aclk);
        end
        guide_enabled=0;repeat(2) @(negedge aclk);if(position!=0) $fatal(1,"Guide reset");
        $display("PASS: coherent status mailbox, three double-buffer handoffs, 14-note manual guide");
        $display("ALL TESTS PASSED");$finish;
    end
    initial begin #1000000;$fatal(1,"Visual-link watchdog");end
endmodule
