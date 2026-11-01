`timescale 1ns/1ps
module tb_wiring_top;
    GSR GSR(.GSRI(1'b1));
    reg clk=0;always #10 clk=~clk;
    tri1 ascl,asda,bscl,bsda,cscl,csda;
    reg hold_b=0,hold_c=0;
    assign bscl=hold_b ? 1'b0 : 1'bz;
    assign csda=hold_c ? 1'b0 : 1'bz;
    wire vcc;
    instrument_top #(.WIRING_DEBUG(1),.ENABLE_JOYSTICK(1),.ENABLE_EC11(1)) dut(
        .ref_clk(clk),.joystick_vcc(vcc),.joystick_sw_n(1'b1),.encoder_a(1'b1),.encoder_b(1'b1),.encoder_sw_n(1'b1),
        .mpr_scl(ascl),.mpr_sda(asda),.mpr_b_scl(bscl),.mpr_b_sda(bsda),.pressure_scl(cscl),.pressure_sda(csda),
        .control_rx(1'b1));
    defparam dut.touch.POWER_WAIT=100,dut.touch.RETRY_WAIT=5000,dut.touch.TIMEOUT=2000,dut.touch.QUARTER=8;
    defparam dut.shared_adc.adc.POWER_WAIT=100,dut.shared_adc.adc.RETRY_WAIT=5000,dut.shared_adc.adc.TIMEOUT=2000,dut.shared_adc.adc.QUARTER=8;
    reg [7:0] blank_count=0;wire fast_blank=blank_count==255;
    always @(posedge dut.pixel_clk)blank_count<=blank_count+1'b1;
    initial force dut.blank=fast_blank;
    initial begin
        wait(!dut.video_rst && !dut.rst);
        wait(dut.screen.display_wiring[3:0]==1 && dut.screen.display_wiring[19:16]==1 && dut.screen.display_wiring[35:32]==1);
        if(dut.screen.display_status[51:50]!==0 || dut.screen.adc_online!==0 || vcc!==1)$fatal(1,"Diagnostic top online/supply wiring");
        if(dut.core.rst!==1 || dut.monitor_sample!==0)$fatal(1,"Wiring profile must be silent");
        hold_b=1;hold_c=1;
        wait(dut.screen.display_wiring[19:16]==2 && dut.screen.display_wiring[35:32]==3);
        wait(dut.screen.display_wiring[30:28]==5 && dut.screen.display_wiring[46:44]==6);
        if(dut.screen.display_wiring[3:0]!=1 || dut.screen.display_wiring[14:12]!=7)$fatal(1,"Fault crossed independent bus");
        hold_b=0;hold_c=0;
        wait(dut.screen.display_wiring[30:28]==7 && dut.screen.display_wiring[46:44]==7);
        $display("PASS: real NACK/SCL/SDA faults through controllers, coherent clock crossing and HDMI frame latch; GPIO remains high");
        $display("ALL TESTS PASSED");$finish;
    end
    initial begin #2000000;$fatal(1,"Wiring top watchdog");end
endmodule
