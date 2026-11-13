"""Actual Linux D1 command: whole instance calls and static rejection."""
import copy
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

assert sys.platform == "linux", "instance execution is only verified on Linux"
root = Path(__file__).resolve().parents[1]
subprocess.run(["moon", "build", "src/runtime_instance", "--target", "native"], cwd=root, check=True)
binary = root / "_build/native/debug/build/runtime_instance/runtime_instance.exe"
base = json.loads((root / "examples/instances/chain.json").read_text(encoding="utf-8"))
checks = 0
with tempfile.TemporaryDirectory(prefix="instance run 空格 ", dir=root / "_build") as directory:
    work = Path(directory)
    foreign = work / "foreign cwd"
    foreign.mkdir()
    for name in ["source", "consumer", "alternate", "missing", "wrong-type", "function-consumer"]:
        shutil.copyfile(root / f"examples/instances/{name}.wasm", work / f"{name}.wasm")
    manifest = work / "input.json"
    flags = ["--component", "consumer", "--export", "run", "--arg", "u32:41"]

    def run(value, status=0, expected="", args=None):
        global checks
        manifest.write_text(json.dumps(value), encoding="utf-8")
        result = subprocess.run([str(binary), "run", str(manifest)] + (flags if args is None else args), cwd=foreign, text=True, encoding="utf-8", capture_output=True, timeout=30)
        assert result.returncode == status, (result.returncode, result.stdout, result.stderr)
        if status == 0:
            assert result.stdout.strip() == expected, result.stdout
        elif expected:
            assert expected in result.stdout, result.stdout
        checks += 1

    run(base, expected="84")
    run(base, expected="2", args=flags[:-1]+["u32:0"])
    run(base, expected="0", args=flags[:-1]+["u32:4294967295"])
    alternate = copy.deepcopy(base)
    alternate["components"][1]["path"] = "alternate.wasm"
    run(alternate, expected="102")
    function_input = json.loads((root / "examples/instances/function.json").read_text(encoding="utf-8"))
    run(function_input, expected="42")
    for name, code, member in [("missing", "MISSING_MEMBER", "twice"), ("wrong-type", "TYPE_MISMATCH", "inc")]:
        value = copy.deepcopy(base)
        value["components"][1]["path"] = name + ".wasm"
        run(value, 1, code)
        run(value, 1, member)
    unbound = copy.deepcopy(base)
    unbound["bindings"] = []
    run(unbound, 1, "UNBOUND_IMPORT")
    duplicate = copy.deepcopy(base)
    duplicate["bindings"].append(duplicate["bindings"][0])
    run(duplicate, 1, "DUPLICATE_BINDING")
    resource = copy.deepcopy(base)
    resource["resources"] = {"quota": 1}
    run(resource, 1, "UNKNOWN_FIELD")
    run(base, 1, "call component", args=["--component", "absent"]+flags[2:])
    run(base, 1, "exported function", args=flags[:3]+["absent"]+flags[4:])
    for value in ["u32:4294967296", "u32:-1", "u32:1.5", "u32:", "bool:true"]:
        run(base, 1, args=flags[:-1]+[value])
    run(base, 1, args=flags+flags[:2])
    run(base, 1, args=["--bogus", "x"]+flags[2:])
    run(base, 1, args=flags[:-2]+["--component", "consumer"])
print(f"OK: {checks} native instance CLI checks, guest results, static failures and explicit u32 call limits")
