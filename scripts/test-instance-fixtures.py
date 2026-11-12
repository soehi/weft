"""Ensure the committed D0 binaries match the shared WAT fixture factory."""
import subprocess
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
(root / "_build").mkdir(exist_ok=True)
names = ["source", "alternate", "missing", "wrong-type", "consumer"]
with tempfile.TemporaryDirectory(prefix="instance probe ", dir=root / "_build") as directory:
    subprocess.run(
        ["moon", "run", "src/tools/make_instance_fixtures", "--target", "native", "--", directory],
        cwd=root, check=True, timeout=120,
    )
    for name in names:
        assert (Path(directory) / f"{name}.wasm").read_bytes() == (
            root / "examples/instances" / f"{name}.wasm"
        ).read_bytes(), name
print("OK: five committed instance binaries match the fixture factory")
