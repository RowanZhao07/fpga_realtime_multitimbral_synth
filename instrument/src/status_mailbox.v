`timescale 1ns/1ps
// Bundled-data handshake: source payload is held until destination acknowledges.
module status_mailbox #(parameter WIDTH=40)(
    input wire src_clk,src_rst, input wire [WIDTH-1:0] src_data,
    input wire dst_clk,dst_rst, output reg [WIDTH-1:0] dst_data=0);
    reg [WIDTH-1:0] held=0;
    reg request=0, acknowledge=0;
    (* syn_preserve=1 *) reg ack_meta=0,ack_sync=0,req_meta=0,req_sync=0;
    always @(posedge src_clk) begin
        ack_meta<=acknowledge; ack_sync<=ack_meta;
        if(src_rst) begin held<=0; request<=0; end
        else if(request==ack_sync) begin held<=src_data; request<=!request; end
    end
    always @(posedge dst_clk) begin
        req_meta<=request; req_sync<=req_meta;
        if(dst_rst) begin acknowledge<=0; dst_data<=0; end
        else if(req_sync!=acknowledge) begin dst_data<=held; acknowledge<=req_sync; end
    end
endmodule
