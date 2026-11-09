"""Build auditable native/Node CLI bundles without publishing a Release."""
import hashlib
import json
import os
import platform
import re
import runpy
import shutil
import subprocess
import tempfile
import zipfile
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
checks = runpy.run_path(str(ROOT / "scripts/check-release-inputs.py"))

def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()

def main():
    checks["check_toolchain"]()
    checks["check_dependencies"]()
    version = re.search(r'^version = "([^"]+)"', (ROOT / "moon.mod").read_text(encoding="utf-8"), re.M)[1]
    assert f"weft {version} (plan 0.2.0)" in (ROOT / "src/cli/core.mbt").read_text(encoding="utf-8"), "CLI version differs from module"
    assert not subprocess.check_output(["git", "diff", "HEAD", "--name-only"], cwd=ROOT).strip(), "commit tracked source changes before release verification"
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    for target in ["native", "js"]:
        subprocess.run(["moon", "build", "src/cli", "--target", target, "--release"], cwd=ROOT, check=True)
    output = ROOT / "_build/release"
    output.mkdir(parents=True, exist_ok=True)
    target = "windows-x86_64" if os.name == "nt" else "linux-x86_64"
    name = f"weft-{version}-{target}"
    archive = output / (name + ".zip")
    with tempfile.TemporaryDirectory(prefix="weft-package-", dir=output) as temporary:
        bundle = Path(temporary) / name
        bundle.mkdir()
        native_name = "weft.exe" if os.name == "nt" else "weft"
        shutil.copy2(ROOT / "_build/native/release/build/cli/cli.exe", bundle / native_name)
        shutil.copy2(ROOT / "_build/js/release/build/cli/cli.js", bundle / "weft.mjs")
        for file in ["LICENSE", "release/toolchain.lock.json", "release/dependencies.lock.json", "release/CANDIDATE.md", "release/THIRD-PARTY.md"]:
            shutil.copy2(ROOT / file, bundle / Path(file).name)
        shutil.copytree(ROOT / "examples/browser", bundle / "examples/browser", ignore=shutil.ignore_patterns("README.md"))
        for file in ["chain.json", "format.json", "reader.wasm", "filter.wasm", "sink.wasm", "join.wasm", "wide-sink.wasm"]:
            shutil.copy2(ROOT / "examples" / file, bundle / "examples" / file)
            if file.endswith(".wasm"): shutil.copy2(ROOT / "examples" / file, bundle / "examples/browser" / file)
        (bundle / "golden.json").write_bytes((ROOT / "docs/fixtures/plan-v0.2.0.json").read_bytes())
        notices = []
        for module in checks["check_dependencies"]():
            path = ROOT / ".mooncakes" / module["name"]
            notices.append(module["name"] + "@" + module["version"])
            for license_file in sorted([*path.glob("LICENSE*"), *path.glob("NOTICE*")]):
                if license_file.is_file(): notices.append(license_file.read_text(encoding="utf-8", errors="replace"))
        (bundle / "THIRD-PARTY.txt").write_text("\n\n".join(notices), encoding="utf-8")
        metadata = {"version":version,"plan_version":"0.2.0","commit":commit,"target":target,"toolchain":json.loads((ROOT / "release/toolchain.lock.json").read_text(encoding="utf-8")),"dependencies":checks["check_dependencies"]()}
        (bundle / "BUILD.json").write_text(json.dumps(metadata, indent=2)+"\n", encoding="utf-8")
        (bundle / "README.txt").write_text("weft "+version+"\nNative: "+native_name+" --version\nNode.js 24+: node weft.mjs --version\nPlan: node weft.mjs plan examples/chain.json --out plan.json\nVerify SHA256SUMS before use; BUILD.json records source and toolchain. No native execution adapter is included.\n", encoding="utf-8")
        sums = "".join(sha(f)+"  "+f.relative_to(bundle).as_posix()+"\n" for f in sorted(bundle.rglob("*")) if f.is_file())
        (bundle / "SHA256SUMS").write_text(sums, encoding="ascii")
        with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as writer:
            for path in sorted(bundle.rglob("*")):
                if path.is_file():
                    info = zipfile.ZipInfo(path.relative_to(bundle.parent).as_posix(), (1980,1,1,0,0,0))
                    info.compress_type = zipfile.ZIP_DEFLATED
                    info.external_attr = (0o755 if path.name == native_name else 0o644) << 16
                    writer.writestr(info, path.read_bytes())
    archive.with_suffix(".zip.sha256").write_text(sha(archive)+"  "+archive.name+"\n", encoding="ascii")
    print(archive)
    return archive

if __name__ == "__main__": main()
