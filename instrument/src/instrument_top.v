`timescale 1ns/1ps
module instrument_top (
    input wire ref_clk, // On-board 50 MHz crystal, V22.
    inout wire mpr_scl, mpr_sda,
    output wire dac_bck, dac_lrck, dac_din,
    output wire [7:0] led,
    output wire [2:0] tmds_p,tmds_n,
    output wire tmds_clock_p,tmds_clock_n,hpd_en
);
    wire clk, locked;
    board_clock clock_source(.ref_clk(ref_clk),.clk(clk),.locked(locked));
    reg [7:0] reset_release=0;
    wire rst=!reset_release[7];
    // Asynchronous assertion on lock loss, synchronous release after 8 clocks.
    always @(posedge clk or negedge locked) begin
        if(!locked) reset_release<=0;
        else reset_release<={reset_release[6:0],1'b1};
    end
    wire online;
    wire [11:0] touched;
    mpr121_controller touch(.clk(clk),.rst(rst),.scl(mpr_scl),.sda(mpr_sda),
        .online(online),.touched(touched));
    wire [39:0] status,pixel_status;
    wire signed [15:0] monitor_sample;
    wire monitor_ce;
    instrument_core core(.clk(clk),.rst(rst),.online(online),.touched(touched),
        .dac_bck(dac_bck),.dac_lrck(dac_lrck),.dac_din(dac_din),.led(led),
        .status(status),.monitor_sample(monitor_sample),.monitor_ce(monitor_ce));
    wire pixel_clk,serial_clk,video_locked;
    video_clock display_clock(.ref_clk(ref_clk),.pixel_clk(pixel_clk),
        .serial_clk(serial_clk),.locked(video_locked));
    reg [7:0] video_release=0;
    wire both_locked=locked && video_locked;
    always @(posedge pixel_clk or negedge both_locked) begin
        if(!both_locked) video_release<=0;
        else video_release<={video_release[6:0],1'b1};
    end
    wire video_rst=!video_release[7];
    reg [2:0] analyser_release=0;
    always @(posedge clk or negedge both_locked) begin
        if(!both_locked) analyser_release<=0;
        else analyser_release<={analyser_release[1:0],1'b1};
    end
    wire analyser_rst=rst || !analyser_release[2];
    status_mailbox mailbox(.src_clk(clk),.src_rst(analyser_rst),.src_data(status),
        .dst_clk(pixel_clk),.dst_rst(video_rst),.dst_data(pixel_status));
    wire [10:0] x; wire [9:0] y;
    wire de,hs,vs,blank;
    video_timing timing(.clk(pixel_clk),.rst(video_rst),.x(x),.y(y),.de(de),.hs(hs),.vs(vs),.vertical_blank(blank));
    wire visual_write,frame_done,frame_ack,visual_ready;
    wire [9:0] visual_write_address,visual_read_address;
    wire [7:0] visual_write_data,visual_read_data;
    audio_spectrum analyser(.clk(clk),.rst(analyser_rst),.sample_ce(monitor_ce),.sample(monitor_sample),
        .write_enable(visual_write),.write_address(visual_write_address),.write_value(visual_write_data),
        .frame_done(frame_done),.frame_ack(frame_ack),.bin_valid(),.bin_index(),.bin_magnitude());
    visual_buffer visual_memory(.audio_clk(clk),.audio_rst(analyser_rst),
        .write_enable(visual_write),.write_address(visual_write_address),.write_value(visual_write_data),
        .frame_done(frame_done),.frame_ack(frame_ack),.pixel_clk(pixel_clk),.pixel_rst(video_rst),
        .vertical_blank(blank),.read_address(visual_read_address),.read_value(visual_read_data),.ready(visual_ready));
    wire [23:0] rgb; wire pixel_de,pixel_hs,pixel_vs;
    instrument_screen screen(.clk(pixel_clk),.rst(video_rst),.x(x),.y(y),.de(de),.hs(hs),.vs(vs),
        .vertical_blank(blank),.status(pixel_status),.visual_ready(visual_ready),.visual_data(visual_read_data),
        .visual_address(visual_read_address),.rgb(rgb),.out_de(pixel_de),.out_hs(pixel_hs),.out_vs(pixel_vs));
    video_output transmitter(.pixel_clk(pixel_clk),.serial_clk(serial_clk),.rst(video_rst),
        .rgb(rgb),.de(pixel_de),.hs(pixel_hs),.vs(pixel_vs),.tmds_p(tmds_p),.tmds_n(tmds_n),
        .tmds_clock_p(tmds_clock_p),.tmds_clock_n(tmds_clock_n));
    // Dock HDMI level-shifter enable; it is not a sensed hot-plug input.
    assign hpd_en=1'b1;
endmodule
