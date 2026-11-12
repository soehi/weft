"""Validate schema syntax, versioned examples and independently recompute hashes."""
import json
from pathlib import Path
from jsonschema import Draft202012Validator
ROOT = Path(__file__).resolve().parents[1]

def read(path):
    return json.loads((ROOT / path).read_text(encoding="utf-8"))

schemas = {}
for path in sorted((ROOT / "schemas").glob("*.schema.json")):
    schema = json.loads(path.read_text(encoding="utf-8"))
    Draft202012Validator.check_schema(schema)
    schemas[path.name] = Draft202012Validator(schema)
for name in ["chain", "format"]:
    schemas["manifest-v0.2.0.schema.json"].validate(read(f"examples/{name}.json"))
for name, version in [("plan-v0.1.0", "0.1.0"), ("plan-v0.2.0", "0.2.0"), ("format-plan-v0.2.0", "0.2.0")]:
    raw = (ROOT / f"docs/fixtures/{name}.json").read_bytes()
    value = json.loads(raw)
    schemas[f"plan-v{version}.schema.json"].validate(value)
    assert not raw.startswith(bytes([239, 187, 191])) and raw.endswith(b"}")
    body = raw.rsplit(b',"plan_hash":', 1)[0] + b"}"
    result = 0xcbf29ce484222325
    for byte in body:
        result = ((result ^ byte) * 0x100000001b3) & 0xffffffffffffffff
    assert value["plan_hash"] == f"{result:016x}", name
schemas["manifest-instance-v0.3.0.schema.json"].validate(read("examples/instances/chain.json"))
schemas["plan-instance-v0.3.0.schema.json"].validate(read("docs/fixtures/plan-instance-v0.3.0.json"))
print("OK: schemas, versioned instance/function artifacts and independent legacy UTF-8 FNV hashes")
