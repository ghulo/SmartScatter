"""Bundle src/engine/NN_*.lua into Engine.lua (one ModuleScript).

The engine is one scope: the parts are concatenated in file-name order, so locals defined in an earlier part are
visible in later ones exactly as before the split. Edit the parts, not Engine.lua."""
import pathlib

here = pathlib.Path(__file__).resolve().parent.parent
parts = sorted((here / "src" / "engine").glob("[0-9][0-9]_*.lua"))

def text_of(p):
    t = p.read_text(encoding="utf-8").replace("\r\n", "\n")
    return t[:-1] if t.endswith("\n") else t  # each part file ends with one newline that is not part of the engine


body = "\n".join(text_of(p) for p in parts)
(here / "Engine.lua").write_bytes((body).encode("utf-8"))
print("Engine.lua", len(body.encode()), "bytes from", len(parts), "parts")
