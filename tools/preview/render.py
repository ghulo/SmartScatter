"""Panel preview (a dev tool): draws tools/preview/out/<name>.json (from dump.lua) as out/<name>.png, rectangles, corners,
borders and text in paint order, at 2x; prints what the dump found wrong (text cut off, things spilling out)."""
import json
import pathlib
import sys

from PIL import Image, ImageDraw, ImageFont

OUT = pathlib.Path(__file__).resolve().parent / "out"
SCALE = 2


def rgb(h):
    return tuple(int(h[i : i + 2], 16) for i in (0, 2, 4))


def font(size, bold):
    name = "arialbd.ttf" if bold else "arial.ttf"
    return ImageFont.truetype(name, max(6, int(size * SCALE * 0.92)))


def main(name):
    data = json.loads((OUT / (name + ".json")).read_text(encoding="utf-8"))
    W, H = int(data["w"]), int(data["h"])
    img = Image.new("RGBA", (W * SCALE, H * SCALE), (40, 40, 40, 255))
    for it in data["items"]:
        clip = it.get("clip")
        layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        x0, y0 = it["x"] * SCALE, it["y"] * SCALE
        x1, y1 = (it["x"] + it["w"]) * SCALE, (it["y"] + it["h"]) * SCALE
        r = int(it.get("r", 0) * SCALE)
        a = int(255 * (1 - it.get("bt", 1)))
        if a > 0 and it.get("bg"):
            d.rounded_rectangle([x0, y0, x1 - 1, y1 - 1], radius=r, fill=rgb(it["bg"]) + (a,))
        if it.get("s") and it.get("st", 1) < 1:
            sa = int(255 * (1 - it["st"]))
            d.rounded_rectangle([x0, y0, x1 - 1, y1 - 1], radius=r, outline=rgb(it["s"]) + (sa,), width=max(1, int(it.get("sw", 1) * SCALE)))
        if it.get("img"):
            d.rectangle([x0 + 2, y0 + 2, x1 - 3, y1 - 3], outline=(160, 160, 160, 90), width=1)
        if it.get("tx"):
            f = font(it.get("ts", 12), it.get("tb"))
            ta = int(255 * (1 - it.get("tt", 0)))
            text = it["tx"]
            if it.get("wrap"):
                words, lines, cur = text.split(" "), [], ""
                for w in words:
                    trial = (cur + " " + w).strip()
                    if d.textlength(trial, font=f) <= (x1 - x0) or not cur:
                        cur = trial
                    else:
                        lines.append(cur)
                        cur = w
                lines.append(cur)
                text = "\n".join(lines)
            bbox = d.multiline_textbbox((0, 0), text, font=f)
            tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
            ax, ay = it.get("ax", "Center"), it.get("ay", "Center")
            tx = x0 if ax == "Left" else (x1 - tw if ax == "Right" else (x0 + x1 - tw) / 2)
            ty = y0 if ay == "Top" else (y1 - th if ay == "Bottom" else (y0 + y1 - th) / 2)
            d.multiline_text((tx, ty - bbox[1]), text, font=f, fill=rgb(it.get("tc", "ffffff")) + (ta,))
        if clip:
            mask = Image.new("L", img.size, 0)
            ImageDraw.Draw(mask).rectangle([clip[0] * SCALE, clip[1] * SCALE, clip[2] * SCALE, clip[3] * SCALE], fill=255)
            layer.putalpha(Image.composite(layer.getchannel("A"), Image.new("L", img.size, 0), mask))
        img.alpha_composite(layer)
    out = OUT / (name + ".png")
    img.convert("RGB").save(out)
    print(out, len(data["items"]), "items")
    for i in data.get("issues", [])[:40]:
        print("  ", i)


main(sys.argv[1] if len(sys.argv) > 1 else "panel")
