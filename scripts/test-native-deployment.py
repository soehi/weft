"""Linux actual reviewed deployment execution; hashes also recomputed in Python."""
import copy
import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

assert sys.platform == "linux"
root = Path(__file__).resolve().parents[1]
subprocess.run(["moon", "build", "src/runtime_instance", "--target", "native"], cwd=root, check=True)
subprocess.run(["moon", "build", "src/compose_cli", "--target", "js"], cwd=root, check=True)
runtime = root / "_build/native/debug/build/runtime_instance/runtime_instance.exe"
planner = root / "_build/js/debug/build/compose_cli/compose_cli.js"
checks = 0
with tempfile.TemporaryDirectory(prefix="locked run 空格 ", dir=root / "_build") as directory:
    work = Path(directory)
    foreign = work / "foreign"
    foreign.mkdir()
    for name in ["source", "consumer", "alternate", "function-consumer"]:
        shutil.copyfile(root / f"examples/instances/{name}.wasm", work / f"{name}.wasm")
    manifest, plan, lock = (work / name for name in ["input.json", "plan.json", "lock.json"])
    base = json.loads((root / "examples/instances/chain.json").read_text(encoding="utf-8"))

    def seal(value):
        manifest.write_text(json.dumps(value), encoding="utf-8")
        subprocess.run(["node", str(planner), "seal", str(manifest), "--out", str(plan), "--lock", str(lock)], cwd=foreign, check=True)

    def run(status=0, expected="84"):
        global checks
        result = subprocess.run([str(runtime), "run-locked", str(plan), "--lock", str(lock), "--inputs", str(manifest), "--component", "consumer", "--export", "run", "--arg", "u32:41"], cwd=foreign, text=True, encoding="utf-8", capture_output=True, timeout=30)
        assert result.returncode == status, (result.stdout, result.stderr)
        assert (result.stdout.strip() == expected) if status == 0 else (expected in result.stdout), result.stdout
        checks += 1

    seal(base)
    run()
    original_plan, original_lock = plan.read_bytes(), lock.read_bytes()
    changed = copy.deepcopy(base)
    changed["components"][1]["path"] = "alternate.wasm"
    manifest.write_text(json.dumps(changed), encoding="utf-8")
    run(1, "BINARY_DIGEST_MISMATCH")
    seal(changed)
    run(expected="102")
    lock.write_bytes(original_lock)
    run(1, "LOCK_DIGEST_MISMATCH")
    seal(base)
    canonical = json.loads(plan.read_bytes())
    for field, expected in [("signature", "TYPE_SIGNATURE_MISMATCH"), ("order", "INVALID_ORDER"), ("imports", "INVALID_INCOMING"), ("operations", "INVALID_OPERATIONS"), ("binding", "BINDING_INTENT_MISMATCH")]:
        value = copy.deepcopy(canonical)
        if field == "signature": value["bindings"][0]["from_signature"] = "0" * 64
        if field == "order":
            value["instances"].reverse()
            for i, instance in enumerate(value["instances"]): instance["order"] = i
        if field == "imports": value["instances"][1]["imports"] = []
        if field == "operations": value["operations"].reverse()
        if field == "binding": value["bindings"][0]["from"]["component"] = "consumer"
        value.pop("plan_digest")
        payload = json.dumps(value, separators=(",", ":"), ensure_ascii=False)
        value["plan_digest"] = {"algorithm": "sha256", "value": hashlib.sha256(("weft:deployment-plan:v1\n" + payload).encode("utf-8")).hexdigest()}
        plan.write_text(json.dumps(value), encoding="utf-8")
        run(1, expected)
    plan.write_bytes(b" " + original_plan)
    run()  # valid noncanonical plans are executable after semantic verification
    seal(json.loads((root / "examples/instances/function.json").read_text(encoding="utf-8")))
    run(expected="42")
    # D3 offline case keeps two compatible provider IDs in the reviewed set.
    # Rewiring is structurally valid but must not inherit the original review.
    reviewed = json.loads((root / "examples/instances/reviewed.json").read_text(encoding="utf-8"))
    seal(reviewed)
    run()
    changed_plan = json.loads(plan.read_bytes())
    changed_plan["bindings"][0]["from"]["component"] = "alternate"
    changed_plan.pop("plan_digest")
    payload = json.dumps(changed_plan, separators=(",", ":"), ensure_ascii=False)
    changed_plan["plan_digest"] = {"algorithm": "sha256", "value": hashlib.sha256(("weft:deployment-plan:v1\n" + payload).encode("utf-8")).hexdigest()}
    plan.write_text(json.dumps(changed_plan), encoding="utf-8")
    run(1, "BINDING_INTENT_MISMATCH")
    reviewed["bindings"][0]["from"]["component"] = "alternate"
    seal(reviewed)
    run(expected="102")
    shutil.copyfile(root / "examples/instances/missing.wasm", work / "missing.wasm")
    reviewed["components"][1]["path"] = "missing.wasm"
    manifest.write_text(json.dumps(reviewed), encoding="utf-8")
    previous_plan, previous_lock = plan.read_bytes(), lock.read_bytes()
    rejected = subprocess.run(["node", str(planner), "seal", str(manifest), "--out", str(plan), "--lock", str(lock)], cwd=foreign, text=True, encoding="utf-8", capture_output=True, timeout=30)
    assert rejected.returncode == 1 and "MISSING_MEMBER" in rejected.stdout and "twice" in rejected.stdout, rejected.stdout
    assert plan.read_bytes() == previous_plan and lock.read_bytes() == previous_lock
    checks += 1
print(f"OK: {checks} native locked deployment CLI checks, guest 84/102/42 and rehashed mutations rejected")
