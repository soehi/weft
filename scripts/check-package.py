"""Inspect the actual Mooncakes archive, excluding caches and machine-specific evidence."""
import hashlib
import json
import subprocess
import zipfile
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[1]
subprocess.run(["moon", "package"], cwd=ROOT, check=True)
archive = ROOT / "_build/publish/soehi-weft-0.3.0.zip"
with zipfile.ZipFile(archive) as reader:
    names = reader.namelist()
    required = ["moon.mod", ".moonignore", "README.md", "LICENSE", "src/api/compile.mbt", "src/api/pkg.generated.mbti", "release/CANDIDATE.md", "release/THIRD-PARTY.md", "examples/chain.json", "examples/reader.wasm", "docs/API.md"]
    for name in required:
        assert name in names, f"missing package input: {name}"
    for name in names:
        path = PurePosixPath(name)
        assert not path.is_absolute() and ".." not in path.parts, name
        assert not set(path.parts) & {"_build", ".mooncakes", ".git", "__pycache__"}, name
        assert not name.startswith("docs/benchmarks/") and name not in {"项目申报书.md", "docs/SUBMISSION.md"}, name
        if path.suffix in {".md", ".json", ".mod", ".pkg"}:
            text = reader.read(name).decode("utf-8")
            assert str(ROOT) not in text and "C:\\Users\\ASUS" not in text, name
report = {"source_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
          "module_version":"0.3.0", "plan_version":"0.2.0", "files":names,
          "archive_sha256":hashlib.sha256(archive.read_bytes()).hexdigest(),
          "toolchain":json.loads((ROOT/"release/toolchain.lock.json").read_text(encoding="utf-8")),
          "dependencies":json.loads((ROOT/"release/dependencies.lock.json").read_text(encoding="utf-8"))}
output = ROOT / "_build/release"
output.mkdir(exist_ok=True)
(output/"candidate.json").write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")
print(f"OK: {len(names)} package entries, required docs/interfaces/licenses, no caches or local evidence; SHA-256 {report['archive_sha256']}")
