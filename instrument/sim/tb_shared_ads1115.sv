`timescale 1ns/1ps
module tb_shared_ads1115;
 reg clk=0;always #10 clk=~clk;
 reg rst=1,present=1,bad_config=0,hold_clock=0,hang_conversion=0;
 reg [15:0] c0=16000,c1=13200;
 tri1 scl,sda;assign scl=hold_clock?1'b0:1'bz;
 wire po,jo,pv,jv;wire [11:0] pm,jm;
 wire [15:0] diagnostics;
 integer pc=0,jc=0,previous_channel=1,prior_count;
 wire up,down;integer ups=0,downs=0;
 joystick_control #(.CENTER_SAMPLES(2),.BUTTON_CLOCKS(4)) decoder(
 .clk(clk),.rst(rst),.online(jo),.sample_valid(jv),.allow_octave(1'b1),.millivolts(jm),
 .sw_n(1'b1),.octave_up(up),.octave_down(down),.vibrato(),.armed());
 always @(negedge clk)begin if(up)ups=ups+1;if(down)downs=downs+1;end
 ads1115_scanner #(.QUARTER(8),.TIMEOUT(6000),.POWER_WAIT(100),.CONVERSION_WAIT(20),
 .POLL_WAIT(20),.MAX_READY_POLLS(16),.RETRY_WAIT(500)) dut(
 .clk(clk),.rst(rst),.scl(scl),.sda(sda),.pressure_online(po),.pressure_mv(pm),.pressure_valid(pv),
 .joystick_online(jo),.joystick_mv(jm),.joystick_valid(jv),.diagnostics(diagnostics));
 shared_ads1115_test_device adc(.scl(scl),.sda(sda),.present(present),.bad_config(bad_config),
 .conversion0(c0),.conversion1(c1),.hang_conversion(hang_conversion));
 always @(negedge clk) begin
 if(pv && jv)$fatal(1,"Mixed channel valid pulses");
 if(pv)begin
 pc=pc+1;if(previous_channel!=1)$fatal(1,"Pressure not alternating");previous_channel=0;
 if(pm!==(c0[15]?12'd0:c0[14:3]))$fatal(1,"Pressure got old/wrong channel %d",pm);
 end
 if(jv)begin
 jc=jc+1;if(previous_channel!=0)$fatal(1,"Joystick not alternating");previous_channel=1;
 if(jm!==(c1[15]?12'd0:c1[14:3]))$fatal(1,"Joystick got old/wrong channel %d",jm);
 end
 end
 task ticks(input integer n);repeat(n)@(negedge clk);endtask
 task pair;
 integer p,j,n;
 begin p=pc;j=jc;n=0;
 while((pc<p+2 || jc<j+2)&&n<200000)begin ticks(1);n=n+1;end
 if(!po || !jo || pc<p+2 || jc<j+2)$fatal(1,"No fresh pair/recovery");end
 endtask
 task failed;
 integer n;
 begin n=0;while((po || jo)&&n<100000)begin ticks(1);n=n+1;end
 if(po || jo || pm || jm || pv || jv)$fatal(1,"Shared failure retained stale consumer data");
 previous_channel=1;end
 endtask
 initial begin
 ticks(10);rst=0;pair;
 if(pm!==2000 || jm!==1650 || adc.busy_reads==0)$fatal(1,"MUX or busy polling");
 $display("PASS: AIN0/AIN1 alternate, busy OS polls never publish stale conversion");
 c0=16'hFFFF;c1=26400;pair;
 if(pm!==0 || jm!==3300 || ups!=1)$fatal(1,"Negative clamp/endpoints/right event");
 c0=25880;c1=1600;pair;
 if(pm!==3235 || jm!==200 || downs!=0)$fatal(1,"Calibrated pressure/axis cross without neutral");
 c1=13200;pair;c1=1600;pair;if(downs!=1)$fatal(1,"ADC to joystick neutral/left event");
 present=0;failed;ticks(20000);
 if(diagnostics[3:0]!=1 || diagnostics[11:4]==0 || diagnostics[14:12]!=7)$fatal(1,"NACK/idle-high evidence missing");
 present=1;pair;
 if(diagnostics[3:0]!=1 || diagnostics[11:4]==0)$fatal(1,"Recovery erased fault history");
 $display("PASS: NACK invalidates both consumers and recovers from AIN0");
 bad_config=1;failed;ticks(20000);if(po||jo)$fatal(1,"Wrong config accepted");
 if(diagnostics[3:0]!=5)$fatal(1,"Configuration mismatch evidence missing");
 bad_config=0;pair;
 wait(jv);ticks(4);hold_clock=1;failed;ticks(20);
 if(diagnostics[3:0]!=2 || diagnostics[14:12]!=5)$fatal(1,"SCL-low idle evidence missing");
 ticks(10000);hold_clock=0;pair;
 $display("PASS: configuration mismatch and SCL timeout recovery");
 hang_conversion=1;failed;prior_count=pc+jc;ticks(50000);
 if(pc+jc!=prior_count)$fatal(1,"Stalled conversion published stale data");
 if(diagnostics[3:0]!=7)$fatal(1,"Conversion timeout evidence missing");
 hang_conversion=0;pair;
 $display("PASS: bounded OS timeout and restart");
 // ADC reset responds to I2C but loses MUX/config; must reject and configure anew.
 adc.config_word=16'h8583;pair;
 $display("ALL TESTS PASSED");$finish;
 end
 initial begin #100000000;$fatal(1,"Shared ADC watchdog");end
endmodule

module shared_ads1115_test_device(inout wire scl,sda,input wire present,bad_config,
    input wire [15:0] conversion0,conversion1,conversion2,input wire hang_conversion);
    reg [15:0] config_word=16'h8583;
    reg converting=0;
    reg [15:0] converted=16'h7FFF;
    integer conversion_starts=0,conversion_reads=0,busy_reads=0;
    event config_written;
    always @(config_written) if(config_word[15] && config_word[8] && config_word[14:12]>=4 && config_word[14:12]<=6) begin
        converting=1;conversion_starts=conversion_starts+1;
        // Old conversion remains visible for 200us after every channel switch.
        #200000;
        if(!hang_conversion) begin
            converted=config_word[14:12]==4 ? conversion0 : config_word[14:12]==5 ? conversion1 : conversion2;converting=0;
        end
    end
    reg slave_sda=0,transaction=0;
    assign sda=slave_sda ? 1'b0 : 1'bz;
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
                            response=((config_word & 16'h7FFF) | (converting ? 16'h0000 : 16'h8000)) ^ (bad_config ? 16'h0200 : 16'h0000);
                            if(converting)busy_reads=busy_reads+1;
                        end else if(ptr==0) begin
                            if(converting)$fatal(1,"Scanner read stale conversion while OS=0");
                            response=converted;conversion_reads=conversion_reads+1;
                        end
                        else $fatal(1,"Unexpected ADS read pointer %h",ptr);
                        ack(); send_byte(response[15:8],1); send_byte(response[7:0],0);
                    end
                end else begin
                    ack(); receive_byte(lo); ack();
                    if(ptr!=1) $fatal(1,"Unexpected ADS write pointer %h",ptr);
                    config_word={hi,lo}; config_writes=config_writes+1;->config_written;
                end
            end
        end
    end
endmodule

// Production timing budget: default 100kHz bus and 2ms conversion wait.
module tb_shared_ads1115_rate;
 reg clk=0;always #10 clk=~clk;
 reg rst=1;tri1 scl,sda;wire valid;integer count=0;time previous_time=0,period;
 ads1115_scanner #(.POWER_WAIT(100)) dut(.clk(clk),.rst(rst),.scl(scl),.sda(sda),
 .pressure_online(),.pressure_mv(),.pressure_valid(),.joystick_online(),.joystick_mv(),.joystick_valid(valid));
 shared_ads1115_test_device adc(.scl(scl),.sda(sda),.present(1'b1),.bad_config(1'b0),
 .conversion0(16'd25880),.conversion1(16'd13200),.hang_conversion(1'b0));
 initial begin repeat(10)@(negedge clk);rst=0;end
 always @(negedge clk)if(valid)begin
 count=count+1;
 if(count>=2)begin
 period=$time-previous_time;
 if(period<6000000 || period>7500000)$fatal(1,"Unexpected shared ADC period %0t",period);
 $display("Per-channel period: %0d ns, approximately %0d samples/second",period,1000000000/period);
 end
 previous_time=$time;
 if(count==3)begin $display("ALL TESTS PASSED");$finish;end
 end
 initial begin #30000000;$fatal(1,"Throughput watchdog");end
endmodule
