"""Check the published UI build against preserved L1 sources and RTL rasters."""
import hashlib
import json
import re
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'outputs/ui-3x-20261101'
WALLPAPERS = ROOT / 'outputs/ui-20261101/wallpapers'
BUILD = ROOT / 'outputs/expression-ui-v2-3x'
BASE = ROOT / 'backups/expression-link-v1-20261101'
UNITY = ROOT / 'backups/ui-v2-before-3x-20261101'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def resources(path):
    text = path.read_text(encoding='utf-8')
    return {key: float(re.search(r'^\s*'+key+r'\s*\|\s*([\d.]+)/', text, re.M)[1])
            for key in ('Logic', 'Register', 'BSRAM', 'DSP')}


def timing(path):
    text = path.read_text(encoding='utf-8')
    result = {}
    for key in ('Setup', 'Hold', 'Recovery', 'Removal'):
        table = re.search(r'^3\.1\.\d '+key+r' Paths Table\n(.*?)(?=\n3\.)', text, re.S | re.M)[1]
        slacks = re.findall(r'^\s+\d+\s+([-\d.]+)\s+', table, re.M)
        assert slacks, key
        result[key.lower()+'_ns'] = min(map(float, slacks))
    table = re.search(r'^3\.2 Minimum Pulse Width Table\n(.*?)\n3\.3',text,re.S | re.M)[1]
    result['pulse_width_ns'] = min(map(float,re.findall(r'^\s+\d+\s+([-\d.]+)\s+',table,re.M)))
    assert min(result.values())>=0, result
    return result


def pin_assignments(path):
    text=path.read_text(encoding='utf-8')
    section=text.split('\n7. Pinout by Port Name\n')[1].split('\n8. All Package Pins')[0]
    result={}
    for line in section.splitlines():
        fields=[part.strip() for part in line.split('|')]
        if len(fields)>20 and fields[4] in ('in','out','io'):
            result[fields[0]]=fields[1:]
    assert len(result)==38, len(result)
    return result


def main():
    changes = [p.name for p in (BASE/'source/instrument/src').iterdir()
               if p.is_file() and sha(p)!=sha(ROOT/'instrument/src'/p.name)]
    assert sorted(changes)==['instrument_screen.v','instrument_top.v'], changes
    baseline = ROOT/'dist/instrument_expression_link_v1.fs'
    assert sha(baseline)=='da65392c1d213eaf79da60ab2113a0c43fea8d154eaf34e2b5cb334276a129a4'
    assert sha(baseline)==sha(BASE/'source/dist/instrument_expression_link_v1.fs')
    old_pins=pin_assignments(BASE/'previous-impl/pnr/instrument_expression.rpt.txt')
    new_pins=pin_assignments(BUILD/'instrument_expression.rpt.txt')
    assert old_pins==new_pins, 'Actual placed pins / electrical attributes changed'
    rasters=[]
    mask=np.zeros((600,800),bool)
    mask[:,:12]=True;mask[:,788:]=True;mask[70:74,:]=True;mask[590:,:]=True
    for n in range(1,9):
        stem='screen_expression' if n==1 else f'screen_expression_wallpaper_{n}'
        image=Image.open(ROOT/f'instrument/sim/{stem}.ppm').convert('RGB')
        image.save(OUT/f'{stem}.png')
        expected=np.array(Image.open(WALLPAPERS/f'{n}.png'))
        mismatch=np.count_nonzero(np.any(np.array(image)[mask]!=expected[mask],axis=1))
        assert mismatch==0, (n,int(mismatch))
        rasters.append(image)
    offline=Image.open(ROOT/'instrument/sim/screen_expression_offline.ppm')
    offline.save(OUT/'screen_expression_offline.png')
    # Two rows; full-resolution panels are exported separately for inspection.
    contact=Image.new('RGB',(1600,600))
    for i,im in enumerate(rasters):
        contact.paste(im.resize((400,300)),((i%4)*400,(i//4)*300))
    contact.save(OUT/'all-wallpapers.png')
    manifest=json.loads((ROOT/'dist/instrument_expression_ui_v2_3x.manifest.json').read_text(encoding='utf-8-sig'))
    unity_manifest=json.loads((UNITY/'dist/instrument_expression_ui_v2.manifest.json').read_text(encoding='utf-8-sig'))
    assert unity_manifest['sha256'].lower()==sha(ROOT/'dist/instrument_expression_ui_v2.fs')
    assert manifest['sha256'].lower()==sha(ROOT/'dist'/manifest['bitstream'])
    for entry in manifest['inputs']:
        assert entry['sha256'].lower()==sha(ROOT/'instrument'/entry['path']), entry['path']
    result={
        'baseline_sha256':sha(baseline),'new_sha256':manifest['sha256'].lower(),
        'existing_source_changes':changes,'audio_and_pin_sources_unchanged':True,
        'placed_ports_verified_unchanged':len(new_pins),
        'baseline_resources':resources(BASE/'previous-impl/pnr/instrument_expression.rpt.txt'),
        'new_resources':resources(BUILD/'instrument_expression.rpt.txt'),
        'previous_1x_resources':resources(UNITY/'reports/instrument_expression.rpt.txt'),
        'timing':timing(BUILD/'instrument_expression.tr'),
        'display_gain':manifest['display_gain'],
        'wallpaper_raster_pixels_checked':int(mask.sum())*8,
        'hardware_validated':False,
    }
    (OUT/'release-audit.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(result,indent=2))


if __name__=='__main__':
    main()
