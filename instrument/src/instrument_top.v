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
    wire monitor_ce; wire [63:0] voice_levels,pixel_levels;
    instrument_core core(.clk(clk),.rst(rst),.online(online),.touched(touched),
        .dac_bck(dac_bck),.dac_lrck(dac_lrck),.dac_din(dac_din),.led(led),
        .status(status),.monitor_sample(monitor_sample),.monitor_ce(monitor_ce),.voice_levels(voice_levels));
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
    status_mailbox #(.WIDTH(104)) mailbox(.src_clk(clk),.src_rst(analyser_rst),
        .src_data({voice_levels,status}),.dst_clk(pixel_clk),.dst_rst(video_rst),
        .dst_data({pixel_levels,pixel_status}));
    wire [10:0] x; wire [9:0] y;
    wire de,hs,vs,blank;
    video_timing timing(.clk(pixel_clk),.rst(video_rst),.x(x),.y(y),.de(de),.hs(hs),.vs(vs),.vertical_blank(blank));
    wire visual_write,frame_done,frame_ack,visual_ready;
    wire [9:0] visual_write_address,visual_read_address;
    wire [7:0] visual_write_data,visual_read_data;
    wire fft_valid,fft_start; wire [8:0] fft_bin; wire [15:0] fft_magnitude;
    wire signed [15:0] fft_real,fft_imag; wire [31:0] fft_frame_sample_index;
    // Attach an algorithm here. External input is intentionally idle until an ADC
    // receiver exists; playback is a reference stream, not microphone recognition.
    wire analysis_ce,analysis_external,result_ready,result_update,latest_valid;
    wire signed [15:0] analysis_sample; wire [31:0] analysis_index;
    wire [95:0] latest_result;wire [31:0] analysis_rate_numerator,analysis_rate_denominator;
    listening_analysis_port analysis_port(.clk(clk),.rst(analyser_rst),
        .playback_ce(monitor_ce),.playback_sample(monitor_sample),
        .external_ce(1'b0),.external_sample(16'sd0),
        .analysis_ce(analysis_ce),.analysis_sample(analysis_sample),
        .analysis_external(analysis_external),.sample_index(analysis_index),
        .analysis_rate_numerator(analysis_rate_numerator),.analysis_rate_denominator(analysis_rate_denominator),
        .result_valid(1'b0),.result_payload(96'd0),.result_ready(result_ready),
        .latest_result(latest_result),.latest_valid(latest_valid),.result_update(result_update));
    audio_spectrum #(.ENABLE_SCOPE(1'b0)) analyser(.clk(clk),.rst(analyser_rst),.sample_ce(monitor_ce),.sample(monitor_sample),
        .write_enable(visual_write),.write_address(visual_write_address),.write_value(visual_write_data),
        .frame_done(frame_done),.frame_ack(frame_ack),.bin_valid(fft_valid),.bin_index(fft_bin),
        .bin_magnitude(fft_magnitude),.bin_real(fft_real),.bin_imag(fft_imag),.bin_frame_start(fft_start),.frame_sample_index(fft_frame_sample_index));
    visual_buffer #(.ADDRESS_BITS(9)) visual_memory(.audio_clk(clk),.audio_rst(analyser_rst),
        .write_enable(visual_write),.write_address(visual_write_address[8:0]),.write_value(visual_write_data),
        .frame_done(frame_done),.frame_ack(frame_ack),.pixel_clk(pixel_clk),.pixel_rst(video_rst),
        .vertical_blank(blank),.read_address(visual_read_address[8:0]),.read_value(visual_read_data),.ready(visual_ready));
    wire scope_write,scope_done,scope_ack,scope_ready;
    wire [8:0] scope_write_address,scope_read_address;
    wire [7:0] scope_write_data,scope_read_data;
    waveform_capture scope(.clk(clk),.rst(analyser_rst),.sample_ce(monitor_ce),.sample(monitor_sample),
        .write_enable(scope_write),.write_address(scope_write_address),.write_value(scope_write_data),
        .frame_done(scope_done),.frame_ack(scope_ack));
    visual_buffer #(.ADDRESS_BITS(9)) scope_memory(.audio_clk(clk),.audio_rst(analyser_rst),
        .write_enable(scope_write),.write_address(scope_write_address),.write_value(scope_write_data),
        .frame_done(scope_done),.frame_ack(scope_ack),.pixel_clk(pixel_clk),.pixel_rst(video_rst),
        .vertical_blank(blank),.read_address(scope_read_address),.read_value(scope_read_data),.ready(scope_ready));
    wire [23:0] rgb; wire pixel_de,pixel_hs,pixel_vs;
    instrument_screen screen(.clk(pixel_clk),.rst(video_rst),.x(x),.y(y),.de(de),.hs(hs),.vs(vs),
        .vertical_blank(blank),.status(pixel_status),.voice_levels(pixel_levels),
        .scope_ready(scope_ready),.scope_data(scope_read_data),.scope_address(scope_read_address),
        .visual_ready(visual_ready),.visual_data(visual_read_data),
        .visual_address(visual_read_address),.rgb(rgb),.out_de(pixel_de),.out_hs(pixel_hs),.out_vs(pixel_vs));
    video_output transmitter(.pixel_clk(pixel_clk),.serial_clk(serial_clk),.rst(video_rst),
        .rgb(rgb),.de(pixel_de),.hs(pixel_hs),.vs(pixel_vs),.tmds_p(tmds_p),.tmds_n(tmds_n),
        .tmds_clock_p(tmds_clock_p),.tmds_clock_n(tmds_clock_n));
    // Dock HDMI level-shifter enable; it is not a sensed hot-plug input.
    assign hpd_en=1'b1;
endmodule
