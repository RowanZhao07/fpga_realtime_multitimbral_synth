`timescale 1ns/1ps
// 50 MHz crystal -> 800 MHz VCO -> 50 MHz global clock.
// Divider topology follows Sipeed's GW5AT-60B SDRAM_PLL reference.
module board_clock(input wire ref_clk, output wire clk, output wire locked);
    PLLA pll (
        .CLKIN(ref_clk), .CLKOUT0(clk), .LOCK(locked),
        .CLKOUT1(), .CLKOUT2(), .CLKOUT3(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6(),
        .CLKFBOUT(), .MDRDO(), .CLKFB(1'b0),
        .RESET(1'b0), .PLLPWD(1'b0), .RESET_I(1'b0), .RESET_O(1'b0),
        .PSSEL(3'b0), .PSDIR(1'b0), .PSPULSE(1'b0),
        .SSCPOL(1'b0), .SSCON(1'b0), .SSCMDSEL(7'b0), .SSCMDSEL_FRAC(3'b0),
        .MDCLK(1'b0), .MDOPC(2'b0), .MDAINC(1'b0), .MDWDI(8'b0)
    );
    defparam pll.FCLKIN="50";
    defparam pll.IDIV_SEL=1;
    defparam pll.FBDIV_SEL=1;
    defparam pll.MDIV_SEL=16;
    defparam pll.MDIV_FRAC_SEL=0;
    defparam pll.ODIV0_SEL=16;
    defparam pll.ODIV0_FRAC_SEL=0;
    defparam pll.CLKOUT0_EN="TRUE";
    defparam pll.CLKOUT1_EN="FALSE";
    defparam pll.CLKOUT2_EN="FALSE";
    defparam pll.CLKOUT3_EN="FALSE";
    defparam pll.CLKOUT4_EN="FALSE";
    defparam pll.CLKOUT5_EN="FALSE";
    defparam pll.CLKOUT6_EN="FALSE";
    defparam pll.CLKFB_SEL="INTERNAL";
endmodule
