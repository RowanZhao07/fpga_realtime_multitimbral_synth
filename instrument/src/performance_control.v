`timescale 1ns/1ps
// White notes [7:0], controls [11:8], sharp notes [16:12], octave modifier X0 [17].
module performance_control #(
    parameter ENABLE_JOYSTICK=1'b0,
    parameter ENABLE_EXPRESSION=1'b0,
    parameter [2:0] DEFAULT_TIMBRE=3'd0,
    parameter integer HOLD_SAMPLES=48828,
    parameter integer REPEAT_SAMPLES=4883
)(
    input wire clk, rst, sample_ce, online,
    input wire [17:0] touched,
    input wire joystick_up,joystick_down,joystick_vibrato,
    input wire command_valid,input wire [7:0] command,input wire [15:0] value,
    output wire [12:0] gates,
    output reg [2:0] timbre=DEFAULT_TIMBRE,
    output reg [12:0] volume=2048,
    output reg [1:0] octave_select=2'd1, // 0..3 select C3..C6; default C4.
    output wire vibrato,
    output reg spectrum_mode=0,
    output reg echo_enabled=0,
    output reg guide_enabled=0,
    output reg [1:0] effect_mode=0,
    output reg y_enabled=0
);
    reg [3:0] previous=0;
    reg [16:0] hold_count=0, repeat_count=0;
    reg combo_used=0;
    reg [16:0] effect_count=0, guide_count=0;
    reg effect_used=0, guide_used=0;
    reg expression_gesture=0;
    wire [3:0] raw_control=online ? touched[11:8] : 4'b0;
    wire expression_modifier=ENABLE_EXPRESSION && online && touched[17];
    wire octave_modifier=!ENABLE_EXPRESSION && !ENABLE_JOYSTICK && online && touched[17];
    reg octave_gesture=0,octave_used=0;
    wire suppress_controls=octave_modifier || octave_gesture || expression_modifier || expression_gesture;
    wire [3:0] control=suppress_controls ? 4'b0 : raw_control;
    wire all_control=&control;
    wire volume_repeat=(repeat_count==REPEAT_SAMPLES-1);
    // Allow 25 ms for X0 on the second touch controller to join a VOL chord.
    // Ordinary volume repeat stays at 100 ms; non-expression profiles are unchanged.
    localparam integer VOLUME_GRACE=REPEAT_SAMPLES<1221 ? REPEAT_SAMPLES : 1221;
    wire volume_press=repeat_count==VOLUME_GRACE-1;
    // Keep the calibrated eight-sine spectrum test; live play has 13 notes.
    assign gates=online ? (spectrum_mode ? 13'h0FF : {touched[16:12],touched[7:0]}) : 13'd0;
    assign vibrato=online && ((ENABLE_JOYSTICK && joystick_vibrato) || control[3]) && !spectrum_mode && !all_control;
    always @(posedge clk) begin
        if(rst) begin
            previous<=0; timbre<=DEFAULT_TIMBRE; volume<=2048; spectrum_mode<=0;
            hold_count<=0; repeat_count<=0; combo_used<=0;
            effect_count<=0; guide_count<=0; effect_used<=0; guide_used<=0;
            echo_enabled<=0; guide_enabled<=0;effect_mode<=0;y_enabled<=0;expression_gesture<=0;
            octave_select<=2'd1;octave_gesture<=0;octave_used<=0;
        end else begin
          // Joystick events are in clk domain, independent of the audio enable.
          if(ENABLE_JOYSTICK && online && !spectrum_mode && !guide_enabled) begin
              if(joystick_up && !joystick_down && octave_select<3) octave_select<=octave_select+1'b1;
              if(joystick_down && !joystick_up && octave_select>0) octave_select<=octave_select-1'b1;
          end
          if(sample_ce) begin
            if(!online || (!touched[17] && raw_control==0)) expression_gesture<=0;
            else if(expression_modifier) expression_gesture<=1;
            // One selection per X0 gesture. Consume ambiguous multi-key chords
            // too, so releasing one control cannot accidentally select a bank.
            if(!online) begin octave_gesture<=0;octave_used<=0;end
            else if(octave_modifier) begin
                octave_gesture<=1;
                if(!octave_used && |raw_control) begin
                    octave_used<=1;
                    if(!spectrum_mode) case(raw_control)
                        4'b0001:octave_select<=2'd0;
                        4'b0010:octave_select<=2'd1;
                        4'b0100:octave_select<=2'd2;
                        4'b1000:octave_select<=2'd3;
                        default:begin end
                    endcase
                end
            end else if(raw_control==0) begin octave_gesture<=0;octave_used<=0;end
            // Swallow both release orders until X0 and all controls are up.
            if(suppress_controls) begin
                previous<=0;hold_count<=0;repeat_count<=0;combo_used<=0;
                effect_count<=0;guide_count<=0;effect_used<=0;guide_used<=0;
                if(!online) spectrum_mode<=0;
            end else begin
            previous<=control;
            if(control==4'b0001 && !spectrum_mode && !combo_used) begin
                if(!effect_used) begin
                    if(effect_count==HOLD_SAMPLES-1) begin
                        if(ENABLE_EXPRESSION) begin
                            effect_mode<=effect_mode+1'b1;
                            echo_enabled<=effect_mode==0;
                        end else echo_enabled<=!echo_enabled;
                        effect_used<=1;
                    end else effect_count<=effect_count+1'b1;
                end
            end else effect_count<=0;
            if(control==4'b0110 && !spectrum_mode && !combo_used) begin
                if(!guide_used) begin
                    if(guide_count==HOLD_SAMPLES-1) begin
                        guide_enabled<=!guide_enabled; guide_used<=1;
                    end else guide_count<=guide_count+1'b1;
                end
            end else guide_count<=0;
            if(control==0) begin effect_used<=0; guide_used<=0; end
            if(!online) begin spectrum_mode<=0; hold_count<=0; combo_used<=0; end
            else if(all_control) begin
                if(!combo_used) begin
                    if(hold_count==HOLD_SAMPLES-1) begin
                        spectrum_mode<=!spectrum_mode; combo_used<=1;
                    end else hold_count<=hold_count+1'b1;
                end
            end else begin hold_count<=0; if(control==0) combo_used<=0; end
            if(control[2:1]==2'b01 || control[2:1]==2'b10) begin
                if(volume_repeat) repeat_count<=0;
                else repeat_count<=repeat_count+1'b1;
            end else repeat_count<=0;
            // Change preset on release; a held all-control gesture consumes it.
            if(previous[0] && !control[0] && !combo_used && !effect_used && !spectrum_mode && online)
                timbre<=timbre+1'b1;
            if(!all_control && !combo_used && !spectrum_mode) begin
                if(control[2:1]==2'b01 && ((ENABLE_EXPRESSION ? volume_press : !previous[1]) || volume_repeat) && volume>512)
                    volume<=volume<768 ? 13'd512 : volume-13'd256;
                if(control[2:1]==2'b10 && ((ENABLE_EXPRESSION ? volume_press : !previous[2]) || volume_repeat) && volume<4096)
                    volume<=volume>3840 ? 13'd4096 : volume+13'd256;
            end
            end
          end
          // Same clock domain; remote commands win a coincident local gesture.
          // The UART parser validates all ranges before asserting valid.
          if(command_valid) case(command)
          "T":timbre<=value[2:0];
          "V":volume<=value[12:0];
          "E":begin echo_enabled<=value[0];effect_mode<=value[0] ? 1 : 0;end
          "F":if(ENABLE_EXPRESSION) begin effect_mode<=value[1:0];echo_enabled<=value==1;end
          "Y":if(ENABLE_EXPRESSION) y_enabled<=value[0];
          "G":guide_enabled<=value[0];
          default:begin end
          endcase
        end
    end
endmodule
