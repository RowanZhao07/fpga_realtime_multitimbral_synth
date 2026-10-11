`timescale 1ns/1ps
// Independent pressure bus. AIN0 versus GND, +/-4.096V, continuous 860 SPS.
module ads1115_controller #(
    parameter integer QUARTER=125,
    parameter integer TIMEOUT=2500000,
    parameter integer POWER_WAIT=5000000,
    parameter integer CONVERSION_WAIT=100000,
    parameter integer RETRY_WAIT=25000000,
    parameter integer POLL_WAIT=100000
)(
    input wire clk,rst,
    inout wire scl,sda,
    output reg online=0,
    output reg [11:0] millivolts=0,
    output reg sample_valid=0
);
    localparam [15:0] CONFIG=16'hC2E3;
    localparam WAIT=0,ISSUE=1,FINISH=2;
    localparam CONFIGURE=0,VERIFY=1,SAMPLE=2;
    reg [1:0] state=WAIT,mode=CONFIGURE;
    reg [4:0] poll_count=0;
    reg [31:0] delay_count=POWER_WAIT;
    reg start=0,reading=0;
    reg [7:0] address=1;
    wire busy,done,failed;
    wire [15:0] result;
    // Register master stores the first received byte in result[7:0].
    // ADS1115 sends the most significant byte first (unlike MPR121 status).
    wire [15:0] adc_word={result[7:0],result[15:8]};
    i2c_register_master #(.QUARTER(QUARTER),.TIMEOUT(TIMEOUT),.WRITE_BYTES(2)) bus (
        .clk(clk),.rst(rst),.start(start),.reading(reading),.device_address(7'h48),
        .address(address),.value(CONFIG),.busy(busy),.done(done),.failed(failed),
        .result(result),.scl(scl),.sda(sda));
    always @(posedge clk) begin
        start<=0; sample_valid<=0;
        if(rst) begin
            state<=WAIT; mode<=CONFIGURE; delay_count<=POWER_WAIT;
            poll_count<=0;
            online<=0; millivolts<=0; reading<=0; address<=1;
        end else begin
            if(delay_count!=0) delay_count<=delay_count-1'b1;
            case(state)
                WAIT: if(delay_count==0) state<=ISSUE;
                ISSUE: if(!busy) begin
                    reading<=mode!=CONFIGURE;
                    address<=mode==SAMPLE ? 8'h00 : 8'h01;
                    start<=1; state<=FINISH;
                end
                FINISH: if(done) begin
                    state<=WAIT; delay_count<=0;
                    // OS is live conversion status, not a configuration mismatch.
                    if(failed || (mode==VERIFY && (adc_word & 16'h7FFF)!=(CONFIG & 16'h7FFF))) begin
                        online<=0; millivolts<=0; mode<=CONFIGURE;
                        poll_count<=0;
                        delay_count<=RETRY_WAIT;
                    end else if(mode==CONFIGURE) mode<=VERIFY;
                    else if(mode==VERIFY) begin
                        mode<=SAMPLE; delay_count<=CONVERSION_WAIT;
                    end else begin
                        // 125 uV/LSB: truncate to mV. Clamp small negative offsets.
                        millivolts<=adc_word[15] ? 12'd0 : adc_word[14:3];
                        online<=1; sample_valid<=1; delay_count<=POLL_WAIT;
                        // Catch an ADC-only reset that occurs between transactions
                        // and still ACKs while its default power-down mode returns 0.
                        if(poll_count==31) begin mode<=VERIFY; poll_count<=0; end
                        else poll_count<=poll_count+1'b1;
                    end
                end
                default: state<=WAIT;
            endcase
        end
    end
endmodule
