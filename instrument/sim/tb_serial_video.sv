`timescale 1ns/1ps
// Decode actual Gowin OSER10 output against parallel TMDS symbols.
module tb_serial_video;
    GSR GSR(.GSRI(1'b1));
    reg pclk=0,fclk=0;always #12.5 pclk=~pclk;always #2.5 fclk=~fclk;
    reg rst=1,de=0,hs=0,vs=0;reg [23:0] rgb=0;
    wire [2:0] p,n;wire cp,cn;
    video_output dut(.pixel_clk(pclk),.serial_clk(fclk),.rst(rst),.rgb(rgb),.de(de),
        .hs(hs),.vs(vs),.tmds_p(p),.tmds_n(n),.tmds_clock_p(cp),.tmds_clock_n(cn));
    reg [29:0] expected[0:1023];integer produced=0,consumed=0,edges=0,k,match_index;
    reg [9:0] shift_b=0,shift_g=0,shift_r=0,shift_c=0;
    always @(posedge pclk) if(!rst) begin
        #0.01;expected[produced]={dut.red,dut.green,dut.blue};produced=produced+1;
    end
    // Search the bit boundary once. Thereafter every ten bits must match order.
    reg aligned=0;
    always @(fclk) begin
        #0.1;
        if(!rst) begin
            if({cp,p}!==(~{cn,n})) $fatal(1,"Differential outputs not complements");
            shift_b={p[0],shift_b[9:1]};shift_g={p[1],shift_g[9:1]};
            shift_r={p[2],shift_r[9:1]};shift_c={cp,shift_c[9:1]};
            if(!aligned && produced>20) begin
                for(k=3;k<produced-1;k=k+1)
                    if({shift_r,shift_g,shift_b}===expected[k] && shift_c==10'b0000011111) begin
                        aligned=1;consumed=k+1;edges=0;
                    end
            end else if(aligned) begin
                edges=edges+1;
                if(edges==10) begin
                    if({shift_r,shift_g,shift_b}!==expected[consumed] || shift_c!==10'b0000011111)
                        $fatal(1,"Serialized TMDS order/clock/bit mismatch at %d",consumed);
                    consumed=consumed+1;edges=0;
                end
            end
        end
    end
    initial begin
      for(integer phase=0;phase<2;phase=phase+1) begin
        repeat(10) @(negedge pclk);rst=0;
        for(integer i=0;i<512;i=i+1) begin
            @(negedge pclk);rgb=(i*24'h193753)^24'hAB834D;de=(i%37)>3;{vs,hs}=i;
        end
        repeat(10) @(negedge pclk);
        if(!aligned || consumed<500) $fatal(1,"No serial alignment");
        $display("PASS: three serialized TMDS channels and clock, >500 pixels decoded, reset cycle %d",phase);
        // Interrupt between clock edges and verify alignment after reset again.
        #1;rst=1;#1;
        produced=0;consumed=0;edges=0;aligned=0;
        shift_b=0;shift_g=0;shift_r=0;shift_c=0;
      end
        $display("ALL TESTS PASSED");$finish;
    end
    initial begin #50000;$fatal(1,"Serializer watchdog");end
endmodule
