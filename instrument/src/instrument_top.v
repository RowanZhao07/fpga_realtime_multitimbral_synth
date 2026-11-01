`timescale 1ns/1ps
module instrument_top #(
`ifdef INSTRUMENT_TOUCH_ISOLATION
    parameter TOUCH_ISOLATION=1'b1,
`else
    parameter TOUCH_ISOLATION=1'b0,
`endif
`ifdef INSTRUMENT_EXPRESSION
    parameter ENABLE_EXPRESSION=1'b1,
`else
    parameter ENABLE_EXPRESSION=1'b0,
`endif
`ifdef INSTRUMENT_WIRING_DEBUG
    parameter WIRING_DEBUG=1'b1,
`else
    parameter WIRING_DEBUG=1'b0,
`endif
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
    output wire joystick_vcc,
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
    // J13-9/B16: supply only the measured low-current joystick after FPGA
    // configuration. Keep it steady through PLL reset / ADC reconnects.
    // Legacy profiles leave this pad high impedance. Never connect a power rail
    // or any other load to it; DRIVE is not a short-circuit current limiter.
    assign joystick_vcc=ENABLE_JOYSTICK ? 1'b1 : 1'bz;
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
    wire [31:0] touch_diagnostics;
    wire [1:0] touch_failure_event;
    wire isolate_core_run,isolate_i2s_run,isolate_visual_run,isolate_led_run;
    wire [255:0] isolate_report;
    wire [279:0] isolate_status,pixel_isolate;
    generate if(TOUCH_ISOLATION) begin: isolation
        touch_isolation_control control(.clk(clk),.rst(rst),.chip_online(chip_online),
            .failure_event(touch_failure_event),.error_a(touch_diagnostics[3:0]),.error_b(touch_diagnostics[19:16]),
            .core_run(isolate_core_run),.i2s_run(isolate_i2s_run),.visual_run(isolate_visual_run),
            .led_run(isolate_led_run),.report(isolate_report));
    end else begin: no_isolation
        assign isolate_core_run=1;assign isolate_i2s_run=1;assign isolate_visual_run=1;assign isolate_led_run=1;
        assign isolate_report=0;
    end endgenerate
    wire [15:0] adc_diagnostics;
    mpr121_controller touch(.clk(clk),.rst(rst),.scl(mpr_scl),.sda(mpr_sda),
        .scl_b(mpr_b_scl),.sda_b(mpr_b_sda),
        .online(online),.chip_online(chip_online),.touched(touched),.diagnostics(touch_diagnostics),.failure_event(touch_failure_event));
    wire pressure_online,pressure_sample_valid;
    wire [11:0] pressure_mv;
    wire joystick_online,joystick_sample_valid;
    wire [11:0] joystick_mv;
    wire y_online,y_sample_valid;
    wire [11:0] y_mv;
    generate if(ENABLE_JOYSTICK) begin: shared_adc
        ads1115_scanner #(.ENABLE_Y(ENABLE_EXPRESSION)) adc(.clk(clk),.rst(rst),.scl(pressure_scl),.sda(pressure_sda),
            .y_online(y_online),.y_mv(y_mv),.y_valid(y_sample_valid),
            .pressure_online(pressure_online),.pressure_mv(pressure_mv),.pressure_valid(pressure_sample_valid),
            .joystick_online(joystick_online),.joystick_mv(joystick_mv),.joystick_valid(joystick_sample_valid),.diagnostics(adc_diagnostics));
    end else begin: pressure_only
        ads1115_controller pressure(.clk(clk),.rst(rst),.scl(pressure_scl),.sda(pressure_sda),
            .online(pressure_online),.millivolts(pressure_mv),.sample_valid(pressure_sample_valid));
        assign joystick_online=0;assign joystick_sample_valid=0;assign joystick_mv=0;
        assign y_online=0;assign y_sample_valid=0;assign y_mv=0;
        assign adc_diagnostics=0;
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
    wire core_bck,core_lrck,core_din;
    generate if(TOUCH_ISOLATION) begin: isolate_audio_pins
        reg enabled=0;
        // Switch external BCK only while its internal source is low. The
        // transmitter/sample enable keep running when only the pins are muted.
        always @(posedge clk) begin
            if(rst) enabled<=0;
            else if(!core_bck) enabled<=isolate_i2s_run;
        end
        assign dac_bck=enabled ? core_bck : 1'b0;
        assign dac_lrck=enabled ? core_lrck : 1'b1;
        assign dac_din=enabled ? core_din : 1'b0;
    end else begin: direct_audio_pins
        assign dac_bck=core_bck;assign dac_lrck=core_lrck;assign dac_din=core_din;
    end endgenerate
    instrument_core #(.ENABLE_EXPRESSION(ENABLE_EXPRESSION),.ENABLE_EC11(ENABLE_EC11),.ENABLE_JOYSTICK(ENABLE_JOYSTICK),
        .JOYSTICK_BUTTON_CLOCKS(JOYSTICK_BUTTON_CLOCKS),.JOYSTICK_REVERSE(JOYSTICK_REVERSE),
        .JOYSTICK_BUTTON_ACTIVE_LOW(JOYSTICK_BUTTON_ACTIVE_LOW),.JOYSTICK_CENTER_MV(JOYSTICK_CENTER_MV),
        .PRESSURE_ZERO_MV(PRESSURE_ZERO_MV),.PRESSURE_FULL_MV(PRESSURE_FULL_MV),
        .EC11_FILTER_CLOCKS(EC11_FILTER_CLOCKS),.EC11_BUTTON_CLOCKS(EC11_BUTTON_CLOCKS),
        .EC11_TRANSITIONS_PER_STEP(EC11_TRANSITIONS_PER_STEP),.EC11_REVERSE(EC11_REVERSE),.DEFAULT_SUSTAIN(TOUCH_DEBUG),
        .DEFAULT_TIMBRE((TOUCH_DEBUG || ENABLE_EC11) ? 2'd1 : 2'd0)) core(.encoder_a(encoder_a),.encoder_b(encoder_b),.encoder_sw_n(encoder_sw_n),
        // The temporary wiring profile keeps synthesis/control in reset (silent).
        // Touch/ADC controllers and their live diagnostics remain independent.
        .sustain_info(sustain_info),.sustain_request(1'b0),.clk(clk),.rst(rst || WIRING_DEBUG || !isolate_core_run),.online(online),.touched(touched),.chip_online(chip_online),
        .joystick_online(joystick_online),.joystick_sample_valid(joystick_sample_valid),
        .y_online(y_online),.y_mv(y_mv),.y_sample_valid(y_sample_valid),
        .joystick_mv(joystick_mv),.joystick_sw_n(joystick_sw_n),.pressure_sample_valid(pressure_sample_valid),
        .pressure_online(pressure_online),.pressure_mv(pressure_mv),
        .control_rx(control_rx),.control_tx(control_tx),.control_status(control_status),.performance_info(performance_info),.uart_diagnostics(uart_diagnostics),
        .diagnostics_visible(diagnostics_visible),
        .dac_bck(core_bck),.dac_lrck(core_lrck),.dac_din(core_din),.led(led),
        .key_lights(key_lights),.volume_low(volume_low),.octave_select(octave_select),.status(core_status),.monitor_sample(monitor_sample),.monitor_ce(monitor_ce),
        .voice_levels(voice_levels));
    hc595_driver key_led_driver(.clk(clk),.rst(rst || !isolate_led_run),.lights(key_lights),
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
    wire workload_visual_rst=analyser_rst || !isolate_visual_run;
    reg [1:0] visual_run_sync=0;
    always @(posedge pixel_clk) begin
        if(video_rst) visual_run_sync<=0;
        else visual_run_sync<={visual_run_sync[0],isolate_visual_run};
    end
    wire workload_pixel_rst=video_rst || (TOUCH_ISOLATION && !visual_run_sync[1]);
    // Keep fault evidence in the playing expression image too. Reloading the
    // silent wiring image resets this history and changes the active workload.
    wire [59:0] wiring_status=(WIRING_DEBUG || ENABLE_EXPRESSION || TOUCH_ISOLATION) ?
        {joystick_mv,adc_diagnostics,touch_diagnostics} : 60'd0;
    wire [59:0] pixel_wiring;
    status_mailbox #(.WIDTH(688)) mailbox(.src_clk(clk),.src_rst(analyser_rst),.src_data({isolate_status,wiring_status,sustain_info,performance_info,octave_select,voice_levels,status}),
        .dst_clk(pixel_clk),.dst_rst(video_rst),.dst_data({pixel_isolate,pixel_wiring,pixel_sustain,pixel_performance,pixel_octave,pixel_levels,pixel_status}));
    wire [10:0] x; wire [9:0] y;
    wire de,hs,vs,blank;
    video_timing timing(.clk(pixel_clk),.rst(video_rst),.x(x),.y(y),.de(de),.hs(hs),.vs(vs),.vertical_blank(blank));
    wire visual_write,frame_done,frame_ack,visual_ready;
    wire [9:0] visual_write_address,visual_read_address;
    wire [7:0] visual_write_data,visual_read_data;
    audio_spectrum #(.ENABLE_SCOPE(1'b0)) analyser(.clk(clk),.rst(workload_visual_rst),.sample_ce(monitor_ce),.sample(monitor_sample),
        .write_enable(visual_write),.write_address(visual_write_address),.write_value(visual_write_data),
        .frame_done(frame_done),.frame_ack(frame_ack),.bin_valid(),.bin_index(),.bin_magnitude());
    visual_buffer #(.ADDRESS_BITS(9)) visual_memory(.audio_clk(clk),.audio_rst(workload_visual_rst),
        .write_enable(visual_write),.write_address(visual_write_address[8:0]),.write_value(visual_write_data),
        .frame_done(frame_done),.frame_ack(frame_ack),.pixel_clk(pixel_clk),.pixel_rst(workload_pixel_rst),
        .vertical_blank(blank),.read_address(visual_read_address[8:0]),.read_value(visual_read_data),.ready(visual_ready));
    // Fixed 3x visual zoom is shared by the waveform and both XY axes only.
    // Keep the FFT and audio output connected to unmodified monitor_sample.
    wire signed [15:0] display_sample;
    display_gain #(.ENABLE_3X(ENABLE_EXPRESSION)) visual_zoom(
        .sample(monitor_sample),.scaled(display_sample));
    // Scope and FFT publish independently, each swapping only at vertical blank.
    wire scope_write,scope_done,scope_ack,scope_ready;
    wire [8:0] scope_write_address,scope_read_address;
    wire [7:0] scope_write_data,scope_read_data;
    waveform_capture scope(.clk(clk),.rst(workload_visual_rst),.sample_ce(monitor_ce),.sample(display_sample),
        .write_enable(scope_write),.write_address(scope_write_address),.write_value(scope_write_data),
        .frame_done(scope_done),.frame_ack(scope_ack));
    visual_buffer #(.ADDRESS_BITS(9)) scope_memory(.audio_clk(clk),.audio_rst(workload_visual_rst),
        .write_enable(scope_write),.write_address(scope_write_address),.write_value(scope_write_data),
        .frame_done(scope_done),.frame_ack(scope_ack),.pixel_clk(pixel_clk),.pixel_rst(workload_pixel_rst),
        .vertical_blank(blank),.read_address(scope_read_address),.read_value(scope_read_data),.ready(scope_ready));
    wire liss_ready,liss_data;
    wire [13:0] liss_address;
    generate if(ENABLE_EXPRESSION && !TOUCH_ISOLATION && !WIRING_DEBUG) begin: xy_visual
        lissajous_capture xy(.audio_clk(clk),.audio_rst(workload_visual_rst),
            .sample_ce(monitor_ce),.sample(display_sample),.pixel_clk(pixel_clk),
            .pixel_rst(workload_pixel_rst),.vertical_blank(blank),.read_address(liss_address),
            .read_value(liss_data),.ready(liss_ready));
    end else begin: no_xy_visual
        assign liss_ready=0;assign liss_data=0;
    end endgenerate
    wire [23:0] rgb; wire pixel_de,pixel_hs,pixel_vs;
    generate if(TOUCH_ISOLATION) begin: observe_workload
        reg [7:0] fft_checksum=0,scope_checksum=0,fft_frames=0;
        // Observe actual arithmetic outputs so synthesis cannot remove the
        // FFT/scope simply because this profile displays a results table.
        always @(posedge clk) begin
            if(rst) begin fft_checksum<=0;scope_checksum<=0;fft_frames<=0;end
            else if(!workload_visual_rst) begin
                if(visual_write) fft_checksum<={fft_checksum[6:0],fft_checksum[7]} ^ visual_write_data;
                if(scope_write) scope_checksum<={scope_checksum[6:0],scope_checksum[7]} ^ scope_write_data;
                if(frame_done && frame_ack) fft_frames<=fft_frames+1'b1;
            end
        end
        assign isolate_status={scope_checksum,fft_frames,fft_checksum,isolate_report};
    end else begin: no_workload_observer
        assign isolate_status=0;
    end endgenerate
    instrument_screen #(.TOUCH_ISOLATION(TOUCH_ISOLATION),.ENABLE_EXPRESSION(ENABLE_EXPRESSION),.WIRING_DEBUG(WIRING_DEBUG),.ENABLE_JOYSTICK(ENABLE_JOYSTICK),.ENABLE_EC11(ENABLE_EC11),.TOUCH_DEBUG(TOUCH_DEBUG)) screen(.isolation_status(pixel_isolate),.wiring_status(pixel_wiring),.sustain_info(pixel_sustain),.clk(pixel_clk),.rst(video_rst),.x(x),.y(y),.de(de),.hs(hs),.vs(vs),
        .vertical_blank(blank),.status(pixel_status),.performance_info(pixel_performance),.voice_levels(pixel_levels),.octave_select(pixel_octave),
        .scope_ready(scope_ready),.scope_data(scope_read_data),.scope_address(scope_read_address),
        .liss_ready(liss_ready),.liss_data(liss_data),.liss_address(liss_address),
        .visual_ready(visual_ready),.visual_data(visual_read_data),
        .visual_address(visual_read_address),.rgb(rgb),.out_de(pixel_de),.out_hs(pixel_hs),.out_vs(pixel_vs));
    video_output transmitter(.pixel_clk(pixel_clk),.serial_clk(serial_clk),.rst(video_rst),
        .rgb(rgb),.de(pixel_de),.hs(pixel_hs),.vs(pixel_vs),.tmds_p(tmds_p),.tmds_n(tmds_n),
        .tmds_clock_p(tmds_clock_p),.tmds_clock_n(tmds_clock_n));
    // Dock HDMI level-shifter enable; it is not a sensed hot-plug input.
    assign hpd_en=1'b1;
endmodule
