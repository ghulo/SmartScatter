"""Panel preview (a dev tool): draws each named dump (render.py) and puts them side by side at half size in
out/<sheet>.png.  python tools/preview/sheet.py <sheet> <name> <name> …"""
import pathlib
import subprocess
import sys

from PIL import Image

HERE = pathlib.Path(__file__).resolve().parent
OUT = HERE / "out"

sheet, names = sys.argv[1], sys.argv[2:]
for n in names:
    subprocess.run([sys.executable, str(HERE / "render.py"), n], check=True)
ims = [Image.open(OUT / (n + ".png")) for n in names]
w = sum(i.width // 2 + 10 for i in ims)
h = max(i.height // 2 for i in ims)
out = Image.new("RGB", (w, h), (255, 255, 255))
x = 0
for i in ims:
    out.paste(i.resize((i.width // 2, i.height // 2)), (x, 0))
    x += i.width // 2 + 10
out.save(OUT / (sheet + ".png"))
print(OUT / (sheet + ".png"))
