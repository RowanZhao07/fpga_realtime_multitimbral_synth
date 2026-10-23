`timescale 1ns/1ps
module tb_variable_sustain;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,gate=0,pedal=1;reg [1:0] timbre=0;
 reg [4:0] strength[0:15];wire [15:0] level[0:15];wire [15:0] active;
 integer tails[0:15];integer previous[0:15];integer t,i,k,elapsed;
 genvar n;
 generate for(n=0;n<16;n=n+1)begin: bank
  envelope_adsr #(.VARIABLE_SUSTAIN(1)) dut(.clk(clk),.rst(rst),.sample_ce(1'b1),
   .gate(gate),.timbre(timbre),.sustain_down(pedal),.sustain_strength(strength[n]),
   .level(level[n]),.active(active[n]));
 end endgenerate
 task tick(input integer count);repeat(count)@(negedge clk);endtask
 initial begin
  for(t=0;t<4;t=t+1)begin
   timbre=t;rst=1;gate=0;pedal=1;
   for(i=0;i<16;i=i+1)begin strength[i]=i+1;tails[i]=0;end
   tick(3);rst=0;gate=1;tick(2200);gate=0;tick(1);elapsed=0;
   for(i=0;i<16;i=i+1)previous[i]=level[i];
   while(active!=0 && elapsed<220000)begin
    tick(1);elapsed=elapsed+1;
    for(i=0;i<16;i=i+1)begin
     if(level[i]>previous[i])$fatal(1,"Tail rose: timbre %d level %d",t,i+1);
     if(previous[i]-level[i]>64)$fatal(1,"Hard cut");
     if(level[i]==0 && tails[i]==0)tails[i]=elapsed;
     previous[i]=level[i];
    end
   end
   if(active!=0)$fatal(1,"Tail never silent for timbre %d",t);
   for(i=1;i<16;i=i+1)if(tails[i]<=tails[i-1])$fatal(1,"Non-monotonic 16-level tails");
   $display("Timbre %d tail samples: L1=%d L16=%d",t,tails[0],tails[15]);
  end
  // Live level changes preserve energy, disabling cannot revive a released tail.
  rst=1;pedal=1;timbre=1;gate=0;tick(3);rst=0;gate=1;tick(100);gate=0;tick(100);
  k=level[15];strength[15]=1;tick(1);
  if(level[15]>k || k-level[15]>64)$fatal(1,"Live strength jump");
  pedal=0;tick(2);pedal=1;tick(2);
  if(bank[15].dut.release_pedal)$fatal(1,"Recaptured released tail");
  k=level[15];gate=1;tick(3);if(level[15]<=k)$fatal(1,"Retrigger failed");
  rst=1;tick(2);if(active!=0)$fatal(1,"Reset failed");
  rst=0;gate=0;pedal=1;tick(100);if(active!=0)$fatal(1,"Empty sustain created sound");
  $display("ALL TESTS PASSED");$finish;
 end
 initial begin #15000000;$fatal(1,"Variable sustain watchdog");end
endmodule
