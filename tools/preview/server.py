"""The panel preview's local end (a dev tool; see tools/preview/panel.lua).

python tools/preview/server.py      serves on 127.0.0.1:8766:
  GET  /tree.json        every module of src/ as {path: source}, as tools/tree.py reads it (read fresh each time)
  GET  /suite.lua        tests/suite.lua (run_suite.lua runs it against what's on disk)
  GET  /<file>           a file of tools/preview (panel.lua, dump.lua, shots.lua, run_suite.lua)
  POST /<name>           a panel dump from dump.lua, saved as tools/preview/out/<name>.json
Then python tools/preview/render.py <name> draws it.

For loader_run.lua (the loader's update code, run for real against a stand-in update site):
  GET  /loader.lua               Loader.lua as build 1, updating from /release, checking every second, with its own
                                 mirror name (the installed plugin's is left alone)
  GET  /release/bundled.json     the stand-in release's modules at build 1 (what the loader starts with)
  GET  /release/set/<build>/<how>  what the site publishes from now on; how: ok, fail (one module can't be had), cut
                                 (one arrives cut off), bad (it won't start) or down (the site can't be reached)
  GET  /release/asked            the modules asked for since the last call, one per line
  GET  /release/release.json, /release/modules/…   the release itself"""
import http.server
import json
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import tree as T  # noqa: E402

OUT = HERE / "out"

# The stand-in release: five modules, of which App and App/B change with every build.
RELEASE = {"build": 1, "how": "ok", "asked": []}
APP = """return function(ctx)
	_G.SS_LoaderRun.ctx = ctx
	table.insert(_G.SS_LoaderRun.starts, ctx.version)
	%s
	return function()
		table.insert(_G.SS_LoaderRun.stops, ctx.version)
	end
end
"""


def release_modules(build, how="ok"):
    return {
        "Engine": "return { TAG = 'stand-in' }\n",
        "App": APP % ('error("this release is broken")' if how == "bad" else "-- build %d" % build),
        "App/A": "return function() end\n",
        "App/B": "return %d\n" % build,
        "App/C": "return function() end -- é\n",
    }


def loader_source():
    src = T.read(T.ROOT / "Loader.lua")
    for old, new in (
        ("__BUILD__", "1"),
        ("__VERSION__", "t1"),
        ("__UPDATE_URL__", "http://127.0.0.1:8766/release"),
        ('"SmartScatterSource"', '"SS_LoaderRunMirror"'),
        ("60 or 300", "1 or 1"),
    ):
        assert old in src, old
        src = src.replace(old, new)
    return src


class Handler(http.server.BaseHTTPRequestHandler):
    def reply(self, body, kind="text/plain"):
        self.send_response(200)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        name = self.path.strip("/")
        if name == "tree.json":
            self.reply(json.dumps(T.tree()).encode("utf-8"), "application/json")
            return
        if name == "loader.lua":
            self.reply(loader_source().encode("utf-8"))
            return
        if name.startswith("release/"):
            self.release(name[len("release/") :])
            return
        f = HERE.parent.parent / "tests" / "suite.lua" if name == "suite.lua" else HERE / name
        if f.is_file() and f.suffix == ".lua":
            self.reply(f.read_bytes())
            return
        self.send_error(404)

    def release(self, name):
        build, how = RELEASE["build"], RELEASE["how"]
        modules = release_modules(build, how)
        if name.startswith("set/"):
            _, b, RELEASE["how"] = name.split("/")
            RELEASE["build"] = int(b)
            RELEASE["asked"].clear()
            self.reply(b"set")
        elif name == "asked":
            self.reply("\n".join(RELEASE["asked"]).encode("utf-8"))
            RELEASE["asked"].clear()
        elif name == "bundled.json":
            self.reply(json.dumps(release_modules(1)).encode("utf-8"), "application/json")
        elif name == "release.json" and how != "down":
            listed = {k: {"path": "modules/%s.lua" % k, "sum": T.checksum(v)} for k, v in modules.items()}
            self.reply(json.dumps({"build": build, "version": "t%d" % build, "modules": listed}).encode("utf-8"), "application/json")
        elif name.startswith("modules/") and name[8:-4] in modules:
            path = name[8:-4]
            RELEASE["asked"].append(path)
            if path == "App/B" and how == "fail":
                self.send_error(404)
            else:
                body = modules[path].encode("utf-8")
                self.reply(body[: len(body) // 2] if path == "App/B" and how == "cut" else body)
        else:
            self.send_error(404)

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        OUT.mkdir(exist_ok=True)
        name = self.path.strip("/").replace("/", "_") or "panel"
        (OUT / (name + ".json")).write_bytes(body)
        self.reply(b"saved %d bytes" % len(body))

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    http.server.ThreadingHTTPServer(("127.0.0.1", 8766), Handler).serve_forever()
