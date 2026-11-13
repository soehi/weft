"""Bounded D3 binary/WAC differential and independent deployment reference.

Replay: python scripts/test-composition-differential.py --seed 7
On disagreement retain seed, WAT, bytes, manifests, WAC and tool diagnostics.
"""
import argparse
import copy
import hashlib
import itertools
import json
import platform
import shutil
import subprocess
import tempfile
import time
import os
from pathlib import Path

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--seed", type=int, choices=range(27))
args = parser.parse_args()
started = time.monotonic()
tool_lock = json.loads((root / "release/external-tools.lock.json").read_text(encoding="utf-8"))["wac"]
system = "windows" if platform.system() == "Windows" else "linux"
wac = root / "_build/external" / ("wac.exe" if system == "windows" else "wac")
assert hashlib.sha256(wac.read_bytes()).hexdigest() == tool_lock["assets"][f"{system}-x86_64"]["sha256"]

def compact(value): return json.dumps(value, ensure_ascii=False, separators=(",", ":"))
def sha(value): return hashlib.sha256(value).hexdigest()
def domain_hash(domain, value): return sha((domain + "\n" + compact(value)).encode("utf-8"))

def signature(tag, members=()):
    return domain_hash("weft:type-signature:instance-sync-v1:v1", {"tag": tag, "members": [{"label": label, "digest": digest} for label, digest in members]})

def value_signature(seed):
    scalar = signature("scalar:u32")
    boolean = signature("scalar:bool")
    return [
        scalar,
        signature("list", [("element", scalar)]),
        signature("option", [("some", scalar)]),
        signature("record", [("field:value", scalar), ("field:ready", boolean)]),
        signature("tuple", [("tuple:0", scalar), ("tuple:1", boolean), ("tuple:2", signature("scalar:string"))]),
        signature("flags", [("read", None), ("write", None)]),
        signature("enum", [("ready", None), ("waiting", None)]),
        signature("variant", [("case:some", scalar), ("case:empty", None)]),
        signature("result", [("ok", scalar), ("err", boolean)]),
    ][seed % 9]

def reference_order(manifest):
    # Exhaustively enumerate bounded permutations; independent of graph/Kahn.
    for order in itertools.permutations(sorted(c["name"] for c in manifest["components"])):
        position = {name: i for i, name in enumerate(order)}
        if all(position[b["from"]["component"]] < position[b["to"]["component"]] for b in manifest["bindings"]): return list(order)
    raise ValueError("cycle")

def reference_verify(plan, lock, binaries, manifest, seed):
    """Independent bounded oracle for this generated type-only common subset.

    Signature facts come from the generator's declared type grammar, never a
    production type/shape/verify helper. Bytes are independently bound to lock.
    """
    try:
        assert set(plan) == {"plan_version", "profile", "planner_version", "lock_digest", "instances", "bindings", "operations", "plan_digest"}
        assert plan["plan_version"] == "0.4.0" and plan["profile"] == "instance-sync-v1" and plan["planner_version"] == "instance-planner-v1"
        def tagged(value, expected): assert value == {"algorithm": "sha256", "value": expected}
        tagged(plan["lock_digest"], domain_hash("weft:input-lock:v1", lock))
        tagged(plan["plan_digest"], domain_hash("weft:deployment-plan:v1", {k: v for k, v in plan.items() if k != "plan_digest"}))
        artifacts = {a["id"]: a for a in lock["artifacts"]}
        assert len(artifacts) == len(lock["artifacts"]) and set(artifacts) == set(binaries)
        instances = plan["instances"]
        assert len(instances) == len(artifacts) and {i["id"] for i in instances} == set(artifacts)
        for i, instance in enumerate(instances):
            assert set(instance) == {"id", "algorithm", "digest", "length", "order", "imports"}
            artifact = artifacts[instance["id"]]
            assert {k: instance[k] for k in ["id", "algorithm", "digest", "length"]} == artifact
            assert artifact["algorithm"] == "sha256" and artifact["length"] == len(binaries[artifact["id"]]) and artifact["digest"] == sha(binaries[artifact["id"]])
            assert instance["order"] == i
        bindings = plan["bindings"]
        bare = [{k: b[k] for k in ["kind", "from", "to"]} for b in bindings]
        assert sorted(map(compact, bare)) == sorted(map(compact, lock["bindings"]))
        assert sorted(map(compact, bare)) == sorted(map(compact, manifest["bindings"]))
        positions = {instance["id"]: i for i, instance in enumerate(instances)}
        targets = []
        expected_signature = signature("instance", [("type:value", value_signature(seed))])
        for b in bindings:
            assert set(b) == {"kind", "from", "to", "from_signature", "to_signature"}
            assert b["kind"] == "instance" and b["from"]["port"] == "ops"
            assert set(b["from"]) == set(b["to"]) == {"component", "port"}
            assert b["from_signature"] == b["to_signature"] == expected_signature
            assert positions[b["from"]["component"]] < positions[b["to"]["component"]]
            targets.append((b["to"]["component"], b["to"]["port"]))
        assert len(set(targets)) == len(targets)
        cursor = 0
        for instance in instances:
            expected = {i for i, b in enumerate(bindings) if b["to"]["component"] == instance["id"]}
            assert all(type(i) is int and i >= 0 for i in instance["imports"])
            assert len(instance["imports"]) == len(expected) and set(instance["imports"]) == expected
            installs = plan["operations"][cursor:cursor + len(expected)]
            assert all(set(op) == {"op", "binding"} and op["op"] == "install-import" and type(op["binding"]) is int for op in installs)
            assert len(installs) == len(expected) and {op["binding"] for op in installs} == expected
            cursor += len(expected)
            assert plan["operations"][cursor] == {"op": "instantiate", "component": instance["id"]}
            cursor += 1
        assert cursor == len(plan["operations"])
        return True
    except (AssertionError, KeyError, IndexError, TypeError): return False

