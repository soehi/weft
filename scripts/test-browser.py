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
        # D2 uses a distinct explicit profile/page. Download both reviewed
        # artifacts from an actual Worker, compare CLI bytes, then verify.
        page.goto(url + "/deployment.html")
        expect(page.locator("#check")).to_be_enabled()
        for provider in ["source", "alternate", "missing"]:
            page.locator(f"[data-provider={provider}]").click()
            expect(page.locator("#status")).to_contain_text("示例已载入")
            page.locator("#check").click()
            if provider == "missing":
                expect(page.locator("#diagnostic code")).to_have_text("MISSING_MEMBER")
                expect(page.locator("#success")).to_be_hidden()
                continue
            expect(page.locator("#success")).to_be_visible()
            downloaded = {}
            for button, filename, shown in [("download", "sealed-plan.json", "plan-json"), ("download-lock", "inputs.lock.json", "lock-json")]:
                with page.expect_download() as download:
                    page.locator("#" + button).click()
                raw = Path(download.value.path()).read_bytes()
                assert raw == page.locator("#" + shown).text_content().encode("utf-8")
                (temp / filename).write_bytes(raw)
                downloaded[filename] = raw
            value = json.loads(page.locator("#manifest").input_value())
            for component in value["components"]:
                (temp / component["path"]).write_bytes((ROOT / "examples/instances" / component["path"]).read_bytes())
            (temp / "instance.json").write_text(json.dumps(value), encoding="utf-8")
            subprocess.run(["moon", "run", "src/compose_cli", "--target", "js", "--", "seal", str(temp / "instance.json"), "--out", str(temp / "cli-sealed.json"), "--lock", str(temp / "cli-lock.json")], cwd=ROOT, check=True)
            assert downloaded["sealed-plan.json"] == (temp / "cli-sealed.json").read_bytes()
            assert downloaded["inputs.lock.json"] == (temp / "cli-lock.json").read_bytes()
            subprocess.run(["moon", "run", "src/compose_cli", "--target", "js", "--", "verify", str(temp / "sealed-plan.json"), "--lock", str(temp / "inputs.lock.json"), "--inputs", str(temp / "instance.json")], cwd=ROOT, check=True)
        # Local selection remains local; edits immediately invalidate both downloads.
        value = json.loads((ROOT / "examples/instances/chain.json").read_text(encoding="utf-8"))
        for component in value["components"]: component["path"] = "C:\\reviewed\\" + component["path"]
        (temp / "user-instance.json").write_text(json.dumps(value), encoding="utf-8")
        request_count = len(requests)
        page.locator("#manifest-file").set_input_files(temp / "user-instance.json")
        page.locator("#component-files").set_input_files([ROOT / "examples/instances/source.wasm", ROOT / "examples/instances/consumer.wasm"])
        page.locator("#check").click()
        expect(page.locator("#success")).to_be_visible()
        assert request_count == len(requests), "D2 selected files caused network traffic"
        page.screenshot(path=str(ROOT / "_build/deployment-mobile.png"), full_page=True)
        assert page.evaluate("document.documentElement.scrollWidth <= innerWidth")
        page.locator("#manifest").fill('{"manifest_version":"0.3.0","manifest_version":"0.3.0"}')
        expect(page.locator("#success")).to_be_hidden()
        page.locator("#check").click()
        expect(page.locator("#diagnostic code")).to_have_text("INVALID_JSON")
        page.locator("#manifest-file").set_input_files({"name":"bad.json","mimeType":"application/json","buffer":bytes([123,255,125])})
        expect(page.locator("#diagnostic code")).to_have_text("BROWSER_UTF8")
        print("OK: D2 Chromium plan+lock downloads equal CLI and verify, alternate/missing members, local files, stale results and mobile")
        assert not errors, errors
        assert all(method == "GET" and address.startswith(url) for method,address in requests)
        # Worker bootstrap failure remains visible and cannot enable planning.
        broken = browser.new_page()
        broken.route("**/planner.mjs", lambda route: route.abort())
        broken.goto(url)
        expect(broken.locator("#diagnostic code")).to_have_text("BROWSER_WORKER")
        expect(broken.locator("#check")).to_be_disabled()
        broken_deploy = browser.new_page()
        broken_deploy.route("**/deployment-planner.mjs", lambda route: route.abort())
        broken_deploy.goto(url + "/deployment.html")
        expect(broken_deploy.locator("#diagnostic code")).to_have_text("BROWSER_WORKER")
        expect(broken_deploy.locator("#check")).to_be_disabled()
        browser.close()
        print("OK: downloads match CLI, user files stay local, mapping ambiguity, duplicate JSON, stale download invalidation, mobile and no browser errors")
finally:
    server.shutdown()
    server.server_close()
