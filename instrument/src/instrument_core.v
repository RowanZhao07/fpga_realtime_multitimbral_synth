`timescale 1ns/1ps
module instrument_core #(
    parameter ENABLE_ECHO=1'b0,
    parameter ENABLE_EC11=1'b0,
    parameter integer EC11_FILTER_CLOCKS=50000,
    parameter integer EC11_TRANSITIONS_PER_STEP=2,
    parameter EC11_REVERSE=1'b0,
    parameter integer EC11_BUTTON_CLOCKS=500000,
    parameter DEFAULT_SUSTAIN=1'b0,
    parameter [1:0] DEFAULT_TIMBRE=2'd0,
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
    input wire pressure_online,
    input wire [11:0] pressure_mv,
    input wire control_rx,output wire control_tx,
    output wire [44:0] control_status,
    output wire [31:0] performance_info,
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
    wire echo_enabled,guide_enabled;
    wire [2:0] guide_target;
    wire [8:0] guide_position;
    wire [1:0] guide_octave;
    wire guide_rest,guide_playing;
    wire [5:0] voice_count;
    wire engine_overrun;
    wire sample_ce, vibrato, spectrum_mode, valid, clipped;
    wire [12:0] gates,active;
    wire [1:0] timbre;
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
    reg [7:0] bpm=120;
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
    uart_control #(.CLOCKS_PER_BIT(UART_CLOCKS_PER_BIT)) remote_control(
        .clk(clk),.rst(rst),.rx(control_rx),.tx(control_tx),.command_ok(command_ok),
        .command_valid(command_valid),.command(command),.value(command_value),
        .input_error(input_error),.accepted(accepted),.rejected(rejected),.diagnostics(uart_diagnostics));
    always @(posedge clk) begin
        if(rst) begin bpm<=120;diagnostics_visible<=0;end
        else if(command_valid) case(command)
            "B":bpm<=command_value[7:0];
            "D":diagnostics_visible<=command_value[0];
            default:begin end
        endcase
    end
    assign control_status={rejected,accepted,custom_score,(guide_length>127 ? 7'd127 : guide_length[6:0]),bpm,guide_mask};
    assign performance_info={voice_count,guide_length,guide_position,guide_rest,guide_playing,5'b0};
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
    // reaching unity at 3072 mV; C1/C2 still set the maximum playing volume.
    wire [9:0] pressure_gain=pressure_mv>=12'd3072 ? 10'd512 :
        10'd128+{1'b0,pressure_mv[11:3]};
    wire [22:0] pressure_product=volume*pressure_gain;
    wire [12:0] expressive_volume=pressure_online ? pressure_product[21:9] : volume;
    wire signed [18:0] mixed;
    wire signed [15:0] sample;
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
    performance_control #(.DEFAULT_TIMBRE(DEFAULT_TIMBRE)) controls(.clk(clk),.rst(rst),.sample_ce(sample_ce),
        .command_valid(command_valid),.command(command),.value(command_value),
        .online(online),.touched(touched),.gates(gates),.timbre(timbre),
        .volume(volume),.octave_select(selected_octave),.vibrato(vibrato),.spectrum_mode(spectrum_mode),.echo_enabled(echo_enabled),.guide_enabled(guide_enabled));
    polyphonic_engine #(.VARIABLE_SUSTAIN(ENABLE_EC11)) engine(.sustain_strength(encoder_strength),.sustain_down(sustain_active),.clk(clk),.rst(audio_reset),.sample_ce(sample_ce),.gates(gates),
        .timbre(spectrum_mode ? 2'b0 : timbre),.octave_select(octave_select),.vibrato(vibrato),
        .mixed(mixed),.valid(valid),.active(active),.voice_levels(voice_levels),.voice_count(voice_count),.overrun(engine_overrun));
    audio_output output_stage(.clk(clk),.rst(audio_reset),.valid(valid),.mixed(mixed),
        .volume(spectrum_mode ? 13'd2048 : expressive_volume),.echo_enable((ENABLE_ECHO || echo_enabled) && !spectrum_mode),
        .sample(sample),.clipped(clipped));
    i2s_transmitter transmitter(.clk(clk),.rst(rst),.sample(sample),
        .sample_ce(sample_ce),.bck(dac_bck),.lrck(dac_lrck),.din(dac_din));
    practice_guide guide(.clk(clk),.rst(rst),.sample_ce(sample_ce),.bpm(bpm),
        .command_valid(command_valid),.command(command),.value(command_value),.input_error(input_error),
        .command_ok(command_ok),.target_mask(guide_mask),.length(guide_length),.custom(custom_score),
        .enabled(guide_enabled && online && !spectrum_mode),.gates(gates),
        .target(guide_target),.position(guide_position),.correct(),.octave(guide_octave),.rest(guide_rest),.playing(guide_playing));
    assign monitor_sample=sample;
    assign monitor_ce=sample_ce;
    reg [25:0] heartbeat_count=0;
    wire tempo_pulse;
    tempo_clock tempo(.clk(clk),.rst(rst),.bpm(bpm),.flash(tempo_pulse),.beat());
    assign status={touched[17],chip_online,active[12:8],gates[12:8],
        lamp_test,tempo_pulse,clipped,guide_position[5:0],guide_target,guide_enabled,spectrum_mode,
        echo_enabled,vibrato,online,volume[12:8],timbre,active[7:0],gates[7:0]};
    always @(posedge clk) begin
        if(rst) heartbeat_count<=0;
        else if(heartbeat_count==26'd49999999) heartbeat_count<=0;
        else heartbeat_count<=heartbeat_count+1'b1;
    end
    wire beat=(heartbeat_count<26'd25000000);
    // Held notes take priority. Idle L5..L8 identify the next-note preset.
    wire [7:0] preset_light=8'h10 << timbre;
    wire [7:0] lights= !online ? (beat ? 8'h81 : 8'h00) :
        spectrum_mode ? (beat ? 8'hFF : 8'h00) :
        (|gates) ? gates[7:0] : guide_enabled ? (tempo_pulse ? guide_mask[7:0] : 8'b0) : (preset_light | 8'h02 | {7'd0,beat});
    assign led=~lights;
    // All thirteen PCB lamps show held notes plus the flashing guide target.
    // X0 retains the lamp check while also modifying C0..C3; it is not a note.
    wire [12:0] guide_lights=guide_enabled && !spectrum_mode && tempo_pulse ?
        guide_mask : 13'b0;
    assign key_lights=lamp_test ? lamp_test_mask :
        !online ? 13'b0 : touched[17] ? 13'h1FFF : pcb_lamps(gates | guide_lights);
endmodule