def direct_wac(manifest):
    lines = ["package d3:reference;", ""]
    for name in reference_order(manifest):
        imports = [json.dumps(b["to"]["port"]) + ": c-" + b["from"]["component"] + "[" + json.dumps(b["from"]["port"]) + "]" for b in manifest["bindings"] if b["to"]["component"] == name]
        lines.append("let c-" + name + " = new weft:" + name + " { " + ", ".join(imports) + " };")
    for c in manifest["components"]: lines.append("export c-" + c["name"] + " as " + json.dumps(c["name"]) + ";")
    return "\n".join(lines) + "\n"

def run(command, cwd):
    env = dict(os.environ, NODE_OPTIONS="--max-old-space-size=256")
    result = subprocess.run(list(map(str, command)), cwd=cwd, capture_output=True, text=True, encoding="utf-8", timeout=30, env=env)
    return {"code": result.returncode, "stdout": result.stdout, "stderr": result.stderr}

def shrink_sinks(manifest, still_fails):
    """Greedy 1-minimal reduction under sink/isolated-node deletion.

    Removing only sinks preserves every surviving component's import closure.
    This is deliberately a small reducer, not a global minimum claim.
    """
    current = copy.deepcopy(manifest)
    while True:
        outgoing = {b["from"]["component"] for b in current["bindings"]}
        reduced = False
        for component in current["components"]:
            name = component["name"]
            if name in outgoing: continue
            candidate = copy.deepcopy(current)
            candidate["components"] = [c for c in candidate["components"] if c["name"] != name]
            candidate["bindings"] = [b for b in candidate["bindings"] if b["to"]["component"] != name]
            if still_fails(candidate): current = candidate; reduced = True; break
        if not reduced: return current

# Exercise the reducer even on a successful corpus: only a->c is necessary.
reducer_fixture = {"components": [{"name": n} for n in ["a", "b", "c"]], "bindings": [{"from": {"component": "a"}, "to": {"component": n}} for n in ["b", "c"]]}
reduced_fixture = shrink_sinks(reducer_fixture, lambda m: {"a", "c"}.issubset({c["name"] for c in m["components"]}))
assert [c["name"] for c in reduced_fixture["components"]] == ["a", "c"] and len(reduced_fixture["bindings"]) == 1

