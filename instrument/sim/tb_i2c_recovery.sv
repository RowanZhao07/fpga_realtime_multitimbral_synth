`timescale 1ns/1ps
// A powered peripheral can retain SDA low while only the FPGA is reset.
module tb_i2c_recovery;
    reg clk=0;always #10 clk=~clk;
    reg rst=1,start=0,hold_sda=0,hold_scl=0,present=1;
    reg recoverable=0;
    tri1 scl,sda;
    assign scl=hold_scl ? 1'b0 : 1'bz;
    assign sda=hold_sda ? 1'b0 : 1'bz;
    wire busy,done,failed;wire [3:0] error_code;
    integer recovery_edges=0,stops=0;
    i2c_register_master #(.QUARTER(8),.TIMEOUT(5000)) dut(
        .clk(clk),.rst(rst),.start(start),.reading(1'b0),.device_address(7'h5a),
        .address(8'h41),.value(8'd12),.busy(busy),.done(done),.failed(failed),
        .error_code(error_code),.result(),.scl(scl),.sda(sda));
    i2c_recovery_write_slave slave(.scl(scl),.sda(sda),.present(present));
    always @(posedge scl) if(hold_sda) recovery_edges=recovery_edges+1;
    always @(negedge scl) if(recoverable && recovery_edges==9) hold_sda=0;
    always @(posedge sda) if(!rst && scl) stops=stops+1;
    task request(input [3:0] expected);
        begin
            @(negedge clk);start=1;@(negedge clk);start=0;
            wait(done);@(negedge clk);
            if(error_code!==expected || failed!==(expected!=0))
                $fatal(1,"I2C fault %d/%b expected %d",error_code,failed,expected);
            if(dut.scl_low || dut.sda_low) $fatal(1,"Failed transaction retained a driven-low line");
        end
    endtask
    integer stop_before;
    initial begin
        repeat(5) @(negedge clk);rst=0;
        request(0);
        if(slave.writes!=1) $fatal(1,"Normal transaction failed");
        // Peripheral state survives FPGA reset: release SDA only after 9 clocks.
        @(negedge clk);hold_sda=1;recoverable=1;recovery_edges=0;rst=1;
        repeat(5) @(negedge clk);rst=0;stop_before=stops;
        request(3);
        if(recovery_edges!=9 || sda!==1 || stops<=stop_before)
            $fatal(1,"Bus clear requires nine clocks, released SDA and STOP");
        request(0);
        if(slave.writes!=2) $fatal(1,"Retry did not reach the recovered peripheral");
        $display("PASS: FPGA-only reset -> nine recovery clocks -> STOP -> valid retry");
        // A transient SCL stretch during recovery must not add false clocks.
        @(negedge clk);hold_sda=1;recoverable=1;recovery_edges=0;
        fork
            request(3);
            begin
                wait(recovery_edges==3);@(negedge scl);hold_scl=1;
                repeat(60) @(negedge clk);hold_scl=0;
            end
        join
        if(recovery_edges!=9 || sda!==1) $fatal(1,"Stretched recovery pulse was not honored");
        request(0);
        // Permanent faults terminate with a reason and leave open-drain pins free.
        @(negedge clk);recoverable=0;hold_sda=1;recovery_edges=0;
        request(3);
        if(recovery_edges!=10 || sda!==0) $fatal(1,"Permanent SDA fault must be bounded (9 clocks plus STOP rise)");
        hold_sda=0;repeat(20) @(negedge clk);
        hold_scl=1;request(2);hold_scl=0;repeat(20) @(negedge clk);
        present=0;request(1);present=1;request(0);
        $display("PASS: stretched clear, permanent SDA/SCL faults, NACK classification and recovery");
        $display("ALL TESTS PASSED");$finish;
    end
    initial begin #1000000;$fatal(1,"I2C recovery watchdog");end
endmodule

// Independent byte/ACK target checks valid register writes after bus clearing.
module i2c_recovery_write_slave(inout wire scl,sda,input wire present);
    reg drive_low=0;integer writes=0;
    assign sda=drive_low ? 1'b0 : 1'bz;
    task receive(output reg [7:0] b);
        for(integer i=7;i>=0;i=i-1) begin @(posedge scl);b[i]=sda;end
    endtask
    task ack;
        @(negedge scl);drive_low=1;@(posedge scl);@(negedge scl);drive_low=0;
    endtask
    reg [7:0] address,reg_addr,value;
    initial forever begin
        @(negedge sda);
        if(scl===1) begin
            receive(address);
            if(address==8'hb4 && present) begin
                ack();receive(reg_addr);ack();receive(value);ack();writes=writes+1;
                if(reg_addr!==8'h41 || value!==12) $fatal(1,"Recovery corrupted a normal write");
            end
        end
    end
endmodule
