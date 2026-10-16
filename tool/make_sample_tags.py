"""Renders the sample tag texts in samples/tags/*.txt as printed-tag PNGs.

Usage: python3 tool/make_sample_tags.py
Requires Pillow and the DejaVu fonts.
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
TAGS = ROOT / "samples" / "tags"
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"


def render(txt: Path) -> None:
    lines = txt.read_text(encoding="utf-8").strip().splitlines()
    font = ImageFont.truetype(FONT, 38)
    pad, gap = 48, 16
    widths = [font.getbbox(l)[2] for l in lines]
    line_h = font.getbbox("Ag")[3]
    w = max(widths) + pad * 2 + 60
    h = len(lines) * (line_h + gap) + pad * 2
    img = Image.new("RGB", (w + 40, h + 40), (205, 196, 180))  # counter background
    tag = Image.new("RGB", (w, h), (255, 253, 246))
    d = ImageDraw.Draw(tag)
    d.rounded_rectangle([4, 4, w - 5, h - 5], radius=24, outline=(168, 132, 58), width=4)
    d.ellipse([w - 52, h // 2 - 12, w - 28, h // 2 + 12], outline=(120, 110, 90), width=3)
    y = pad
    for l in lines:
        d.text((pad, y), l, font=font, fill=(25, 22, 18))
        y += line_h + gap
    img.paste(tag, (20, 20))
    img.save(txt.with_suffix(".png"), optimize=True)


if __name__ == "__main__":
    for t in sorted(TAGS.glob("*.txt")):
        render(t)
        print("wrote", t.with_suffix(".png").name)
