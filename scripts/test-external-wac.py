"""D0 external oracle: named instance transfer, wrong type and missing members."""
import hashlib
import json
import platform
import subprocess
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
lock = json.loads((root / "release/external-tools.lock.json").read_text(encoding="utf-8"))["wac"]
system = "windows" if platform.system() == "Windows" else "linux"
tool = root / "_build/external" / ("wac.exe" if system == "windows" else "wac")
with tool.open("rb") as stream:
    assert hashlib.file_digest(stream, "sha256").hexdigest() == lock["assets"][f"{system}-x86_64"]["sha256"]
assert subprocess.check_output([str(tool), "--version"], text=True, encoding="utf-8").strip() == f"wac-cli {lock['version']}"
(root / "_build").mkdir(exist_ok=True)
source = (root / "examples/instances/compose.wac").read_text(encoding="utf-8")
with tempfile.TemporaryDirectory(prefix="external instance ", dir=root / "_build") as directory:
    work = Path(directory)
    products = []
    for mode in ["source", "alternate", "missing", "wrong-type", "disconnected"]:
        script = work / f"{mode}.wac"
        script.write_text(source.replace("ops: provider.ops,", "") if mode == "disconnected" else source, encoding="utf-8")
        output = work / f"{mode}.wasm"
        provider = "source" if mode == "disconnected" else mode
        result = subprocess.run([
            str(tool), "compose", str(script),
            "--dep", f"d0:provider={root / 'examples/instances' / (provider + '.wasm')}",
            "--dep", f"d0:consumer={root / 'examples/instances/consumer.wasm'}",
            "-o", str(output),
        ], text=True, encoding="utf-8", capture_output=True, timeout=30)
        if mode in {"source", "alternate"}:
            assert result.returncode == 0, result.stderr
            data = output.read_bytes()
            assert data[:8] == bytes.fromhex("0061736d0d000100"), "not a component binary"
            products.append(data)
        else:
            assert result.returncode != 0 and not output.exists(), mode
            required = {"missing": ["twice"], "wrong-type": ["value", "u32", "bool"], "disconnected": ["ops"]}[mode]
            assert all(word in result.stderr for word in required), result.stderr
        print(f"OK: WAC {lock['version']} instance case {mode}")
    assert products[0] != products[1], "different provider contents must change composed artifacts"
    # Validate WAC emitted from D1's checked composition, using the independent
    # Rust composer instead of the decoder used by our own type adapter.
    emitted = work / "d1-emitted.wac"
    subprocess.run([
        "moon", "run", "src/compose_cli", "--target", "js", "--", "emit-wac",
        str(root / "examples/instances/chain.json"), "--out", str(emitted),
    ], cwd=root, check=True, timeout=120)
    for provider in ["source", "alternate", "missing", "wrong-type"]:
        output = work / f"d1-{provider}.wasm"
        result = subprocess.run([
            str(tool), "compose", str(emitted),
            "--dep", f"weft:source={root / 'examples/instances' / (provider + '.wasm')}",
            "--dep", f"weft:consumer={root / 'examples/instances/consumer.wasm'}",
            "-o", str(output),
        ], text=True, encoding="utf-8", capture_output=True, timeout=30)
        if provider in {"source", "alternate"}:
            assert result.returncode == 0, result.stderr
            assert output.read_bytes()[:8] == bytes.fromhex("0061736d0d000100")
        else:
            assert result.returncode != 0 and not output.exists(), provider
            assert ("twice" if provider == "missing" else "value") in result.stderr, result.stderr
        print(f"OK: D1 emitted WAC case {provider}")
    function_wac = work / "d1-function.wac"
    subprocess.run([
        "moon", "run", "src/compose_cli", "--target", "js", "--", "emit-wac",
        str(root / "examples/instances/function.json"), "--out", str(function_wac),
    ], cwd=root, check=True, timeout=120)
    result = subprocess.run([
        str(tool), "compose", str(function_wac),
        "--dep", f"weft:source={root / 'examples/instances/source.wasm'}",
        "--dep", f"weft:consumer={root / 'examples/instances/function-consumer.wasm'}",
        "-o", str(work / "d1-function.wasm"),
    ], text=True, encoding="utf-8", capture_output=True, timeout=30)
    assert result.returncode == 0, result.stderr
    print("OK: D1 emitted WAC explicit function-member access")
