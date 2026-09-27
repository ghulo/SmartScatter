"""Build Smart Scatter: python3 build.py <version> <build number>

Writes
  SmartScatter.rbxmx   the plugin file: the loader Script with the App and Engine module trees inside
  dist/                the online release every installed copy updates from (push it to where update_url.txt points):
    release.json + modules/…     the module tree, for loaders from 9.45 on
    manifest.json + *.lua        the same code flattened into Engine / Main / Main_2…, for older loaders (tools/tree.py)
The build number must be higher than the last release's, or installed copies won't take it."""
import json
import pathlib
import shutil
import sys
import datetime

here = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(here / "tools"))
import tree as T  # noqa: E402

version = sys.argv[1] if len(sys.argv) > 1 else datetime.datetime.now().strftime("%y.%m%d.%H%M")
build = sys.argv[2] if len(sys.argv) > 2 else "1"

t = T.tree()
T.check(t)

# ── the plugin file ─────────────────────────────────────────────────────────────
url_file = here / "update_url.txt"
update_url = T.read(url_file).strip() if url_file.exists() else ""
loader = T.read(here / "Loader.lua").replace("__VERSION__", version).replace("__BUILD__", build).replace("__UPDATE_URL__", update_url)


def cdata(src):
    return "<![CDATA[" + src.replace("]]>", "]]]]><![CDATA[>") + "]]>"


refs = iter(range(1, 100000))


def item(cls, name, src=None, children=""):
    props = '<string name="Name">%s</string>' % name
    if src is not None:
        props += '<ProtectedString name="Source">%s</ProtectedString>' % cdata(src)
    return '<Item class="%s" referent="RBX%d"><Properties>%s</Properties>%s</Item>' % (cls, next(refs), props, children)


def node(path):
    """a path of the tree as an Item: a ModuleScript if it has a source, else a Folder; children below it"""
    kids = sorted({p[len(path) + 1:].split("/")[0] for p in t if p.startswith(path + "/")})
    inner = "".join(node(path + "/" + k) for k in kids)
    name = path.split("/")[-1]
    return item("ModuleScript", name, t[path], inner) if path in t else item("Folder", name, None, inner)


xml = ('<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
       'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">'
       + item("Script", "SmartScatter", loader, "".join(node(e) for e in T.ENTRIES)) + "</roblox>")
(here / "SmartScatter.rbxmx").write_bytes(xml.encode("utf-8"))
print("SmartScatter.rbxmx", len(xml), "bytes, version", version, "build", build, "-", len(t), "modules")

# ── the release ─────────────────────────────────────────────────────────────────
dist = here / "dist"
if dist.exists():
    shutil.rmtree(dist)
(dist / "modules").mkdir(parents=True)
modules = {}
for path, src in t.items():
    f = dist / "modules" / (path + ".lua")
    f.parent.mkdir(parents=True, exist_ok=True)
    f.write_bytes(src.encode("utf-8"))
    modules[path] = {"path": "modules/" + path + ".lua", "sum": T.checksum(src)}
(dist / "release.json").write_bytes(json.dumps({"version": version, "build": int(build), "modules": modules}, indent=1).encode("utf-8"))

legacy = T.legacy(t)
files = {}
for name, src in legacy.items():
    (dist / (name + ".lua")).write_bytes(src.encode("utf-8"))
    files[name] = {"path": name + ".lua", "sum": T.checksum(src)}
(dist / "manifest.json").write_bytes(json.dumps({"version": version, "build": int(build), "files": files}, indent=1).encode("utf-8"))
print("release in dist/:", len(modules), "modules +", len(legacy), "flattened scripts ->", update_url or "(no update_url.txt: online updates off)")
