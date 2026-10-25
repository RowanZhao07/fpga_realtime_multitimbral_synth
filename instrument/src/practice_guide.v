`timescale 1ns/1ps
// 512 events, double-buffered upload. A step never generates note gates.
// Built-in melody advances on note-on and ends once. Uploaded timed events
// retain their explicit duration/release semantics and looping behavior.
// Word: timed[23], sixteenth-note duration[22:15], octave bank[14:13], keys[12:0].
module practice_guide #(
    parameter [31:0] TICK_DENOM=32'd3000000000
)(
    input wire clk,rst,sample_ce,enabled,
    input wire [7:0] bpm,
    input wire [12:0] gates,
    input wire command_valid,input_error,
    input wire [7:0] command,input wire [15:0] value,
    output wire command_ok,output wire [12:0] target_mask,
    output wire [9:0] length,output reg custom=0,
    output wire [2:0] target,
    output reg [8:0] position=0,
    output reg correct=0,
    output wire [1:0] octave,
    output wire rest,
    output reg playing=0,
    output reg finished=0
);
    reg [23:0] score_ram[0:1023];
    reg active_bank=0,uploading=0,poisoned=0;
    reg [9:0] staged_length=0,active_length=0;
    reg [1:0] staged_octave=1;
    reg [7:0] staged_duration=0;
    reg [12:0] previous=0;
    reg was_enabled=0;
    reg [31:0] tempo_phase=0;
    reg [7:0] remaining=0;
    reg [1:0] fetch_wait=2;
    reg [23:0] ram_event=0;
    wire [23:0] rom_event;
    wire [9:0] rom_length;
    guide_score_rom built_in(.address(position),.event_word(rom_event),.length(rom_length));
    wire [23:0] event_word=custom ? ram_event : rom_event;
    assign target_mask=finished ? 13'd0 : event_word[12:0];
    assign octave=event_word[14:13];
    assign rest=!finished && (target_mask==0);
    assign length=custom ? active_length : rom_length;
    wire timed=event_word[23];
    wire [12:0] note_on=gates & ~previous;
    // For the single-note built-in melody, allow the previous note to remain
    // held (legato), but require a fresh correct attack. Never consume a hold
    // twice, including consecutive notes on the same key in different octaves.
    wire note_match=custom ? (gates==target_mask && |note_on) :
        (note_on==target_mask && |target_mask);
    wire append_ok=uploading && !poisoned && staged_length<512 && value<=16'h1fff &&
        (value!=0 || staged_duration!=0);
    wire option_ok=uploading && !poisoned;
    wire commit_ok=uploading && !poisoned && staged_length!=0;
    // Dedicated synchronous RAM ports infer block RAM, not 24576 flip-flops.
    always @(posedge clk) begin
        ram_event<=score_ram[{active_bank,position}];
        if(!rst && command_valid && !input_error && command=="A" && append_ok)
            score_ram[{!active_bank,staged_length[8:0]}]<={staged_duration!=0,staged_duration,staged_octave,value[12:0]};
    end
    assign command_ok=!input_error && (command=="A" ? append_ok :
        command=="Z" ? commit_ok : (command=="O" || command=="U") ? option_ok : 1'b1);
    reg [2:0] first_white;
    integer n;
    always @* begin
        first_white=0;
        for(n=7;n>=0;n=n-1) if(target_mask[n]) first_white=n;
    end
    assign target=first_white;
    wire [32:0] tick_sum={1'b0,tempo_phase}+{13'b0,bpm,12'b0};
    wire tick=(tick_sum>={1'b0,TICK_DENOM});
    always @(posedge clk) begin
        correct<=0;
        if(rst) begin
            position<=0;custom<=0;active_bank<=0;uploading<=0;poisoned<=0;
            staged_length<=0;active_length<=0;staged_octave<=1;staged_duration<=0;
            previous<=0;was_enabled<=0;playing<=0;finished<=0;remaining<=0;tempo_phase<=0;fetch_wait<=2;
        end else begin
            if(fetch_wait!=0) fetch_wait<=fetch_wait-1'b1;
            if(sample_ce) begin
                previous<=gates;was_enabled<=enabled;
                if(!enabled || !was_enabled) begin position<=0;playing<=0;finished<=0;remaining<=0;tempo_phase<=0;fetch_wait<=2;end
                else if(fetch_wait!=0) begin end
                else if(finished) begin end
                else if(!playing) begin
                    if((rest && gates==0) || note_match) begin
                        correct<=!rest;
                        if(timed) begin playing<=1;remaining<=event_word[22:15];tempo_phase<=0;end
                        else if(!custom && {1'b0,position}+10'd1>=length) finished<=1;
                        else begin position<=({1'b0,position}+10'd1>=length) ? 0 : position+1'b1;fetch_wait<=2;end
                    end
                end else begin
                    if(remaining!=0) begin
                        if(tick) begin tempo_phase<=tick_sum-TICK_DENOM;remaining<=remaining-1'b1;end
                        else tempo_phase<=tick_sum[31:0];
                    end else if(gates==0) begin
                        position<=({1'b0,position}+10'd1>=length) ? 0 : position+1'b1;
                        playing<=0;tempo_phase<=0;fetch_wait<=2;
                    end
                end
            end
            // Errors poison only the staged bank; the running score survives.
            if(input_error && uploading) poisoned<=1;
            if(command_valid && !input_error) case(command)
                "N":begin uploading<=1;poisoned<=0;staged_length<=0;staged_octave<=1;staged_duration<=0;end
                "O":if(option_ok && value>=3 && value<=6) staged_octave<=value-3;else poisoned<=1;
                "U":if(option_ok && value>=1 && value<=255) staged_duration<=value[7:0];else poisoned<=1;
                "A":if(append_ok) begin
                    staged_length<=staged_length+1'b1;
                end else poisoned<=1;
                "Z":if(commit_ok) begin
                    active_bank<=!active_bank;active_length<=staged_length;custom<=1;
                    uploading<=0;position<=0;previous<=gates;playing<=0;finished<=0;remaining<=0;tempo_phase<=0;fetch_wait<=2;
                end else poisoned<=1;
                "R":begin custom<=0;uploading<=0;poisoned<=0;position<=0;previous<=gates;playing<=0;finished<=0;remaining<=0;tempo_phase<=0;fetch_wait<=2;end
                default:begin end
            endcase
        end
    end
endmodule
