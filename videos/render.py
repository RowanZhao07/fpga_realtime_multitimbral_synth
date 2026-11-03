"""Render the competition film from an explicit, portable edit decision list.

Requires Python 3.10+, numpy, Pillow and FFmpeg/ffprobe. Narration is never
time-stretched. Raw footage, recordings and rendered media stay outside Git.
"""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import subprocess
import wave

import numpy as np
from PIL import Image, ImageDraw, ImageFont

W, H, FPS, SR = 1280, 720, 30, 48000


def stamp(t):
    n = round(t * 1000)
    return f"{n//3600000:02}:{n//60000%60:02}:{n//1000%60:02},{n%1000:03}"


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--project', type=Path, default=Path(__file__).with_name('project.json'))
    p.add_argument('--media-dir', type=Path, required=True)
    p.add_argument('--output-dir', type=Path, required=True)
    p.add_argument('--ffmpeg', default='ffmpeg')
    p.add_argument('--font', default='C:/Windows/Fonts/NotoSerifSC-VF.ttf')
    a = p.parse_args()
    ff = shutil.which(a.ffmpeg)
    if not ff:
        p.error('FFmpeg was not found; pass --ffmpeg /path/to/ffmpeg')
    fp = str(Path(ff).with_name('ffprobe.exe' if Path(ff).suffix == '.exe' else 'ffprobe'))
    data = json.loads(a.project.read_text(encoding='utf-8'))
    out = a.output_dir.resolve(); work = out / 'work'
    work.mkdir(parents=True, exist_ok=True)

    def run(args, name):
        with (work / (name + '.log')).open('w', encoding='utf-8') as log:
            subprocess.run([ff, '-hide_banner', '-nostdin', '-y', *map(str, args)],
                           stdout=log, stderr=log, check=True)

    def font(size, weight=600):
        f = ImageFont.truetype(a.font, size)
        try:
            f.set_variation_by_axes([weight])
        except OSError:
            pass
        return f

    def layer(title, detail='', caption=False):
        im = Image.new('RGBA', (W, H)); d = ImageDraw.Draw(im)
        if caption:
            f = font(28); width = round(f.getlength(title)) + 48
            if width > W - 60:
                raise ValueError(f'Caption too wide: {title}')
            x = (W - width) // 2
            d.rounded_rectangle((x, H-79, x+width, H-23), 14,
                                fill=(15,23,34,218), outline=(210,227,245,60))
            d.text((W//2, H-53), title, font=f, anchor='mm', fill=(245,248,253))
        else:
            d.rounded_rectangle((28,23,504,115), 20, fill=(23,32,48,220),
                                outline=(204,219,242,65))
            d.text((46,31), title, font=font(31,700), fill=(222,232,255))
            d.text((47,79), detail, font=font(17,500), fill=(222,228,239))
        return im

    def audio(path, duration=None, start=0):
        cmd = [ff, '-v','error','-ss',str(start),'-i',str(path)]
        if duration is not None:
            cmd += ['-t',str(duration)]
        cmd += ['-vn','-ac','2','-ar',str(SR),'-f','f32le','pipe:1']
        return np.frombuffer(subprocess.check_output(cmd),dtype='<f4').reshape(-1,2).copy()

    def writewav(path, pcm):
        with wave.open(str(path),'wb') as f:
            f.setnchannels(2); f.setsampwidth(2); f.setframerate(SR)
            f.writeframes(np.rint(np.clip(pcm,-1,1)*32767).astype('<i2').tobytes())

    segments = data['segments']; cursor = 3.0; captions = []; voices = []
    for s in segments:
        s['timeline_start'] = cursor
        s['duration'] = s['frames'] / FPS
        cursor += s['duration']; s['timeline_end'] = cursor
        for c in s.get('captions',[]):
            captions.append(dict(c, start=s['timeline_start']+c['at'],
                                 end=s['timeline_start']+c['until']))
        for v in s.get('voices',[]):
            voices.append(dict(v, start=s['timeline_start']+v['at']))
    assert cursor <= 180, f'Film exceeds three minutes: {cursor}'
    assert all(c['at'] < c['until'] <= s['duration'] for s in segments for c in s.get('captions',[]))
    captions.sort(key=lambda c:c['start'])
    assert all(c['end'] <= n['start'] for c,n in zip(captions,captions[1:]))
    (out/'配音字幕.srt').write_text('\n\n'.join(
        f"{i+1}\n{stamp(c['start'])} --> {stamp(c['end'])}\n{c['text']}"
        for i,c in enumerate(captions))+'\n',encoding='utf-8-sig')
    (out/'timeline.json').write_text(json.dumps(segments,ensure_ascii=False,indent=2),encoding='utf-8')

    original = np.zeros((round(cursor*SR),2),np.float32)
    opening = a.media_dir / data['opening']
    opening_audio = audio(a.media_dir / data.get('opening_audio',data['opening']),3)
    original[:min(len(opening_audio),3*SR)] = opening_audio[:3*SR]
    render_paths = []
    open_video = work/'00.mp4'
    run(['-i',opening,'-an','-vf',f'scale={W}:{H},fps={FPS},setsar=1',
         '-frames:v','90','-c:v','libx264','-preset','fast','-crf','18',
         '-pix_fmt','yuv420p',open_video],'opening')
    render_paths.append(open_video)
    for s in segments:
        idx = s['index']; src = a.media_dir/s['file']; dur = s['duration']
        title = work/f'{idx:02}_title.png'
        layer(f"{idx:02}  {s['title']}",s['detail']).save(title)
        cmd = ['-ss',str(s.get('source_start',0)),'-i',src,
               '-loop','1','-i',title]
        filters = [f"[0:v]setpts=(PTS-STARTPTS)/{s.get('picture_speed',1)},"
                   f"scale={W}:{H},fps={FPS},setsar=1,tpad=stop_mode=clone:stop_duration=0.1[v0]",
                   '[v0][1:v]overlay=0:0:shortest=1[v1]']
        n = 1
        for c in s.get('captions',[]):
            n += 1; cp = work/f'{idx:02}_caption_{n}.png'
            layer(c['text'],caption=True).save(cp)
            cmd += ['-loop','1','-i',cp]
            filters.append(f"[v{n-1}][{n}:v]overlay=0:0:shortest=1:"
                           f"enable='between(t,{c['at']},{c['until']})'[v{n}]")
        if s.get('inset'):
            n += 1
            cmd += ['-loop','1','-i',a.media_dir/s['inset']]
            filters.append(f'[v{n-1}][{n}:v]overlay=904:23:shortest=1[v{n}]')
        target = work/f'{idx:02}.mp4'
        cmd += ['-filter_complex_threads','1','-filter_complex',';'.join(filters),
                '-map',f'[v{n}]','-an','-frames:v',str(s['frames']),
                '-c:v','libx264','-preset','fast','-crf','20','-pix_fmt','yuv420p',target]
        run(cmd,f'scene_{idx:02}'); render_paths.append(target)
        # Picture speed is deliberately independent of audio/narration time.
        pcm = audio(src,dur,s.get('source_start',0)); at=round(s['timeline_start']*SR)
        count=min(len(pcm),round(dur*SR)); original[at:at+count]=pcm[:count]
        print(f"Rendered {idx:02}: {s['title']} ({dur:.3f}s)",flush=True)

    voice = np.zeros_like(original); duck = np.ones(len(original),np.float32)
    voice_audit = []; pending = []
    for v in voices:
        path = a.media_dir/v['file']
        if v.get('optional') and not path.exists():
            pending.append(v['file']); continue
        pcm = audio(path)
        first=round(v.get('trim_start',0)*SR); last=len(pcm)-round(v.get('trim_end',0)*SR)
        pcm=pcm[first:last]
        if len(pcm)/SR > v['max_duration']:
            raise ValueError(f"Recording does not fit; rerecord without speeding speech: {path}")
        start=round(v['start']*SR); end=start+len(pcm)
        voice[start:end]+=pcm
        lo=max(0,start-round(.18*SR)); hi=min(len(duck),end+round(.38*SR))
        duck[lo:start]=np.minimum(duck[lo:start],np.linspace(1,.2,start-lo))
        duck[start:end]=np.minimum(duck[start:end],.2)
        duck[end:hi]=np.minimum(duck[end:hi],np.linspace(.2,1,hi-end))
        voice_audit.append({'file':v['file'],'start':start/SR,'duration':len(pcm)/SR,
                            'speech_speed':1.0,'trim_start':first/SR,
                            'trim_end':v.get('trim_end',0),
                            'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
    combined=original*duck[:,None]+voice
    peak=float(np.abs(combined).max()); gain=min(1,.86/max(peak,1e-9)); combined*=gain
    writewav(work/'master.wav',combined)
    listing=work/'concat.txt'
    listing.write_text(''.join(f"file '{p.name}'\n" for p in render_paths),encoding='utf-8')
    film=out/'弦外之芯_参赛演示_最终版.mp4'
    run(['-f','concat','-safe','0','-i',listing,'-i',work/'master.wav',
         '-map','0:v:0','-map','1:a:0','-c:v','copy','-c:a','aac','-b:a','192k',
         '-t',str(cursor),'-movflags','+faststart',film],'final_mux')
    run(['-v','error','-xerror','-i',film,'-f','null','-'],'decode_check')
    probe=json.loads(subprocess.check_output([fp,'-v','error','-show_format',
                                              '-show_streams','-of','json',str(film)]))
    assert float(probe['format']['duration']) <= 180
    report={'duration_seconds':float(probe['format']['duration']),
            'frames':sum(s['frames'] for s in segments)+90,
            'narration':voice_audit,'pending_optional_recordings':pending,
            'master_gain':gain,'pcm_peak':float(np.abs(combined).max()),
            'decode_pass':True,'sha256':hashlib.sha256(film.read_bytes()).hexdigest()}
    (out/'validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({'film':str(film),'seconds':report['duration_seconds'],
                      'pending_recordings':pending},ensure_ascii=False),flush=True)


if __name__ == '__main__':
    main()
