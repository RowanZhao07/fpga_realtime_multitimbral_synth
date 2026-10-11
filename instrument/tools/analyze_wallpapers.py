"""Check RTL image unpacking/scaling against Pillow and export the gallery."""
from pathlib import Path
import numpy as np
from PIL import Image, ImageOps, ImageDraw

root = Path(__file__).resolve().parents[2]
sim = root / "instrument/sim"
output = sim / "output"
output.mkdir(exist_ok=True)
previews = []
for number in range(1, 9):
    with Image.open(root / "assets/wallpapers" / f"{number}.jpg") as source:
        native = ImageOps.fit(ImageOps.exif_transpose(source).convert("RGB"),
                              (192, 144), Image.Resampling.LANCZOS)
    native = np.array(native.quantize(colors=64, method=Image.Quantize.MEDIANCUT,
                                      dither=Image.Dither.NONE).convert("RGB"))
    # Independent exact integer coordinate mapping, not the RTL reciprocal.
    expected = native[(np.arange(600)*6//25)[:, None], (np.arange(800)*6//25)[None, :]]
    actual = np.array(Image.open(sim / f"wallpaper_{number}.ppm"))
    assert np.array_equal(actual, expected), f"Image {number}: wrong pixels, palette, scaling or latency"
    frame = Image.open(sim / f"gallery_{number}.ppm")
    assert np.array_equal(np.array(frame)[:, 4], expected[:, 4]), f"Image {number}: renderer/background latency mismatch"
    frame.save(output / f"wallpaper_screen_{number}.png")
    previews.append(frame.copy())
sheet = Image.new("RGB", (1600, 664), "#121521")
draw = ImageDraw.Draw(sheet)
for i, frame in enumerate(previews):
    left, top = (i % 4)*400, (i // 4)*332
    # Two rows, preserve 4:3; reserve labels beneath each image.
    sheet.paste(frame.resize((400, 300), Image.Resampling.LANCZOS), (left, top))
    draw.text((left+10, top+308), f"{i+1}.jpg | RTL simulation", fill="#e2dcff")
sheet.save(output / "wallpaper_gallery.png")
previews[0].save(output / "wallpaper_slideshow.gif", save_all=True,
                 append_images=previews[1:], duration=1800, loop=0)
print("WALLPAPER GOLDEN COMPARISON PASSED: 8 x 480000 exact RGB pixels; gallery exported")