output_dir = root / "_build/d3"
output_dir.mkdir(exist_ok=True)
subprocess.run(["moon", "build", "src/compose_cli", "--target", "js"], cwd=root, check=True)
cli = ["node", root / "_build/js/debug/build/compose_cli/compose_cli.js"]
report = {"schema_version": 1, "seeds": [], "external_tool": tool_lock, "scope": "nine synchronous value-type constructors in type-only instances; 3-5 node DAGs", "mutations": 0, "valid_transformations": 0, "budgets": {"command_timeout_seconds": 30, "node_heap_mib": 256, "binary_graph_nodes_max": 5, "seeds_max": 27}}
with tempfile.TemporaryDirectory(prefix="corpus ", dir=output_dir) as directory:
    work = Path(directory)
    subprocess.run(["moon", "run", "src/tools/generate_composition_cases", "--target", "native", "--", str(work)], cwd=root, check=True, timeout=120)
    for seed in ([args.seed] if args.seed is not None else range(27)):
        manifest = json.loads((work / f"seed-{seed}.json").read_text(encoding="utf-8"))
        transcripts = []
        case = "valid"
        try:
            for case in ["valid", "wrong", "missing"]:
                value = copy.deepcopy(manifest)
                if case != "valid": value["components"][0]["path"] = f"seed-{seed}-{case}.wasm"
                input_file = work / "input.json"
                input_file.write_text(compact(value), encoding="utf-8")
                static = run(cli + ["plan", input_file], work)
                script = work / "reference.wac"
                script.write_text(direct_wac(value), encoding="utf-8")
                deps = [part for c in value["components"] for part in ["--dep", "weft:" + c["name"] + "=" + str(work / c["path"])]]
                (work / "composed.wasm").unlink(missing_ok=True)
                external = run([wac, "compose", script, *deps, "-o", work / "composed.wasm"], work)
                transcripts.append({"seed": seed, "case": case, "weft": static, "external": external})
                assert (static["code"] == 0) == (external["code"] == 0) == (case == "valid"), transcripts[-1]
                if case != "valid":
                    assert ("TYPE_MISMATCH" if case == "wrong" else "MISSING_MEMBER") in static["stdout"]
                    assert "value" in external["stderr"], external
                    assert not (work / "composed.wasm").exists(), external
                    continue
                emitted = work / "emitted.wac"
                emission = run(cli + ["emit-wac", input_file, "--out", emitted], work)
                assert emission["code"] == 0, emission
                (work / "emitted.wasm").unlink(missing_ok=True)
                accepted = run([wac, "compose", emitted, *deps, "-o", work / "emitted.wasm"], work)
                assert accepted["code"] == 0, accepted
                plan_file, lock_file = work / "sealed.json", work / "lock.json"
                sealed = run(cli + ["seal", input_file, "--out", plan_file, "--lock", lock_file], work)
                assert sealed["code"] == 0, sealed
                plan, lock = json.loads(plan_file.read_bytes()), json.loads(lock_file.read_bytes())
                binaries = {c["name"]: (work / c["path"]).read_bytes() for c in value["components"]}
                assert reference_verify(plan, lock, binaries, manifest, seed), "independent reference rejected generated plan"
                assert [i["id"] for i in plan["instances"]] == reference_order(value)
                reordered = copy.deepcopy(value)
                reordered["components"].reverse()
                reordered["bindings"].reverse()
                reordered_file = work / "reordered.json"
                reordered_file.write_text(compact(reordered), encoding="utf-8")
                reordered_plan, reordered_lock = work / "reordered-plan.json", work / "reordered-lock.json"
                result = run(cli + ["seal", reordered_file, "--out", reordered_plan, "--lock", reordered_lock], work)
                assert result["code"] == 0 and reordered_plan.read_bytes() == plan_file.read_bytes() and reordered_lock.read_bytes() == lock_file.read_bytes(), result
                report["valid_transformations"] += 1
                if len(plan["bindings"]) > 1:
                    permuted = copy.deepcopy(plan)
                    count = len(permuted["bindings"])
                    permuted["bindings"].reverse()
                    for instance in permuted["instances"]: instance["imports"] = [count - i - 1 for i in instance["imports"]]
                    for op in permuted["operations"]:
                        if op["op"] == "install-import": op["binding"] = count - op["binding"] - 1
                    permuted["plan_digest"]["value"] = domain_hash("weft:deployment-plan:v1", {k: v for k, v in permuted.items() if k != "plan_digest"})
                    assert reference_verify(permuted, lock, binaries, manifest, seed)
                    plan_file.write_text(compact(permuted), encoding="utf-8")
                    result = run(cli + ["verify", plan_file, "--lock", lock_file, "--inputs", input_file], work)
                    assert result["code"] == 2, result
                    report["valid_transformations"] += 1
                mutants = []
                def mutation(label, action):
                    changed = copy.deepcopy(plan); action(changed)
                    changed["plan_digest"]["value"] = domain_hash("weft:deployment-plan:v1", {k: v for k, v in changed.items() if k != "plan_digest"})
                    mutants.append((label, changed))
                mutation("profile", lambda p: p.update(profile="unknown"))
                mutation("version", lambda p: p.update(plan_version="0.3.0"))
                mutation("planner", lambda p: p.update(planner_version="unknown"))
                mutation("lock-digest", lambda p: p["lock_digest"].update(value="0" * 64))
                mutation("algorithm", lambda p: p["instances"][0].update(algorithm="md5"))
                mutation("binary-digest", lambda p: p["instances"][0].update(digest="0" * 64))
                mutation("binary-length", lambda p: p["instances"][0].update(length=0))
                mutation("instance-id", lambda p: p["instances"][0].update(id="unknown"))
                mutation("order-index", lambda p: p["instances"][0].update(order=99))
                mutation("instance-set", lambda p: p["instances"].pop())
                mutation("duplicate-instance", lambda p: p["instances"].append(p["instances"][0]))
                mutation("binding-kind", lambda p: p["bindings"][0].update(kind="function"))
                mutation("provider", lambda p: p["bindings"][0]["from"].update(component="unknown"))
                mutation("consumer-port", lambda p: p["bindings"][0]["to"].update(port="unknown"))
                mutation("signature", lambda p: p["bindings"][0].update(from_signature="0" * 64))
                mutation("delete-binding", lambda p: p["bindings"].pop())
                mutation("duplicate-binding", lambda p: p["bindings"].append(p["bindings"][0]))
                target = next(i for i, entry in enumerate(plan["instances"]) if entry["imports"])
                mutation("incoming", lambda p: p["instances"][target].update(imports=[]))
                mutation("negative-index", lambda p: p["instances"][target].update(imports=[-1]))
                mutation("operations", lambda p: p["operations"].reverse())
                mutation("missing-instantiate", lambda p: p["operations"].pop())
                for label, changed in mutants:
                    assert not reference_verify(changed, lock, binaries, manifest, seed), label
                    plan_file.write_text(compact(changed), encoding="utf-8")
                    result = run(cli + ["verify", plan_file, "--lock", lock_file, "--inputs", input_file], work)
                    assert result["code"] == 1, {"seed": seed, "mutation": label, "result": result}
                    report["mutations"] += 1
            report["seeds"].append({"seed": seed, "nodes": len(manifest["components"]), "edges": len(manifest["bindings"]), "cases": transcripts})
            print(f"OK: seed {seed}, three binary decisions, {len(mutants)} rejected plan mutations", flush=True)
        except Exception as error:
            failure = output_dir / f"failure-seed-{seed}-{case}"
            failure.mkdir(exist_ok=True)
            # Preserve the original disagreement before attempting reduction.
            for path in work.iterdir():
                if path.is_file(): shutil.copy2(path, failure / path.name)
            failure_record = {"seed": seed, "case": case, "tool": tool_lock, "transcripts": transcripts, "error": str(error)}
            (failure / "failure.json").write_text(json.dumps(failure_record, ensure_ascii=False, indent=2), encoding="utf-8")
            if transcripts and ((transcripts[-1]["weft"]["code"] == 0) != (transcripts[-1]["external"]["code"] == 0)):
                def disagreement(candidate):
                    input_file = work / "reduce.json"
                    input_file.write_text(compact(candidate), encoding="utf-8")
                    script = work / "reduce.wac"
                    script.write_text(direct_wac(candidate), encoding="utf-8")
                    deps = [part for c in candidate["components"] for part in ["--dep", "weft:" + c["name"] + "=" + str(work / c["path"])]]
                    static = run(cli + ["plan", input_file], work)
                    (work / "reduce.wasm").unlink(missing_ok=True)
                    external = run([wac, "compose", script, *deps, "-o", work / "reduce.wasm"], work)
                    return (static["code"] == 0) != (external["code"] == 0)
                try:
                    reduced = shrink_sinks(value, disagreement)
                    (failure / "reduced.json").write_text(compact(reduced), encoding="utf-8")
                    (failure / "reduced.wac").write_text(direct_wac(reduced), encoding="utf-8")
                except Exception as reduction_error:
                    failure_record["reduction_error"] = str(reduction_error)
                    (failure / "failure.json").write_text(json.dumps(failure_record, ensure_ascii=False, indent=2), encoding="utf-8")
            raise
report["elapsed_seconds"] = round(time.monotonic() - started, 3)
(output_dir / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"OK: {len(report['seeds'])} seeded binary DAGs, {len(report['seeds']) * 3} accept/reject cases, actual emitted WAC, {report['mutations']} rehashed mutations vs independent reference; {report['elapsed_seconds']}s")
