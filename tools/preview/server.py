"""The panel preview's local end (a dev tool; see tools/preview/panel.lua).

python tools/preview/server.py      serves on 127.0.0.1:8766:
  GET  /tree.json        every module of src/ as {path: source}, as tools/tree.py reads it (read fresh each time)
  GET  /suite.lua        tests/suite.lua (run_suite.lua runs it against what's on disk)
  GET  /<file>           a file of tools/preview (panel.lua, dump.lua, shots.lua, run_suite.lua)
  POST /<name>           a panel dump from dump.lua, saved as tools/preview/out/<name>.json
Then python tools/preview/render.py <name> draws it."""
import http.server
import json
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import tree as T  # noqa: E402

OUT = HERE / "out"


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
        f = HERE.parent.parent / "tests" / "suite.lua" if name == "suite.lua" else HERE / name
        if f.is_file() and f.suffix == ".lua":
            self.reply(f.read_bytes())
            return
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
