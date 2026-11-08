"""Real Chromium end-to-end checks; no external server or uploads."""
import json
import tempfile
import threading
import subprocess
from functools import partial
from pathlib import Path
from http.server import ThreadingHTTPServer
from playwright.sync_api import sync_playwright, expect
from importlib.util import spec_from_file_location, module_from_spec
_spec = spec_from_file_location("serve_demo", Path(__file__).with_name("serve-demo.py"))
_module = module_from_spec(_spec)
_spec.loader.exec_module(_module)
DemoHandler = _module.DemoHandler
ROOT = Path(__file__).resolve().parents[1]

class QuietHandler(DemoHandler):
    def log_message(self, *_): pass

server = ThreadingHTTPServer(("127.0.0.1", 0), partial(QuietHandler, directory=str(ROOT / "demo")))
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
url = f"http://127.0.0.1:{server.server_port}"
try:
    with tempfile.TemporaryDirectory(prefix="weft-browser-") as tmp, sync_playwright() as p:
        temp = Path(tmp)
        browser = p.chromium.launch()
        page = browser.new_page(viewport={"width": 1440, "height": 1000}, accept_downloads=True)
        errors, requests = [], []
        page.on("pageerror", lambda e: errors.append(str(e)))
        page.on("request", lambda r: requests.append((r.method, r.url)))
        page.goto(url)
        expect(page.locator("#check")).to_be_enabled()
        for name, code in [("chain", None), ("diamond", None), ("cycle", "PLAN_CYCLE"), ("type-mismatch", "PLAN_TYPE_MISMATCH"), ("missing-import", "PLAN_UNBOUND_IMPORT")]:
            page.locator(f"[data-case={name}]").click()
            expect(page.locator("#status")).to_contain_text("示例已载入")
            page.locator("#check").click()
            if code:
                expect(page.locator("#diagnostic code")).to_have_text(code)
                expect(page.locator("#success")).to_be_hidden()
            else:
                expect(page.locator("#success")).to_be_visible()
                plan = json.loads(page.locator("#plan-json").text_content())
                expect(page.locator("#graph g[data-component]")).to_have_count(len(plan["instances"]))
                expect(page.locator("#instances tr")).to_have_count(len(plan["instances"]))
                with page.expect_download() as download:
                    page.locator("#download").click()
                raw = Path(download.value.path()).read_bytes()
                assert raw == page.locator("#plan-json").text_content().encode("utf-8")
                m = json.loads((ROOT / f"examples/browser/{name}.json").read_text())
                for c in m["components"]:
                    (temp / c["path"]).write_bytes((ROOT / "examples" / c["path"]).read_bytes())
                (temp / "manifest.json").write_text(json.dumps(m), encoding="utf-8")
                subprocess.run(["moon", "run", "src/cli", "--target", "js", "--", "plan", str(temp / "manifest.json"), "--out", str(temp / "cli.json")], cwd=ROOT, check=True)
                assert raw == (temp / "cli.json").read_bytes()
            print(f"OK: Chromium {name}")
        # User-selected files: absolute manifest paths remain logical labels.
        manifest = {"components": [{"name": "source", "path": "C:\\original\\reader.wasm"}, {"name": "sink", "path": "/original/sink.wasm"}], "wires": [{"from": "source.read", "to": "sink.in"}]}
        (temp / "user.json").write_text(json.dumps(manifest), encoding="utf-8")
        baseline = len(requests)
        page.locator("#manifest-file").set_input_files(temp / "user.json")
        page.locator("#component-files").set_input_files([ROOT / "examples/reader.wasm", ROOT / "examples/sink.wasm"])
        expect(page.locator("#file-0")).to_have_value("0")
        page.locator("#check").click()
        expect(page.locator("#success")).to_be_visible()
        assert len(requests) == baseline, "user files caused a network request"
        page.locator("#manifest").fill('{"components":[],"components":[]}')
        expect(page.locator("#success")).to_be_hidden()
        page.locator("#check").click()
        expect(page.locator("#diagnostic code")).to_have_text("MANIFEST_JSON")
        # Ambiguous basenames require an explicit choice.
        page.locator("#manifest").fill('{"components":[{"name":"a","path":"same.wasm"}]}')
        component = (ROOT / "examples/reader.wasm").read_bytes()
        page.locator("#component-files").set_input_files([{"name":"same.wasm","mimeType":"application/wasm","buffer":component}, {"name":"same.wasm","mimeType":"application/wasm","buffer":component}])
        expect(page.locator("#file-0")).to_have_value("-1")
        page.locator("#check").click()
        expect(page.locator("#diagnostic code")).to_have_text("BROWSER_FILE_MISSING")
        page.locator("#file-0").select_option("1")
        page.locator("#check").click()
        expect(page.locator("#success")).to_be_visible()
        # Malformed UTF-8 invalidates a previously downloadable result.
        page.locator("#manifest-file").set_input_files({"name":"bad.json","mimeType":"application/json","buffer":bytes([123,255,125])})
        expect(page.locator("#diagnostic code")).to_have_text("BROWSER_UTF8")
        expect(page.locator("#success")).to_be_hidden()
        # Narrow viewport: controls remain usable and page itself does not overflow.
        page.set_viewport_size({"width":390,"height":844})
        page.locator('[data-case=diamond]').click()
        expect(page.locator("#status")).to_contain_text("示例已载入")
        page.locator("#check").click()
        expect(page.locator("#success")).to_be_visible()
        assert page.evaluate("document.documentElement.scrollWidth <= innerWidth")
        page.screenshot(path=str(ROOT / "_build/demo-mobile.png"), full_page=True)
        assert not errors, errors
        assert all(method == "GET" and address.startswith(url) for method,address in requests)
        # Worker bootstrap failure remains visible and cannot enable planning.
        broken = browser.new_page()
        broken.route("**/planner.mjs", lambda route: route.abort())
        broken.goto(url)
        expect(broken.locator("#diagnostic code")).to_have_text("BROWSER_WORKER")
        expect(broken.locator("#check")).to_be_disabled()
        browser.close()
        print("OK: downloads match CLI, user files stay local, mapping ambiguity, duplicate JSON, stale download invalidation, mobile and no browser errors")
finally:
    server.shutdown()
    server.server_close()
