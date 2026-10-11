"""Compare actual RTL FFT output with an independent floating-point transform."""
from pathlib import Path
import json
import numpy as np
from PIL import Image
root=Path(__file__).resolve().parents[1]
output=root/'sim/output'
output.mkdir(exist_ok=True)
inp=np.loadtxt(root/'sim/fft_input.csv',delimiter=',',dtype=int)
out=np.loadtxt(root/'sim/fft_output.csv',delimiter=',',dtype=int)
checks=[]
for scenario in range(3):
    x=inp[inp[:,0]==scenario,2]
    y=out[out[:,0]==scenario]
    ref=np.fft.fft(x*np.hanning(4096))/4096
    actual=y[:,3]+1j*y[:,4]
    error=np.max(np.abs(actual-ref[:512]))
    assert error<16,(scenario,error)
    if scenario==1:
        assert abs(actual[37])>1950 and abs(actual[73])>950
        assert max(abs(actual[100:]))<12
    checks.append({'scenario':scenario,'max_complex_error_pcm_units':float(error)})
Image.open(root/'sim/screen.ppm').save(output/'screen_preview.png')
Image.open(root/'sim/screen_debug.ppm').save(output/'screen_debug_preview.png')
Image.open(root/'sim/screen_offline.ppm').save(output/'screen_offline_preview.png')
(output/'visual_analysis.json').write_text(json.dumps({
    'evidence':'RTL simulation, not physical screen capture',
    'fft_length':4096,'sample_rate':48828.125,'bin_hz':48828.125/4096,
    'window':'Hann','display_bins':512,'checks':checks,'checks_passed':True},indent=2))
print('FFT GOLDEN COMPARISON AND SCREEN EXPORT PASSED',checks)
