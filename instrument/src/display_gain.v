`timescale 1ns/1ps
// Display-only fixed zoom, before waveform/XY coordinate quantization.
// The mixer, DAC and FFT still receive the original PCM. No DSP or state.
module display_gain #(parameter ENABLE_3X=1'b1)(
    input wire signed [15:0] sample,output wire signed [15:0] scaled);
    wire signed [17:0] wide={{2{sample[15]}},sample};
    wire signed [17:0] tripled=wide+(wide<<<1);
    assign scaled=!ENABLE_3X ? sample :
        tripled>18'sd32767 ? 16'sh7fff :
        tripled< -18'sd32768 ? 16'sh8000 : tripled[15:0];
endmodule
