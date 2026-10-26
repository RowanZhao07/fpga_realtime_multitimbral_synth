`timescale 1ns/1ps
module instrument_top #(
`ifdef INSTRUMENT_TOUCH_DEBUG
    parameter TOUCH_DEBUG=1'b1,
`else
    parameter TOUCH_DEBUG=1'b0,
`endif
`ifdef INSTRUMENT_EC11
    parameter ENABLE_EC11=1'b1,
`else
    parameter ENABLE_EC11=1'b0,
`endif
`ifdef INSTRUMENT_JOYSTICK
    parameter ENABLE_JOYSTICK=1'b1,
`else
    parameter ENABLE_JOYSTICK=1'b0,
`endif
    parameter integer JOYSTICK_BUTTON_CLOCKS=500000,
    parameter JOYSTICK_REVERSE=1'b0, JOYSTICK_BUTTON_ACTIVE_LOW=1'b1,
    parameter integer JOYSTICK_CENTER_MV=1650,
    parameter integer PRESSURE_ZERO_MV=0,PRESSURE_FULL_MV=3235,
    parameter integer EC11_FILTER_CLOCKS=50000,
    parameter integer EC11_BUTTON_CLOCKS=500000,
    parameter integer EC11_TRANSITIONS_PER_STEP=2,
    parameter EC11_REVERSE=1'b0
)(
    input wire joystick_sw_n,
    input wire encoder_a,encoder_b,encoder_sw_n,
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
        .online(online),.chip_online(chip_online),.touched(touched),.diagnostics());
    wire pressure_online,pressure_sample_valid;
    wire [11:0] pressure_mv;
    wire joystick_online,joystick_sample_valid;
    wire [11:0] joystick_mv;
    generate if(ENABLE_JOYSTICK) begin: shared_adc
        ads1115_scanner adc(.clk(clk),.rst(rst),.scl(pressure_scl),.sda(pressure_sda),
            .pressure_online(pressure_online),.pressure_mv(pressure_mv),.pressure_valid(pressure_sample_valid),
            .joystick_online(joystick_online),.joystick_mv(joystick_mv),.joystick_valid(joystick_sample_valid));
    end else begin: pressure_only
        ads1115_controller pressure(.clk(clk),.rst(rst),.scl(pressure_scl),.sda(pressure_sda),
            .online(pressure_online),.millivolts(pressure_mv),.sample_valid(pressure_sample_valid));
        assign joystick_online=0;assign joystick_sample_valid=0;assign joystick_mv=0;
    end endgenerate
    wire [52:0] core_status;
    wire [44:0] control_status;
    wire [31:0] performance_info,pixel_performance;
    wire [83:0] uart_diagnostics;
    wire diagnostics_visible;
    wire [7:0] volume_low;
    wire [1:0] octave_select,pixel_octave;
    wire [203:0] status={volume_low,diagnostics_visible,uart_diagnostics,control_status,pressure_online,pressure_mv,core_status};
    wire [203:0] pixel_status;
    wire signed [15:0] monitor_sample;
    wire monitor_ce;
    wire [103:0] voice_levels,pixel_levels;
    wire [12:0] key_lights;
    wire [5:0] sustain_info,pixel_sustain;
    instrument_core #(.ENABLE_EC11(ENABLE_EC11),.ENABLE_JOYSTICK(ENABLE_JOYSTICK),
        .JOYSTICK_BUTTON_CLOCKS(JOYSTICK_BUTTON_CLOCKS),.JOYSTICK_REVERSE(JOYSTICK_REVERSE),
        .JOYSTICK_BUTTON_ACTIVE_LOW(JOYSTICK_BUTTON_ACTIVE_LOW),.JOYSTICK_CENTER_MV(JOYSTICK_CENTER_MV),
        .PRESSURE_ZERO_MV(PRESSURE_ZERO_MV),.PRESSURE_FULL_MV(PRESSURE_FULL_MV),
        .EC11_FILTER_CLOCKS(EC11_FILTER_CLOCKS),.EC11_BUTTON_CLOCKS(EC11_BUTTON_CLOCKS),
        .EC11_TRANSITIONS_PER_STEP(EC11_TRANSITIONS_PER_STEP),.EC11_REVERSE(EC11_REVERSE),.DEFAULT_SUSTAIN(TOUCH_DEBUG),
        .DEFAULT_TIMBRE((TOUCH_DEBUG || ENABLE_EC11) ? 2'd1 : 2'd0)) core(.encoder_a(encoder_a),.encoder_b(encoder_b),.encoder_sw_n(encoder_sw_n),
        .sustain_info(sustain_info),.sustain_request(1'b0),.clk(clk),.rst(rst),.online(online),.touched(touched),.chip_online(chip_online),
        .joystick_online(joystick_online),.joystick_sample_valid(joystick_sample_valid),
        .joystick_mv(joystick_mv),.joystick_sw_n(joystick_sw_n),.pressure_sample_valid(pressure_sample_valid),
        .pressure_online(pressure_online),.pressure_mv(pressure_mv),
        .control_rx(control_rx),.control_tx(control_tx),.control_status(control_status),.performance_info(performance_info),.uart_diagnostics(uart_diagnostics),
        .diagnostics_visible(diagnostics_visible),
        .dac_bck(dac_bck),.dac_lrck(dac_lrck),.dac_din(dac_din),.led(led),
        .key_lights(key_lights),.volume_low(volume_low),.octave_select(octave_select),.status(core_status),.monitor_sample(monitor_sample),.monitor_ce(monitor_ce),
        .voice_levels(voice_levels));
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
    status_mailbox #(.WIDTH(348)) mailbox(.src_clk(clk),.src_rst(analyser_rst),.src_data({sustain_info,performance_info,octave_select,voice_levels,status}),
        .dst_clk(pixel_clk),.dst_rst(video_rst),.dst_data({pixel_sustain,pixel_performance,pixel_octave,pixel_levels,pixel_status}));
    wire [10:0] x; wire [9:0] y;
    wire de,hs,vs,blank;
    video_timing timing(.clk(pixel_clk),.rst(video_rst),.x(x),.y(y),.de(de),.hs(hs),.vs(vs),.vertical_blank(blank));
    wire visual_write,frame_done,frame_ack,visual_ready;
    wire [9:0] visual_write_address,visual_read_address;
    wire [7:0] visual_write_data,visual_read_data;
    audio_spectrum #(.ENABLE_SCOPE(1'b0)) analyser(.clk(clk),.rst(analyser_rst),.sample_ce(monitor_ce),.sample(monitor_sample),
        .write_enable(visual_write),.write_address(visual_write_address),.write_value(visual_write_data),
        .frame_done(frame_done),.frame_ack(frame_ack),.bin_valid(),.bin_index(),.bin_magnitude());
    visual_buffer #(.ADDRESS_BITS(9)) visual_memory(.audio_clk(clk),.audio_rst(analyser_rst),
        .write_enable(visual_write),.write_address(visual_write_address[8:0]),.write_value(visual_write_data),
        .frame_done(frame_done),.frame_ack(frame_ack),.pixel_clk(pixel_clk),.pixel_rst(video_rst),
        .vertical_blank(blank),.read_address(visual_read_address[8:0]),.read_value(visual_read_data),.ready(visual_ready));
    // Scope and FFT publish independently, each swapping only at vertical blank.
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
    instrument_screen #(.ENABLE_JOYSTICK(ENABLE_JOYSTICK),.ENABLE_EC11(ENABLE_EC11),.TOUCH_DEBUG(TOUCH_DEBUG)) screen(.sustain_info(pixel_sustain),.clk(pixel_clk),.rst(video_rst),.x(x),.y(y),.de(de),.hs(hs),.vs(vs),
        .vertical_blank(blank),.status(pixel_status),.performance_info(pixel_performance),.voice_levels(pixel_levels),.octave_select(pixel_octave),
        .scope_ready(scope_ready),.scope_data(scope_read_data),.scope_address(scope_read_address),
        .visual_ready(visual_ready),.visual_data(visual_read_data),
        .visual_address(visual_read_address),.rgb(rgb),.out_de(pixel_de),.out_hs(pixel_hs),.out_vs(pixel_vs));
    video_output transmitter(.pixel_clk(pixel_clk),.serial_clk(serial_clk),.rst(video_rst),
        .rgb(rgb),.de(pixel_de),.hs(pixel_hs),.vs(pixel_vs),.tmds_p(tmds_p),.tmds_n(tmds_n),
        .tmds_clock_p(tmds_clock_p),.tmds_clock_n(tmds_clock_n));
    // Dock HDMI level-shifter enable; it is not a sensed hot-plug input.
    assign hpd_en=1'b1;
endmodule
