"""Compare early/late harmonics from actual shared-pipeline RTL output."""
from pathlib import Path
import json
import numpy as np

out=Path(__file__).resolve().parents[1]/'sim/output'
data=np.loadtxt(out/'dynamic_timbre.csv',delimiter=',',skiprows=1)
fs=50_000_000/1024
fundamental=261.625565
def harmonic_ratio(x):
    f=np.fft.rfftfreq(len(x),1/fs)
    a=np.abs(np.fft.rfft(x*np.hanning(len(x))))
    def peak(h):return a[np.abs(f-h*fundamental)<20].max()
    return float(peak(2)/peak(1))
result=[]
for tone in range(4):
    x=data[data[:,0]==tone,2]
    early=harmonic_ratio(x[256:4352]);late=harmonic_ratio(x[12288:16384])
    result.append(dict(tone=tone,early_h2_h1=early,late_h2_h1=late))
    if tone==0:assert max(early,late)<.01,'Sine acquired spurious harmonics'
    if tone in (1,3):assert early>.01 and late<early*.25,'Upper harmonics did not decay faster than fundamental'
    if tone==2:assert early>.2 and .08<late<early,'String spectrum did not warm over time'
(out/'dynamic_timbre_analysis.json').write_text(json.dumps(dict(evidence='RTL, not board capture',checks=result,passed=True),indent=2))
print(result)
print('DYNAMIC TIMBRE ANALYSIS PASSED')
