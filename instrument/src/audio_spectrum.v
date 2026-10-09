`timescale 1ns/1ps
// Snapshot analyser, independent of the real-time audio path.
// 4096 real samples, Hann window, radix-2 DIT, 1/N scaling at every stage.
// Full-rate input: 48828.125 Hz; bin width 11.92093 Hz. No decimation/aliasing.
module audio_spectrum #(parameter ENABLE_SCOPE=1'b1)(input wire clk,rst,sample_ce,
    input wire signed [15:0] sample,
    output reg write_enable=0, output reg [9:0] write_address=0,
    output reg [7:0] write_value=0,
    output reg frame_done=0, input wire frame_ack,
    output reg bin_valid=0, output reg [8:0] bin_index=0,
    output reg [15:0] bin_magnitude=0,
    output wire signed [15:0] bin_real,bin_imag,output wire bin_frame_start,output reg [31:0] frame_sample_index=0);
    localparam CAPTURE=0,CAP_WRITE=1,CAP_NEXT=2,ISSUE_A=3,WAIT_A=4,GET_A=5,
        WAIT_B=6,GET_B=7,MULTIPLY=8,ROTATE=9,WRITE_A=10,WRITE_B=11,NEXT=12,
        OUT_ISSUE=13,OUT_WAIT=14,OUT_VALUE=15,ACK_WAIT=16;
    reg [4:0] state=CAPTURE;
    reg [31:0] stream_sample_index=0;
    always @(posedge clk) begin
        if(rst) stream_sample_index<=0;
        else if(sample_ce) stream_sample_index<=stream_sample_index+1'b1;
    end
    reg [11:0] capture_index=0,group_base=0,offset=0,read_address=0;
    reg [3:0] stage=0;
    wire [12:0] half_size=13'd1<<stage;
    wire [11:0] index_a=group_base+offset;
    wire [11:0] index_b=index_a+half_size[11:0];
    wire [10:0] twiddle_address=offset<<(11-stage);
    wire signed [15:0] cosine,sine,window_value;
    fft_cos_lut cosine_table(.address(twiddle_address),.value(cosine));
    fft_sin_lut sine_table(.address(twiddle_address),.value(sine));
    fft_window_lut window_table(.address(capture_index),.value(window_value));
    reg signed [31:0] windowed=0;
    reg signed [15:0] input_sample=0;
    reg signed [15:0] real_memory[0:4095],imag_memory[0:4095];
    reg signed [15:0] read_real=0,read_imag=0,a_real=0,a_imag=0,b_real=0,b_imag=0;
    reg signed [31:0] rr=0,ii=0,ri=0,ir=0;
    reg signed [17:0] rotated_real=0,rotated_imag=0;
    wire signed [32:0] rotation_r=$signed({rr[31],rr})-$signed({ii[31],ii});
    wire signed [32:0] rotation_i=$signed({ri[31],ri})+$signed({ir[31],ir});
    wire signed [18:0] sum_r=$signed(a_real)+$signed(rotated_real);
    wire signed [18:0] sum_i=$signed(a_imag)+$signed(rotated_imag);
    wire signed [18:0] diff_r=$signed(a_real)-$signed(rotated_real);
    wire signed [18:0] diff_i=$signed(a_imag)-$signed(rotated_imag);
    assign bin_real=read_real; assign bin_imag=read_imag;
    assign bin_frame_start=bin_valid && bin_index==0;
    wire [15:0] abs_r=read_real[15] ? -read_real : read_real;
    wire [15:0] abs_i=read_imag[15] ? -read_imag : read_imag;
    wire [16:0] magnitude={1'b0,abs_r}+{1'b0,abs_i};
    wire signed [15:0] scope_scaled=input_sample>>>6;
    function [11:0] reverse_bits;
        input [11:0] x; integer k;
        begin for(k=0;k<12;k=k+1) reverse_bits[k]=x[11-k]; end
    endfunction
    function [7:0] log_height;
        input [16:0] x; integer k; reg [7:0] result;
        begin
            result=0;
            for(k=0;k<16;k=k+1) if(x>=(17'd1<<k)) result=k*9;
            log_height=result;
        end
    endfunction
    reg mem_write;
    reg [11:0] mem_address;
    reg signed [15:0] mem_real,mem_imag;
    always @* begin
        mem_write=0; mem_address=0; mem_real=0; mem_imag=0;
        case(state)
        CAP_WRITE: begin mem_write=1; mem_address=reverse_bits(capture_index); mem_real=windowed>>>15; end
        WRITE_A: begin mem_write=1; mem_address=index_a; mem_real=sum_r>>>1; mem_imag=sum_i>>>1; end
        WRITE_B: begin mem_write=1; mem_address=index_b; mem_real=diff_r>>>1; mem_imag=diff_i>>>1; end
        endcase
    end
    // One synchronous read port and one write port per block RAM.
    always @(posedge clk) begin
        read_real<=real_memory[read_address]; read_imag<=imag_memory[read_address];
        if(mem_write && !rst) begin real_memory[mem_address]<=mem_real; imag_memory[mem_address]<=mem_imag; end
    end
    always @(posedge clk) begin
        write_enable<=0; bin_valid<=0;
        if(rst) begin state<=CAPTURE; capture_index<=0; group_base<=0; offset<=0; stage<=0;
            frame_done<=0; read_address<=0; bin_index<=0; frame_sample_index<=0; end
        else case(state)
        CAPTURE: if(sample_ce) begin
            windowed<=sample*window_value; input_sample<=sample; state<=CAP_WRITE;
            if(capture_index==0) frame_sample_index<=stream_sample_index;
        end
        CAP_WRITE: begin
            if(ENABLE_SCOPE && capture_index<512) begin
                write_enable<=1; write_address<={1'b0,capture_index[8:0]};
                if(scope_scaled>100) write_value<=100;
                else if(scope_scaled< -100) write_value<=-8'sd100;
                else write_value<=scope_scaled[7:0];
            end
            state<=CAP_NEXT;
        end
        CAP_NEXT: if(capture_index==4095) begin
            stage<=0; group_base<=0; offset<=0; state<=ISSUE_A;
        end else begin capture_index<=capture_index+1'b1; state<=CAPTURE; end
        ISSUE_A: begin read_address<=index_a; state<=WAIT_A; end
        WAIT_A: state<=GET_A;
        GET_A: begin a_real<=read_real; a_imag<=read_imag; read_address<=index_b; state<=WAIT_B; end
        WAIT_B: state<=GET_B;
        GET_B: begin b_real<=read_real; b_imag<=read_imag; state<=MULTIPLY; end
        MULTIPLY: begin rr<=b_real*cosine; ii<=b_imag*sine; ri<=b_real*sine; ir<=b_imag*cosine; state<=ROTATE; end
        ROTATE: begin rotated_real<=rotation_r>>>15; rotated_imag<=rotation_i>>>15; state<=WRITE_A; end
        WRITE_A: state<=WRITE_B;
        WRITE_B: state<=NEXT;
        NEXT: begin
            if({1'b0,offset}+1<half_size) offset<=offset+1'b1;
            else begin
                offset<=0;
                if({1'b0,group_base}+(half_size<<1)<4096) group_base<=group_base+(half_size<<1);
                else begin
                    group_base<=0;
                    if(stage==11) begin bin_index<=0; state<=OUT_ISSUE; end
                    else stage<=stage+1'b1;
                end
            end
            if(!(offset+13'd1==half_size && {1'b0,group_base}+(half_size<<1)==4096 && stage==11)) state<=ISSUE_A;
        end
        OUT_ISSUE: begin read_address<={3'b0,bin_index}; state<=OUT_WAIT; end
        OUT_WAIT: state<=OUT_VALUE;
        OUT_VALUE: begin
            bin_valid<=1; bin_magnitude<=magnitude[15:0];
            write_enable<=1; write_address<={1'b1,bin_index}; write_value<=log_height(magnitude);
            // Keep bin_index valid throughout bin_valid; advance in OUT_WAIT via read address below.
            if(bin_index==511) begin frame_done<=1; state<=ACK_WAIT; end
            else begin read_address<={3'b0,bin_index}+1'b1; state<=17; end
        end
        17: begin bin_index<=bin_index+1'b1; state<=OUT_WAIT; end
        ACK_WAIT: if(frame_ack) begin frame_done<=0; capture_index<=0; state<=CAPTURE; end
        default: state<=CAPTURE;
        endcase
    end
endmodule
