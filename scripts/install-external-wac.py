"""Install one official checksum-locked development tool without changing PATH."""
import hashlib
import json
import os
import platform
import tempfile
import urllib.request
from pathlib import Path

root = Path(__file__).resolve().parents[1]
lock = json.loads((root / "release/external-tools.lock.json").read_text(encoding="utf-8"))["wac"]
system = {"Windows": "windows", "Linux": "linux"}.get(platform.system())
assert system and platform.machine().lower() in {"amd64", "x86_64"}, "unverified tool platform"
asset = lock["assets"][f"{system}-x86_64"]
destination = root / "_build/external" / ("wac.exe" if system == "windows" else "wac")
destination.parent.mkdir(parents=True, exist_ok=True)

def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()

if destination.exists():
    assert sha(destination) == asset["sha256"], "existing tool differs from lock; inspect it before replacing"
else:
    with tempfile.NamedTemporaryFile(dir=destination.parent, prefix="wac-download-", delete=False) as stream:
        temporary = Path(stream.name)
    try:
        with urllib.request.urlopen(asset["url"], timeout=60) as response, temporary.open("wb") as stream:
            while chunk := response.read(1024 * 1024):
                stream.write(chunk)
        assert sha(temporary) == asset["sha256"], "official WAC download differs from lock"
        temporary.chmod(0o755)
        os.replace(temporary, destination)
    finally:
        temporary.unlink(missing_ok=True)
print(f"OK: checksum-locked WAC {lock['version']} at {destination.relative_to(root)}")
