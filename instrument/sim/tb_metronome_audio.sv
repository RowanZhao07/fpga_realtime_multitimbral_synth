`timescale 1ns/1ps
module tb_metronome_audio;
 reg clk=0;always #10 clk=~clk;
 reg rst=1,ce=0,enabled=0;reg [7:0] bpm=120;reg [2:0] meter=3;
 wire signed [15:0] pcm;wire tick,flash;wire [2:0] beat;wire [1:0] accent;
 metronome_audio dut(.clk(clk),.rst(rst),.sample_ce(ce),.enabled(enabled),.bpm(bpm),.meter(meter),
 .volume(13'd4096),.sample(pcm),.tick(tick),.flash(flash),.beat_index(beat),.accent(accent));
 integer sample_no=0,events=0,last_tick=0,first_tick=0,f=0,k,j,n,expected_accent,interval,peak=0;
 real ideal,err;
 reg got_tick=0,capture=0;reg [31:0] old_phase;
 task frame;begin
 ce=1;@(negedge clk);got_tick=tick;ce=0;repeat(3)@(negedge clk);sample_no=sample_no+1;
 if((^pcm)===1'bx)$fatal(1,"Unknown PCM");
 if(capture)$fdisplay(f,"%0d,%0d,%0d,%0d,%0d,%0d",meter,bpm,sample_no,pcm,got_tick,accent);
 if(pcm>peak)peak=pcm;
 end endtask
 task run_meter(input integer m,b,beats_to_check);begin
 enabled=0;repeat(120)frame;meter=m;bpm=b;enabled=1;events=0;
 ideal=3000000000.0/(1024.0*b*(m==4 ? 3.0 : 1.0));
 while(events<beats_to_check)begin
 frame;
 if(got_tick)begin
   if(events==0)begin first_tick=sample_no;if(beat!=0 || accent!=2)$fatal(1,"Start must be downbeat");end
   else begin
     interval=sample_no-last_tick;err=interval-ideal;
     if(err>1.0 || err< -1.0)$fatal(1,"Timing m=%0d bpm=%0d samples=%0d ideal=%f",m,b,interval,ideal);
   end
   err=sample_no-first_tick-events*ideal;
   if(err>1.0 || err< -1.0)$fatal(1,"Accumulated phase drift %f samples",err);
   expected_accent=beat==0 ? 2 : ((m==3 && beat==2) || (m==4 && beat==3)) ? 1 : 0;
   if(accent!=expected_accent || !flash)$fatal(1,"Accent/visual beat disagreement");
   if(beat!=events%(m<2 ? 2 : m==2 ? 3 : m==3 ? 4 : 6))$fatal(1,"Bar wrap");
   last_tick=sample_no;events=events+1;
 end
 end
 end endtask
 initial begin
 repeat(3)@(negedge clk);rst=0;repeat(4200)frame;
 if(pcm!=0)$fatal(1,"Default silence");
 for(k=0;k<5;k=k+1)run_meter(k,240,k==4 ? 13 : 9);
 run_meter(0,40,3);run_meter(4,40,7);
 // A tempo edit in the middle of a beat carries existing phase.
 run_meter(3,120,1);repeat(10000)frame;old_phase=dut.phase;bpm=121;frame;
 if(got_tick || dut.phase!=old_phase+121*1024)$fatal(1,"Tempo edit reset/duplicated beat");
 // Continuously changing BPM must not postpone beats indefinitely.
 events=0;for(j=0;j<100000;j=j+1)begin
   if(j%4883==0 && bpm<240)bpm=bpm+1;
   frame;if(got_tick)events=events+1;
 end
 if(events<4)$fatal(1,"Tempo ramp stalled clock");
 f=$fopen("metronome_audio.csv","w");$fdisplay(f,"meter,bpm,sample,pcm,tick,accent");capture=1;
 run_meter(3,120,9);run_meter(4,120,13);
 enabled=0;repeat(200)frame;if(pcm!=0 || beat!=0 || flash)$fatal(1,"Disable must silence and park on beat one");
 meter=0;repeat(2)frame;if(beat!=0)$fatal(1,"Stopped meter change retained an invalid beat index");
 capture=0;$fclose(f);
 if(peak<8000 || peak>15000)$fatal(1,"Click headroom %0d",peak);
 $display("ALL TESTS PASSED: rational sample timing, five accent patterns, 40/240 BPM, live ramp, click audio, bounded stop tail; peak=%0d",peak);$finish;
 end
 initial begin #1000000000;$fatal(1,"Metronome watchdog");end
endmodule
