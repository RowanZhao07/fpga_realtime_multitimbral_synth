`timescale 1ns/1ps
module instrument_top (
    input wire ref_clk, // On-board 50 MHz crystal, V22.
    inout wire mpr_scl, mpr_sda, mpr_b_scl, mpr_b_sda,
    inout wire pressure_scl, pressure_sda,
    output wire dac_bck, dac_lrck, dac_din,
    output wire [7:0] led,
    output wire led_ser,led_srclk,led_rclk,led_oe_n,
    input wire control_rx,output wire control_tx,
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
    wire [17:0] touched;
    wire [1:0] chip_online;
    mpr121_controller touch(.clk(clk),.rst(rst),.scl(mpr_scl),.sda(mpr_sda),
        .scl_b(mpr_b_scl),.sda_b(mpr_b_sda),
        .online(online),.chip_online(chip_online),.touched(touched));
    wire pressure_online;
    wire [11:0] pressure_mv;
    ads1115_controller pressure(.clk(clk),.rst(rst),.scl(pressure_scl),.sda(pressure_sda),
        .online(pressure_online),.millivolts(pressure_mv),.sample_valid());
    wire [52:0] core_status;
    wire [44:0] control_status;
    wire [83:0] uart_diagnostics;
    wire diagnostics_visible;
    wire [7:0] volume_low;
    wire [203:0] status={volume_low,diagnostics_visible,uart_diagnostics,control_status,pressure_online,pressure_mv,core_status};
    wire [203:0] pixel_status;
    wire signed [15:0] monitor_sample;
    wire monitor_ce;
    wire [7:0] key_lights;
    instrument_core core(.clk(clk),.rst(rst),.online(online),.touched(touched),.chip_online(chip_online),
        .pressure_online(pressure_online),.pressure_mv(pressure_mv),
        .control_rx(control_rx),.control_tx(control_tx),.control_status(control_status),.uart_diagnostics(uart_diagnostics),
        .diagnostics_visible(diagnostics_visible),
        .dac_bck(dac_bck),.dac_lrck(dac_lrck),.dac_din(dac_din),.led(led),
        .key_lights(key_lights),.volume_low(volume_low),.status(core_status),.monitor_sample(monitor_sample),.monitor_ce(monitor_ce));
    hc595_driver key_led_driver(.clk(clk),.rst(rst),.lights(key_lights),
        .serial_data(led_ser),.shift_clock(led_srclk),.latch_clock(led_rclk),.oe_n(led_oe_n));
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
    status_mailbox #(.WIDTH(204)) mailbox(.src_clk(clk),.src_rst(analyser_rst),.src_data(status),
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
