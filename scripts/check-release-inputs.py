"""Fail closed when the selected toolchain or resolved dependencies drift."""
import json
import re
import subprocess
import os
import shutil
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]

def check_toolchain():
    lock = json.loads((ROOT / "release/toolchain.lock.json").read_text())
    text = subprocess.check_output(["moon", "version", "--all"], text=True, encoding="utf-8")
    for key in ["moon", "moonc", "moonrun"]:
        assert re.search(r"(?m)^" + key + r" " + re.escape(lock[key]) + r"(?: |$)", text), f"unexpected {key}; use the locked toolchain"
    tool_home = Path(os.environ.get("MOON_HOME", str(Path(shutil.which("moon")).resolve().parent.parent)))
    core = (tool_home / "lib/core/moon.mod").read_text(encoding="utf-8")
    assert re.search(r'^version\s*=\s*"' + re.escape(lock["core"]) + r'"', core, re.M), "core version differs from toolchain lock"
    return text

def check_dependencies():
    lock = json.loads((ROOT / "release/dependencies.lock.json").read_text())["modules"]
    found = []
    for path in (ROOT / ".mooncakes").glob("*/*/moon.mod"):
        text = path.read_text(encoding="utf-8")
        name = re.search(r'^name\s*=\s*"([^"]+)"', text, re.M)
        version = re.search(r'^version\s*=\s*"([^"]+)"', text, re.M)
        if name and version:
            found.append({"name": name[1], "version": version[1]})
    assert sorted(found, key=lambda x: x["name"]) == lock, "resolved dependency graph differs from release/dependencies.lock.json"
    return lock

if __name__ == "__main__":
    check_toolchain()
    check_dependencies()
    print("OK: pinned compiler and 17 resolved dependency versions")
