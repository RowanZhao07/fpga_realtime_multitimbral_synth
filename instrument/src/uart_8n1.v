`timescale 1ns/1ps
// Full-duplex 3.3V UART. 50MHz / 5208 = 9600.6 baud, idle high.
module uart_8n1 #(parameter integer CLOCKS_PER_BIT=5208)(
    input wire clk,rst,rx,tx_valid,input wire [7:0] tx_data,
    output reg tx=1,output wire tx_busy,
    output reg [7:0] rx_data=0,output reg rx_valid=0,rx_error=0);
    (* ASYNC_REG="TRUE" *) reg [1:0] sync_rx=2'b11;
    reg [2:0] rx_state=0;
    reg [31:0] rx_count=0,tx_count=0;
    reg [2:0] rx_bit=0;
    reg [7:0] rx_shift=0;
    reg [9:0] tx_shift=10'h3FF;
    reg [3:0] tx_left=0;
    assign tx_busy=(tx_left!=0);
    always @(posedge clk) begin
        if(rst) begin
            sync_rx<=3;rx_state<=0;rx_count<=0;rx_bit<=0;rx_shift<=0;
            rx_data<=0;rx_valid<=0;rx_error<=0;
            tx<=1;tx_left<=0;tx_count<=0;tx_shift<=10'h3FF;
        end else begin
            sync_rx<={sync_rx[0],rx};rx_valid<=0;rx_error<=0;
            case(rx_state)
            0:if(!sync_rx[1]) begin rx_count<=CLOCKS_PER_BIT/2-1;rx_state<=1;end
            1:if(rx_count!=0) rx_count<=rx_count-1'b1;
              else if(!sync_rx[1]) begin rx_count<=CLOCKS_PER_BIT-1;rx_bit<=0;rx_state<=2;end
              else rx_state<=0; // Reject a short start glitch.
            2:if(rx_count!=0) rx_count<=rx_count-1'b1;
              else begin
                  rx_shift[rx_bit]<=sync_rx[1];rx_count<=CLOCKS_PER_BIT-1;
                  if(rx_bit==7) rx_state<=3;else rx_bit<=rx_bit+1'b1;
              end
            3:if(rx_count!=0) rx_count<=rx_count-1'b1;
              else if(sync_rx[1]) begin rx_data<=rx_shift;rx_valid<=1;rx_state<=0;end
              else begin rx_error<=1;rx_state<=4;end
            4:if(sync_rx[1]) rx_state<=0; // A break reports once, then waits for idle.
            default:rx_state<=0;
            endcase
            if(tx_left==0) begin
                tx<=1;
                if(tx_valid) begin
                    tx_shift<={1'b1,tx_data,1'b0};tx<=0;
                    tx_left<=10;tx_count<=CLOCKS_PER_BIT-1;
                end
            end else if(tx_count!=0) tx_count<=tx_count-1'b1;
            else begin
                tx_count<=CLOCKS_PER_BIT-1;tx_left<=tx_left-1'b1;
                tx_shift<={1'b1,tx_shift[9:1]};tx<=tx_shift[1];
            end
        end
    end
endmodule
