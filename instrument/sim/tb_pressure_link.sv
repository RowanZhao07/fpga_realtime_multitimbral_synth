`timescale 1ns/1ps
module tb_pressure_link;
    reg clk=0; always #10 clk=~clk;
    reg rst=1, present=1, bad_config=0, hold_scl=0;
    tri1 scl,sda;
    assign scl=hold_scl ? 1'b0 : 1'bz;
    reg [15:0] conversion=0;
    wire online,valid;
    wire [11:0] millivolts;
    ads1115_controller #(.QUARTER(8),.TIMEOUT(6000),.POWER_WAIT(100),
        .CONVERSION_WAIT(500),.RETRY_WAIT(500),.POLL_WAIT(200)) dut (
        .clk(clk),.rst(rst),.scl(scl),.sda(sda),.online(online),
        .millivolts(millivolts),.sample_valid(valid));
    ads1115_test_device adc(.scl(scl),.sda(sda),.present(present),
        .bad_config(bad_config),.conversion(conversion));
    integer samples=0;
    always @(posedge clk) if(valid) samples=samples+1;
    task wait_voltage(input reg [15:0] code,input integer expected);
        integer before_samples,cycles;
        begin
            conversion=code; before_samples=samples; cycles=0;
            // Wait two reads so an already-running transaction cannot satisfy it.
            while((samples<before_samples+2 || millivolts!==expected) && cycles<20000) begin
                @(negedge clk); cycles=cycles+1;
            end
            if(!online || millivolts!==expected || samples<before_samples+2)
                $fatal(1,"ADC code %h: expected %0d mV, got %0d online=%b",code,expected,millivolts,online);
        end
    endtask
    initial begin
        repeat(10) @(negedge clk); rst=0;
        repeat(12000) @(negedge clk);
        if(!online) $fatal(1,"ADS1115 must configure and produce a fresh sample");
        if(adc.config_writes!=1 || adc.config_reads<1 || adc.config_word!==16'hC2E3)
            $fatal(1,"Expected A0/GND, +/-4.096V, 860SPS continuous conversion config");
        wait_voltage(16'h0000,0);
        wait_voltage(16'h1F40,1000);
        wait_voltage(16'h2690,1234);
        wait_voltage(16'h3E80,2000);
        wait_voltage(16'h5DC0,3000);
        wait_voltage(16'h6720,3300);
        wait_voltage(16'hFFFF,0); // Slight negative offset must not wrap to full scale.
        $display("PASS: ADC configuration, MSB-first words, 0/1/2/3/3.3V and negative offset");
        present=0; wait(!online); @(negedge clk);
        if(millivolts!=0 || valid) $fatal(1,"NACK must invalidate stale pressure");
        bad_config=1; present=1;
        repeat(16000) @(negedge clk);
        if(online || millivolts!=0) $fatal(1,"Bad config readback accepted");
        bad_config=0; wait(online); wait_voltage(16'h3E80,2000);
        $display("PASS: NACK and mismatched configuration invalidate data and retry");
        wait(!adc.transaction); @(negedge clk); hold_scl=1;
        wait(!online); @(negedge clk);
        if(millivolts!=0 || dut.bus.sda_low || dut.bus.scl_low)
            $fatal(1,"Clock timeout must release pins and invalidate data");
        hold_scl=0; wait(online); wait_voltage(16'h6720,3300);
        $display("PASS: stuck clock timeout and recovery");
        // An ADC-only reset can fit entirely between polls and therefore never NACK.
        wait_voltage(16'h3E80,2000);
        wait(!adc.transaction); @(negedge clk);
        adc.config_word=16'h8583; // Actual reset state: power-down, no new conversions.
        repeat(120000) @(negedge clk);
        if(!online || millivolts!=2000 || adc.config_word!==16'hC2E3)
            $fatal(1,"Responsive ADC reset must be detected and reconfigured");
        $display("PASS: ADC-only reset without NACK recovers periodic conversion");
        $display("ALL TESTS PASSED"); $finish;
    end
    initial begin #10000000; $fatal(1,"Pressure test watchdog"); end
endmodule

// External peripheral model. Only 0x48 ACKs; pointer and both data bytes are decoded.
module ads1115_test_device(inout wire scl,sda,input wire present,bad_config,
    input wire [15:0] conversion);
    reg slave_sda=0,transaction=0;
    assign sda=slave_sda ? 1'b0 : 1'bz;
    reg [15:0] config_word=16'h8583;
    integer config_writes=0,config_reads=0;
    reg [7:0] address,ptr,hi,lo;
    reg restarted;
    reg [15:0] response;
    always @(negedge sda) if(scl===1'b1) transaction=1;
    always @(posedge sda) if(scl===1'b1) transaction=0;
    task receive_byte(output reg [7:0] value);
        for(integer n=7;n>=0;n=n-1) begin @(posedge scl); value[n]=sda; end
    endtask
    task ack;
        begin
            @(negedge scl); slave_sda=1;
            @(posedge scl); @(negedge scl); slave_sda=0;
        end
    endtask
    task send_byte(input reg [7:0] value,input reg expected_ack);
        begin
            for(integer n=7;n>=0;n=n-1) begin
                slave_sda=!value[n]; @(posedge scl); @(negedge scl);
            end
            slave_sda=0; @(posedge scl);
            if(sda!==!expected_ack) $fatal(1,"ADS read ACK/NACK sequence");
            @(negedge scl);
        end
    endtask
    initial forever begin
        @(negedge sda);
        if(scl===1'b1) begin
            receive_byte(address);
            if(present && address==8'h90) begin
                ack(); receive_byte(ptr); ack();
                // Distinguish an actual data byte from a repeated START on the wire.
                restarted=0;
                fork : next_transfer
                    receive_byte(hi);
                    begin
                        forever begin
                            @(negedge sda);
                            if(scl===1'b1) begin restarted=1; break; end
                        end
                    end
                join_any
                disable next_transfer;
                if(restarted) begin
                    receive_byte(address);
                    if(present && address==8'h91) begin
                        if(ptr==1) begin
                            config_reads=config_reads+1;
                            response=(config_word & 16'h7FFF) ^ (bad_config ? 16'h0200 : 16'h0000);
                        end else if(ptr==0) response=config_word[8] ? 16'd0 : conversion;
                        else $fatal(1,"Unexpected ADS read pointer %h",ptr);
                        ack(); send_byte(response[15:8],1); send_byte(response[7:0],0);
                    end
                end else begin
                    ack(); receive_byte(lo); ack();
                    if(ptr!=1) $fatal(1,"Unexpected ADS write pointer %h",ptr);
                    config_word={hi,lo}; config_writes=config_writes+1;
                end
            end
        end
    end
endmodule
