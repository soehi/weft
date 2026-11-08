"""Verify extraction and first use in a clean directory with no MoonBit needed."""
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

def sha(path):
    with path.open("rb") as stream: return hashlib.file_digest(stream, "sha256").hexdigest()

def main():
    archive = Path(sys.argv[1]).resolve()
    assert sha(archive) == archive.with_suffix(".zip.sha256").read_text(encoding="utf-8").split()[0]
    with tempfile.TemporaryDirectory(prefix="weft clean install ") as temporary:
        clean = Path(temporary)
        with zipfile.ZipFile(archive) as reader:
            for entry in reader.infolist(): assert (clean / entry.filename).resolve().is_relative_to(clean)
            reader.extractall(clean)
        root, = [path for path in clean.iterdir() if path.is_dir()]
        for line in (root / "SHA256SUMS").read_text(encoding="utf-8").splitlines():
            expected, name = line.split("  ", 1)
            path = (root / name).resolve()
            assert path.is_relative_to(root) and sha(path) == expected, name
        binary = root / ("weft.exe" if os.name == "nt" else "weft")
        if os.name != "nt": binary.chmod(0o755)
        meta = json.loads((root / "BUILD.json").read_text(encoding="utf-8"))
        # Invocations only use the extracted CLI and Node; there is no moon.mod or dependency cache here.
        for command in [[str(binary)], ["node", str(root / "weft.mjs")]]:
            version = subprocess.check_output(command+["--version"], cwd=clean, text=True).strip()
            assert version == f"weft {meta['version']} (plan 0.2.0)"
            out = clean / "output.json"
            subprocess.run(command+["plan", str(root / "examples/chain.json"), "--out", str(out)], cwd=clean, check=True)
            assert out.read_bytes() == (root / "golden.json").read_bytes()
            assert subprocess.run(command+["plan", str(root / "examples/no-such-file.json")], cwd=clean, stdout=subprocess.PIPE).returncode != 0
        print("OK: extracted native + Node CLI, file checksums, version and golden plan from clean foreign directory")

if __name__ == "__main__": main()
