`timescale 1ns/1ps
module tb_spectrum;
    reg clk=0; always #10 clk=~clk;
    reg rst=1,ce=0,ack=0;
    reg signed [15:0] sample=0;
    wire done,valid; wire [8:0] bin; wire [15:0] magnitude;
    wire scope_write;wire [9:0] scope_address;wire [7:0] scope_value;
    audio_spectrum dut(.clk(clk),.rst(rst),.sample_ce(ce),.sample(sample),
        .write_enable(scope_write),.write_address(scope_address),.write_value(scope_value),.frame_done(done),.frame_ack(ack),
        .bin_valid(valid),.bin_index(bin),.bin_magnitude(magnitude));
    integer outputs,inputs,scenario=0,count=0,n,v;
    integer expected_scope,scope_pixels=0;
    always @(negedge clk) if(!rst && scope_write && !scope_address[9]) begin
        // Full PCM16 maps to the plot limits, with no AGC.
        expected_scope=$signed(dut.input_sample)>>>8;
        if(expected_scope>127) expected_scope=127;
        if(expected_scope< -128) expected_scope=-128;
        if($signed(scope_value)!==expected_scope)
            $fatal(1,"Fixed-scale PCM scope mismatch: input=%0d got=%0d expected=%0d",$signed(dut.input_sample),$signed(scope_value),expected_scope);
        scope_pixels=scope_pixels+1;
    end

    real phase,value,freq;
    integer midi[0:7]='{60,62,64,65,67,69,71,72};
    always @(posedge clk) if(valid) begin
        if(bin!==count[8:0] || $isunknown(magnitude)) $fatal(1,"FFT bin sequence/data");
        $fdisplay(outputs,"%0d,%0d,%0d,%0d,%0d",scenario,bin,magnitude,$signed(dut.read_real),$signed(dut.read_imag));
        if(scenario==0 && magnitude!=0) $fatal(1,"Silence spectrum");
        count=count+1;
    end
    initial begin
        outputs=$fopen("fft_output.csv","w"); inputs=$fopen("fft_input.csv","w");
        repeat(3) @(negedge clk); rst=0;
        for(scenario=0;scenario<3;scenario=scenario+1) begin
            count=0;
            for(n=0;n<4096;n=n+1) begin
                value=0;
                if(scenario==1) value=8000*$sin(2*3.141592653589793*37*n/4096)+4000*$sin(2*3.141592653589793*73*n/4096);
                if(scenario==2) for(v=0;v<8;v=v+1) begin
                    freq=440.0*(2.0**((midi[v]-69)/12.0));
                    value=value+1500*$sin(2*3.141592653589793*freq*n/48828.125);
                end
                @(negedge clk); sample=$rtoi(value); ce=1;
                $fdisplay(inputs,"%0d,%0d,%0d",scenario,n,$signed(sample));
                @(negedge clk); ce=0; repeat(6) @(negedge clk);
            end
            wait(done); repeat(2) @(negedge clk);
            if(count!=512) $fatal(1,"Missing FFT bins");
            ack=1; @(negedge clk); ack=0; repeat(3) @(negedge clk);
        end
        if(scope_pixels!=1536) $fatal(1,"Missing PCM scope samples");
        $fclose(outputs); $fclose(inputs);
        $display("PASS: 4096-point spectrum, silence/two tones/eight notes; golden comparison in Python");
        $display("ALL TESTS PASSED"); $finish;
    end
    initial begin #100000000; $fatal(1,"FFT watchdog"); end
endmodule
