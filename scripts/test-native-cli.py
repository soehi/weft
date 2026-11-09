"""Exercise the actual experimental native command on Linux, including exit codes."""
import copy
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BINARY = ROOT / "_build/native/debug/build/runtime_native/runtime_native.exe"

def main():
    count = 0
    with tempfile.TemporaryDirectory(prefix="weft native spaces ", dir=ROOT / "_build") as directory:
        work = Path(directory)
        fixtures = work / "input files"
        fixtures.mkdir()
        subprocess.run(["moon", "run", "src/tools/make_execution_fixtures", "--target", "native", "--", str(fixtures)], cwd=ROOT, check=True)
        manifest = {"components": [{"name":"source", "path":"source.wasm"}, {"name":"consumer", "path":"consumer.wasm"}], "wires":[{"from":"source.inc", "to":"consumer.inc"}]}
        file = fixtures / "chain.json"
        def write(value):
            file.write_text(json.dumps(value), encoding="utf-8")
        def cli(args, expected=None, error=None):
            nonlocal count
            result = subprocess.run([str(BINARY), *args], cwd=work, capture_output=True, text=True, timeout=30)
            assert result.returncode == (0 if error is None else 1), (args, result.returncode, result.stdout, result.stderr)
            if expected is not None: assert result.stdout.strip() == expected, result.stdout
            if error is not None: assert error in result.stdout, result.stdout
            count += 1
        base = ["run", str(file.relative_to(work)), "--component", "consumer", "--export", "run"]
        write(manifest)
        cli(base + ["--arg", "u32:41"], "84")
        absolute = copy.deepcopy(manifest)
        for c in absolute["components"]: c["path"] = str(fixtures / c["path"])
        write(absolute)
        cli(base + ["--arg", "u32:41"], "84")
        alternate = copy.deepcopy(manifest)
        alternate["components"][0]["path"] = "alternate.wasm"
        write(alternate)
        cli(base + ["--arg", "u32:41"], "86")
        write(manifest)
        cli(["run", str(file), "--component", "source", "--export", "inc", "--arg", "u32:41"], "42")
        cli(["--help"])
        for args in [[], ["plan", str(file)], ["run", str(file)], base + ["--export", "run"], base + ["--component", "source"], base + ["--unknown", "x"], base + ["extra"], base + ["--arg"], base + ["--arg", "41"], base + ["--arg", "bool:yes"], base + ["--arg", "char:ab"], base + ["--arg", "u32:-1"], base + ["--arg", "u32:4294967296"]]:
            cli(args, error="error:")
        cli(base, error="error:")  # argument arity
        cli(base + ["--arg", "bool:true"], error="error:")  # type mismatch
        cli(["run", str(file), "--component", "absent", "--export", "run"], error="error:")
        cli(["run", str(file), "--component", "consumer", "--export", "absent", "--arg", "u32:41"], error="error:")
        disconnected = copy.deepcopy(manifest)
        disconnected["wires"] = []
        write(disconnected)
        cli(base + ["--arg", "u32:41"], error="error:")
        for key in ["quota", "max_memory_pages"]:
            limited = {**manifest, "resources":{key:1}}
            write(limited)
            cli(base + ["--arg", "u32:41"], error="resource limits")
        write({"components":[{"name":"consumer", "path":"trap.wasm"}], "wires":[]})
        cli(base, error="error:")
        write({"components":[{"name":"consumer", "path":"absent.wasm"}], "wires":[]})
        cli(base, error="cannot read consumer")
        file.write_bytes(b"\xff")
        cli(base, error="error:")
        file.write_text("{", encoding="utf-8")
        cli(base, error="error:")
        cli(["run", "absent.json", "--component", "consumer", "--export", "run"], error="error:")
    print(f"OK: {count} native CLI checks, actual results, manifest-relative paths and exit code 1 on failures")

if __name__ == "__main__":
    main()
