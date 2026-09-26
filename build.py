"""Bundle Loader + Engine + Main into SmartScatter.rbxmx (a local plugin file)."""
import sys, pathlib, datetime

here = pathlib.Path(__file__).parent
version = sys.argv[1] if len(sys.argv) > 1 else datetime.datetime.now().strftime("%y.%m%d.%H%M")
build = sys.argv[2] if len(sys.argv) > 2 else "1"

import subprocess
# Engine.lua and Main.lua are generated from src/engine/*.lua and src/*.lua: rebuild both so the file is never stale
for tool in ("bundle_engine.py", "bundle.py"):
    if subprocess.run([sys.executable, str(here / "tools" / tool)]).returncode != 0:
        sys.exit("build stopped: " + tool + " failed")
if subprocess.run([sys.executable, str(here / "tools" / "lint_dupes.py"), str(here / "Engine.lua")]).returncode != 0:
    sys.exit("build stopped: Engine.lua defines the same name twice")

def cdata(src: str) -> str:
    return "<![CDATA[" + src.replace("]]>", "]]]]><![CDATA[>") + "]]>"

def item(cls, ref, name, src, children=""):
    return (f'<Item class="{cls}" referent="{ref}"><Properties>'
            f'<string name="Name">{name}</string>'
            f'<ProtectedString name="Source">{cdata(src)}</ProtectedString>'
            f'</Properties>{children}</Item>')

# where releases are published: update_url.txt (one line, no trailing slash), e.g. a GitHub raw URL of the dist folder
url_file = here / "update_url.txt"
update_url = url_file.read_text().strip() if url_file.exists() else ""
loader = ((here / "Loader.lua").read_text().replace("__VERSION__", version).replace("__BUILD__", build)
          .replace("__UPDATE_URL__", update_url))
engine = (here / "Engine.lua").read_text()
main = (here / "Main.lua").read_text()
parts = sorted([p for p in here.glob("Main_[0-9]*.lua") if p.stem[5:].isdigit()], key=lambda p: int(p.stem.split("_")[1]))

xml = ('<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
       'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
       'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">'
       + item("Script", "RBX0", "SmartScatter", loader,
              item("ModuleScript", "RBX1", "Engine", engine) + item("ModuleScript", "RBX2", "Main", main)
              + "".join(item("ModuleScript", "RBX%d" % (3 + k), p.stem, p.read_text()) for k, p in enumerate(parts)))
       + '</roblox>')
out = here / "SmartScatter.rbxmx"
out.write_text(xml)
print(out, len(xml), "bytes, version", version)

# the release: what installed copies download (upload the dist folder to where update_url.txt points)
import json
def checksum(text):
    h = 0
    for c in text.encode():
        h = (h * 31 + c) % 1000000007
    return h
dist = here / "dist"
dist.mkdir(exist_ok=True)
for old in dist.glob("*.lua"):
    old.unlink()
files = {}
for name, src in [("Engine", engine), ("Main", main)] + [(p.stem, p.read_text()) for p in parts]:
    (dist / (name + ".lua")).write_text(src)
    files[name] = {"path": name + ".lua", "sum": checksum(src)}
(dist / "manifest.json").write_text(json.dumps({"version": version, "build": int(build), "files": files}, indent=1))
print("release in", dist, "build", build, "->", update_url or "(no update_url.txt: online updates off)")
