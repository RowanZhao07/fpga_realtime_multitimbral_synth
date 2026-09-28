`timescale 1ns/1ps
// 50 MHz input, 800 MHz VCO, 200 MHz serializer / 40 MHz pixels.
module video_clock(input wire ref_clk,output wire pixel_clk,serial_clk,locked);
    PLLA pll(.CLKIN(ref_clk),.CLKOUT0(serial_clk),.CLKOUT1(pixel_clk),.LOCK(locked),
        .CLKOUT2(),.CLKOUT3(),.CLKOUT4(),.CLKOUT5(),.CLKOUT6(),.CLKFBOUT(),.MDRDO(),
        .CLKFB(1'b0),.RESET(1'b0),.PLLPWD(1'b0),.RESET_I(1'b0),.RESET_O(1'b0),
        .PSSEL(3'b0),.PSDIR(1'b0),.PSPULSE(1'b0),.SSCPOL(1'b0),.SSCON(1'b0),
        .SSCMDSEL(7'b0),.SSCMDSEL_FRAC(3'b0),.MDCLK(1'b0),.MDOPC(2'b0),
        .MDAINC(1'b0),.MDWDI(8'b0));
    defparam pll.FCLKIN="50",pll.IDIV_SEL=1,pll.FBDIV_SEL=1,
        pll.MDIV_SEL=16,pll.MDIV_FRAC_SEL=0,pll.ODIV0_SEL=4,pll.ODIV0_FRAC_SEL=0,
        pll.ODIV1_SEL=20,pll.CLKOUT0_EN="TRUE",pll.CLKOUT1_EN="TRUE",
        pll.CLKOUT2_EN="FALSE",pll.CLKOUT3_EN="FALSE",pll.CLKOUT4_EN="FALSE",
        pll.CLKOUT5_EN="FALSE",pll.CLKOUT6_EN="FALSE",pll.CLKFB_SEL="INTERNAL";
endmodule
