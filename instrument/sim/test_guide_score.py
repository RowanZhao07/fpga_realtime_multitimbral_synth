"""Check the supplied melody, encoded pitch/duration, repeat and MIDI range."""
import importlib.util
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('guide',ROOT/'instrument/tools/generate_guide.py')
guide=importlib.util.module_from_spec(spec);spec.loader.exec_module(guide)

class ScoreTests(unittest.TestCase):
    def test_selected_vocal_passage(self):
        events,sections=guide.score_events()
        self.assertEqual(len(events),76)
        self.assertEqual(sum(d for _,d in events),252)
        self.assertEqual(events[:10],[(74,2),(71,6),(74,2),(69,6),(71,2),
                                     (69,4),(67,10),(67,2),(66,2),(64,2)])
        # Closing 3,4,3,2,1,low-7,1 from the supplied G-major score.
        self.assertEqual(events[-7:],[(71,2),(72,2),(71,2),(69,4),(67,2),(66,2),(67,10)])
        self.assertTrue(all(note is not None for note,_ in events))
        self.assertEqual(len(sections),1)
        self.assertEqual((min(n for n,_ in events),max(n for n,_ in events)),(64,83))

    def test_only_one_chorus(self):
        events,_=guide.score_events()
        pitches=[n for n,_ in events]
        # High tonic pickup of the chorus 'wo yu jian': once, no intro/repeat.
        phrase=[79,78,79,78,76,74,76,74,67,69,71]
        self.assertEqual(sum(pitches[i:i+len(phrase)]==phrase for i in range(len(pitches))),1)
        self.assertEqual(events[-2:],[(66,2),(67,10)]) # 'ma pai', final G4

    def test_every_rom_event_is_playable(self):
        events,_=guide.score_events();words=guide.encode(events);last_bank=1
        for (pitch,duration),word in zip(events,words):
            self.assertEqual((word>>15)&255,duration)
            self.assertEqual(word>>23,0)
            bank=(word>>13)&3;mask=word&8191
            if pitch is None:
                self.assertEqual(mask,0);self.assertEqual(bank,last_bank)
            else:
                self.assertEqual(mask.bit_count(),1)
                self.assertEqual(48+bank*12+guide.OFFSETS[mask.bit_length()-1],pitch)
                if pitch-(48+last_bank*12) in guide.OFFSETS:self.assertEqual(bank,last_bank)
            last_bank=bank

if __name__=='__main__':unittest.main()
