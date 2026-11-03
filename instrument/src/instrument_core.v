`timescale 1ns/1ps
module instrument_core #(
    parameter ENABLE_ECHO=1'b0,
    parameter ENABLE_JOYSTICK=1'b0,
    parameter ENABLE_EXPRESSION=1'b0,
    parameter integer JOYSTICK_BUTTON_CLOCKS=500000,
    parameter JOYSTICK_REVERSE=1'b0, JOYSTICK_BUTTON_ACTIVE_LOW=1'b1,
    parameter integer JOYSTICK_CENTER_MV=1650,
    parameter integer PRESSURE_ZERO_MV=0,PRESSURE_FULL_MV=3235,
    parameter ENABLE_EC11=1'b0,
    parameter integer EC11_FILTER_CLOCKS=50000,
    parameter integer EC11_TRANSITIONS_PER_STEP=2,
    parameter EC11_REVERSE=1'b0,
    parameter integer EC11_BUTTON_CLOCKS=500000,
    parameter DEFAULT_SUSTAIN=1'b0,
    parameter [2:0] DEFAULT_TIMBRE=3'd0,
    parameter integer UART_CLOCKS_PER_BIT=5208,
    parameter integer LAMP_TEST_CLOCKS=250000000
)(
    // Future pedal adapter supplies a synchronized, debounced level in clk domain.
    input wire sustain_request,
    input wire encoder_a,encoder_b,encoder_sw_n,
    output wire [5:0] sustain_info,
    output wire sustain_active,
    input wire clk, rst, online,
    input wire [17:0] touched,
    input wire [1:0] chip_online,
    input wire joystick_online,joystick_sample_valid,joystick_sw_n,
    input wire [11:0] joystick_mv,
    input wire y_online,y_sample_valid,
    input wire [11:0] y_mv,
    input wire pressure_sample_valid,
    input wire pressure_online,
    input wire [11:0] pressure_mv,
    input wire control_rx,output wire control_tx,
    output wire [44:0] control_status,
    output wire [32:0] performance_info,
    output wire [17:0] metronome_info,
    output wire [83:0] uart_diagnostics,
    output reg diagnostics_visible=0,
    output wire dac_bck, dac_lrck, dac_din,
    output wire [7:0] led,
    output wire [12:0] key_lights,
    output wire [7:0] volume_low,
    output wire [1:0] octave_select,
    output wire [52:0] status, output wire signed [15:0] monitor_sample,
    output wire monitor_ce, output wire [103:0] voice_levels
);
    wire echo_enabled,guide_enabled,y_enabled,y_armed;
    wire [1:0] effect_mode;
    wire signed [15:0] pitch_bend;
    wire [2:0] guide_target;
    wire [8:0] guide_position;
    wire [1:0] guide_octave;
    wire guide_rest,guide_playing,guide_finished;
    wire [5:0] voice_count;
    wire engine_overrun;
    wire sample_ce, vibrato, spectrum_mode, valid, clipped,limited;
    wire [12:0] gates,active;
    wire [2:0] timbre;
    wire [1:0] selected_octave;
    // The eight-sine calibration always uses its original C4..C5 tuning.
    assign octave_select=spectrum_mode ? 2'd1 : (guide_enabled && online) ? guide_octave : selected_octave;
    wire [12:0] volume;
    assign volume_low=volume[7:0];
    wire command_valid,input_error,command_ok,custom_score;
    wire [7:0] command,accepted,rejected;
    wire [15:0] command_value;
    wire [12:0] guide_mask;
    wire [9:0] guide_length;
    reg [7:0] bpm=93;
    localparam integer LAMP_TIMER_BITS=LAMP_TEST_CLOCKS>1 ? $clog2(LAMP_TEST_CLOCKS+1) : 1;
    reg [LAMP_TIMER_BITS-1:0] lamp_test_left=0;
    reg [12:0] lamp_test_mask=0;
    wire lamp_test=(lamp_test_left!=0);
    // Logical notes are K0..K7,S0..S4; PCB LED1..13 are chromatic C4..C5.
    function [12:0] pcb_lamps;
        input [12:0] notes;
        begin
            pcb_lamps={notes[7],notes[6],notes[12],notes[5],notes[11],
                notes[4],notes[10],notes[3],notes[2],notes[9],notes[1],notes[8],notes[0]};
        end
    endfunction
    uart_control #(.ENABLE_EXPRESSION(ENABLE_EXPRESSION),.CLOCKS_PER_BIT(UART_CLOCKS_PER_BIT)) remote_control(
        .clk(clk),.rst(rst),.rx(control_rx),.tx(control_tx),.command_ok(command_ok),
        .command_valid(command_valid),.command(command),.value(command_value),
        .input_error(input_error),.accepted(accepted),.rejected(rejected),.diagnostics(uart_diagnostics));
    always @(posedge clk) begin
        if(rst) begin bpm<=93;diagnostics_visible<=0;end
        else if(command_valid) case(command)
            "B":bpm<=command_value[7:0];
            "R":bpm<=93;
            "D":diagnostics_visible<=command_value[0];
            default:begin end
        endcase
    end
    assign control_status={rejected,accepted,custom_score,(guide_length>127 ? 7'd127 : guide_length[6:0]),bpm,guide_mask};
    // Append the timbre bank above the existing status layout; lower fields stay compatible.
    assign performance_info={timbre[2],voice_count,guide_length,guide_position,guide_rest,guide_playing,guide_finished,
        (ENABLE_EXPRESSION ? effect_mode : 2'b0),y_armed,y_enabled};
    // A bounded, silent hardware diagnostic independent of touch detection.
    // Preserve L0..255 white-key masks and L256 cancel. J0..8191 addresses
    // physical LED1..13 directly; J8192 cancels. Both expire after five seconds.
    always @(posedge clk) begin
        if(rst) begin lamp_test_left<=0;lamp_test_mask<=0;end
        else if(command_valid && command=="L") begin
            lamp_test_mask<=pcb_lamps({5'b0,command_value[7:0]});
            lamp_test_left<=command_value==256 ? 0 : LAMP_TEST_CLOCKS;
        end else if(command_valid && command=="J") begin
            lamp_test_mask<=command_value[12:0];
            lamp_test_left<=command_value==8192 ? 0 : LAMP_TEST_CLOCKS;
        end else if(lamp_test) lamp_test_left<=lamp_test_left-1'b1;
    end
    // One pressure pad is a global expression control. Q9 gain spans 1/4..1,
    // reaching unity at the measured 3235 mV by default; C1/C2 set maximum volume.
    wire [9:0] legacy_pressure_gain;
    pressure_mapping pressure_curve(.millivolts(pressure_mv),.gain(legacy_pressure_gain),.bar_width());
    wire [9:0] smooth_pressure_gain;
    wire [9:0] pressure_gain=ENABLE_JOYSTICK ? smooth_pressure_gain : legacy_pressure_gain;
    generate if(ENABLE_JOYSTICK) begin: pressure_filter
        pressure_expression #(.ZERO_MV(PRESSURE_ZERO_MV),.FULL_MV(PRESSURE_FULL_MV)) expression(
            .clk(clk),.rst(rst),.online(pressure_online),.sample_valid(pressure_sample_valid),
            .sample_ce(sample_ce),.millivolts(pressure_mv),.gain(smooth_pressure_gain),.filtered_mv());
    end else begin: no_pressure_filter
        assign smooth_pressure_gain=10'd512;
    end endgenerate
    wire [22:0] pressure_product=volume*pressure_gain;
    wire [12:0] expressive_volume=(ENABLE_JOYSTICK || pressure_online) ? pressure_product[21:9] : volume;
    wire signed [18:0] mixed;
    wire signed [15:0] sample,tone_sample,click_sample;
    wire metro_enabled,metro_gesture,metro_flash;
    wire [7:0] metro_bpm;
    wire [2:0] metro_meter,metro_beat;
    wire [1:0] metro_accent;
    generate if(ENABLE_EXPRESSION) begin: metronome
        metronome_control controls(.clk(clk),.rst(rst),.sample_ce(sample_ce),.online(online),
            .touched(touched),.enabled(metro_enabled),.bpm(metro_bpm),.meter(metro_meter),.gesture(metro_gesture));
        metronome_audio click(.clk(clk),.rst(audio_reset),.sample_ce(sample_ce),
            .enabled(metro_enabled && !spectrum_mode),.bpm(metro_bpm),.meter(metro_meter),.volume(volume),
            .sample(click_sample),.beat_index(metro_beat),.flash(metro_flash),.accent(metro_accent),.tick());
    end else begin: no_metronome
        assign metro_enabled=0;assign metro_bpm=120;assign metro_meter=3;assign metro_gesture=0;
        assign click_sample=0;assign metro_beat=0;assign metro_flash=0;assign metro_accent=0;
    end endgenerate
    assign metronome_info={metro_bpm,metro_meter,metro_beat,metro_enabled,metro_flash,metro_accent};
    wire signed [16:0] final_mix=$signed({tone_sample[15],tone_sample})+$signed({click_sample[15],click_sample});
    wire click_clipped=final_mix>32767 || final_mix< -32768;
    assign sample=final_mix>32767 ? 16'sh7fff : final_mix< -32768 ? 16'sh8000 : final_mix[15:0];
    reg previous_mode=0;
    always @(posedge clk) previous_mode<=spectrum_mode;
    wire audio_reset=rst || (previous_mode!=spectrum_mode);
    reg remote_sustain=DEFAULT_SUSTAIN;
    always @(posedge clk) begin
        if(audio_reset || !online || spectrum_mode) remote_sustain<=DEFAULT_SUSTAIN;
        else if(command_valid && command=="H") remote_sustain<=command_value[0];
    end
    wire encoder_enabled;
    wire [4:0] encoder_strength;
    generate if(ENABLE_EC11) begin: ec11_control
        ec11_sustain #(.FILTER_CLOCKS(EC11_FILTER_CLOCKS),.BUTTON_CLOCKS(EC11_BUTTON_CLOCKS),
            .TRANSITIONS_PER_STEP(EC11_TRANSITIONS_PER_STEP),.REVERSE(EC11_REVERSE)) knob(
            .clk(clk),.rst(audio_reset || !online || spectrum_mode),
            .a(encoder_a),.b(encoder_b),.sw_n(encoder_sw_n),
            .set_valid(command_valid && command=="H"),.set_enabled(command_value[0]),
            .enabled(encoder_enabled),.strength(encoder_strength));
    end else begin: no_ec11
        assign encoder_enabled=1'b0;
        assign encoder_strength=5'd3;
    end endgenerate
    assign sustain_info={sustain_active,encoder_strength};
    assign sustain_active=!audio_reset && online && !spectrum_mode &&
        (sustain_request || (ENABLE_EC11 ? encoder_enabled : remote_sustain));
    wire joystick_up,joystick_down,joystick_vibrato;
    generate if(ENABLE_JOYSTICK) begin: joystick_input
        joystick_control #(.BUTTON_CLOCKS(JOYSTICK_BUTTON_CLOCKS),.REVERSE(JOYSTICK_REVERSE),
            .BUTTON_ACTIVE_LOW(JOYSTICK_BUTTON_ACTIVE_LOW),.CENTER_MV(JOYSTICK_CENTER_MV)) stick(
            .clk(clk),.rst(rst),.online(joystick_online),.sample_valid(joystick_sample_valid),
            .allow_octave(online && !guide_enabled && !spectrum_mode),.millivolts(joystick_mv),
            .sw_n(joystick_sw_n),.octave_up(joystick_up),.octave_down(joystick_down),
            .vibrato(joystick_vibrato),.armed());
    end else begin: no_joystick
        assign joystick_up=0;assign joystick_down=0;assign joystick_vibrato=0;
    end endgenerate
    generate if(ENABLE_EXPRESSION) begin: pitch_input
        pitch_expression wheel(.clk(clk),.rst(audio_reset),.sample_ce(sample_ce),
            .enabled(y_enabled && online && !spectrum_mode),.online(y_online),
            .sample_valid(y_sample_valid),.millivolts(y_mv),.armed(y_armed),.bend(pitch_bend));
    end else begin: no_pitch_input
        assign pitch_bend=0;assign y_armed=0;
    end endgenerate
    performance_control #(.ENABLE_EXPRESSION(ENABLE_EXPRESSION),.ENABLE_JOYSTICK(ENABLE_JOYSTICK),.DEFAULT_TIMBRE(DEFAULT_TIMBRE)) controls(.clk(clk),.rst(rst),.sample_ce(sample_ce),
        .command_valid(command_valid),.command(command),.value(command_value),
        .joystick_up(joystick_up),.joystick_down(joystick_down),.joystick_vibrato(joystick_vibrato),
        .online(online),.touched(touched),.gates(gates),.timbre(timbre),
        .volume(volume),.octave_select(selected_octave),.vibrato(vibrato),.spectrum_mode(spectrum_mode),
        .echo_enabled(echo_enabled),.guide_enabled(guide_enabled),.effect_mode(effect_mode),.y_enabled(y_enabled));
    polyphonic_engine #(.ENABLE_PITCH_BEND(ENABLE_EXPRESSION),.VARIABLE_SUSTAIN(ENABLE_EC11)) engine(.pitch_bend(spectrum_mode ? 16'sd0 : pitch_bend),.sustain_strength(encoder_strength),.sustain_down(sustain_active),.clk(clk),.rst(audio_reset),.sample_ce(sample_ce),.gates(gates),
        .timbre(spectrum_mode ? 3'b0 : timbre),.octave_select(octave_select),.vibrato(vibrato),
        .mixed(mixed),.valid(valid),.active(active),.voice_levels(voice_levels),.voice_count(voice_count),.overrun(engine_overrun));
    wire effects_valid;
    wire signed [18:0] effects_mix;
    generate if(ENABLE_EXPRESSION) begin: effects
        expression_effects processor(.clk(clk),.rst(audio_reset),.valid(valid),.mixed(mixed),
            .mode(effect_mode),.calibration(spectrum_mode),.valid_out(effects_valid),.result(effects_mix));
    end else begin: no_effects
        assign effects_valid=valid;assign effects_mix=mixed;
    end endgenerate
    audio_output output_stage(.clk(clk),.rst(audio_reset),.valid(effects_valid),.mixed(effects_mix),
        .volume(spectrum_mode ? 13'd2048 : expressive_volume),.calibration(spectrum_mode),.echo_enable((ENABLE_ECHO || echo_enabled) && !spectrum_mode),
        .sample(tone_sample),.clipped(clipped),.limited(limited));
    i2s_transmitter transmitter(.clk(clk),.rst(rst),.sample(sample),
        .sample_ce(sample_ce),.bck(dac_bck),.lrck(dac_lrck),.din(dac_din));
    practice_guide guide(.clk(clk),.rst(rst),.sample_ce(sample_ce),.bpm(bpm),
        .command_valid(command_valid),.command(command),.value(command_value),.input_error(input_error),
        .command_ok(command_ok),.target_mask(guide_mask),.length(guide_length),.custom(custom_score),
        .enabled(guide_enabled && online && !spectrum_mode),.gates(gates),
        .target(guide_target),.position(guide_position),.correct(),.octave(guide_octave),.rest(guide_rest),.playing(guide_playing),.finished(guide_finished));
    assign monitor_sample=sample;
    assign monitor_ce=sample_ce;
    reg [25:0] heartbeat_count=0;
    wire tempo_pulse;
    tempo_clock tempo(.clk(clk),.rst(rst),.bpm(bpm),.flash(tempo_pulse),.beat());
    assign status={touched[17],chip_online,active[12:8],gates[12:8],
        lamp_test,tempo_pulse,(clipped || limited || click_clipped),guide_position[5:0],guide_target,guide_enabled,spectrum_mode,
        echo_enabled,vibrato,online,volume[12:8],timbre[1:0],active[7:0],gates[7:0]};
    always @(posedge clk) begin
        if(rst) heartbeat_count<=0;
        else if(heartbeat_count==26'd49999999) heartbeat_count<=0;
        else heartbeat_count<=heartbeat_count+1'b1;
    end
    wire beat=(heartbeat_count<26'd25000000);
    // Idle L5..L8 identify the preset within its bank; L3 marks presets T4..T7.
    wire [7:0] preset_light=(8'h10 << timbre[1:0]) | (timbre[2] ? 8'h04 : 8'h00);
    wire [7:0] lights= !online ? (beat ? 8'h81 : 8'h00) :
        spectrum_mode ? (beat ? 8'hFF : 8'h00) :
        (|gates) ? gates[7:0] : guide_enabled ? guide_mask[7:0] : (preset_light | 8'h02 | {7'd0,beat});
    assign led=~lights;
    // All thirteen PCB lamps show held notes plus a steady guide target.
    // X0 retains the lamp check while also modifying C0..C3; it is not a note.
    wire [12:0] guide_lights=guide_enabled && !spectrum_mode ?
        guide_mask : 13'b0;
    assign key_lights=lamp_test ? lamp_test_mask :
        !online ? 13'b0 : (touched[17] && (!ENABLE_EXPRESSION || (touched[11:8]==0 && !metro_gesture))) ? 13'h1FFF : pcb_lamps(gates | guide_lights);
endmodule
