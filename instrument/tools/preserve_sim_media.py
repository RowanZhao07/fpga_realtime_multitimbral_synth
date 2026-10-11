"""Keep simulation pictures in Git-visible assets before cleaning raw output.

PPM frames are saved as lossless PNG; exact pixel duplicates are skipped.
Replaced pictures retain a content-addressed copy in history/. WAVs stay local.
All locations are resolved from this script, independent of the caller's cwd.
"""
from hashlib import sha256
from pathlib import Path
import shutil

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SIM = ROOT / "instrument/sim"
ASSETS = ROOT / "assets/simulation"
PICTURES = {".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg"}


def safe(path):
    if not path.resolve().is_relative_to(ROOT):
        raise ValueError("Media path leaves the repository")
    return path


def preserve(source, target):
    """Never discard an existing, different revision of a picture or WAV."""
    safe(source)
    safe(target).parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        old = target.read_bytes()
        if old == source.read_bytes():
            return
        archive = target.parent / "history" / f"{target.stem}-{sha256(old).hexdigest()[:12]}{target.suffix}"
        safe(archive).parent.mkdir(exist_ok=True)
        if archive.exists() and archive.read_bytes() != old:
            raise RuntimeError(f"Archive name collision: {archive.name}")
        if not archive.exists():
            shutil.copy2(target, archive)
    shutil.copy2(source, target)
    assert source.read_bytes() == target.read_bytes(), target.name


def pixel_key(image):
    return image.size, sha256(image.convert("RGB").tobytes()).digest()


def main():
    safe(ASSETS).mkdir(parents=True, exist_ok=True)
    for source in sorted(safe(SIM / "output").glob("*")):
        if not source.is_file():
            continue
        if source.suffix.lower() in PICTURES:
            preserve(source, ASSETS / source.name)
        elif source.suffix.lower() == ".wav":
            preserve(source, ROOT / ".local/simulation_audio" / source.name)

    known = set()
    for path in ASSETS.rglob("*.png"):
        with Image.open(safe(path)) as image:
            known.add(pixel_key(image))
    for source in sorted(SIM.glob("*.ppm")):
        with Image.open(safe(source)) as image:
            key = pixel_key(image)
            if key in known:
                continue
            target = ASSETS / "frames" / f"{source.stem}-{key[1].hex()[:12]}.png"
            safe(target).parent.mkdir(exist_ok=True)
            if not target.exists():
                image.save(target)
            with Image.open(target) as saved:
                assert pixel_key(saved) == key, target.name
            known.add(key)
    print("Simulation pictures preserved in assets/simulation; WAVs in .local/simulation_audio.")


if __name__ == "__main__":
    main()
