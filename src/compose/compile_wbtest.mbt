///|
fn manifest() -> String {
  "{\"manifest_version\":\"0.3.0\",\"profile\":\"instance-sync-v1\",\"components\":[{\"name\":\"source\",\"path\":\"source.wasm\"},{\"name\":\"consumer\",\"path\":\"consumer.wasm\"}],\"bindings\":[{\"kind\":\"instance\",\"from\":{\"component\":\"source\",\"port\":\"ops\"},\"to\":{\"component\":\"consumer\",\"port\":\"ops\"}}]}"
}

///|
fn bins(mode : String) -> Map[String, Bytes] raise {
  Map([("source", @fixture.provider(mode)), ("consumer", @fixture.consumer())])
}

///|
test "D1 pure compile emits an explicit new profile without changing old format" {
  let result = compile(manifest(), bins("source"))
  guard result is Ok(out) else { fail("composition compile failed") }
  assert_eq(out.plan.order, ["source", "consumer"])
  let parsed = @json.parse(out.json)
  guard parsed is @json.Object(fields) else { fail("plan is not an object") }
  assert_true(fields.get("plan_version") is Some(@json.String("0.3.0")))
  assert_true(fields.get("profile") is Some(@json.String("instance-sync-v1")))
  assert_true(!out.json.contains("plan_hash")) // D2 content binding is not implemented.
  guard emit_wac(manifest(), bins("source")) is Ok(wac) else { fail("WAC failed") }
  assert_true(wac.contains("c-source[\"ops\"]"))
}

///|
test "D1 strict parser rejects old implicit unknown and duplicate-key inputs" {
  for (source, code) in [
    ("{\"components\":[],\"wires\":[]}", "UNKNOWN_FIELD"),
    ("{\"manifest_version\":\"0.2.0\",\"profile\":\"instance-sync-v1\",\"components\":[],\"bindings\":[]}", "UNSUPPORTED_MANIFEST_VERSION"),
    ("{\"manifest_version\":\"0.3.0\",\"profile\":\"other\",\"components\":[],\"bindings\":[]}", "UNSUPPORTED_PROFILE"),
    ("{\"manifest_version\":\"0.3.0\",\"manifest_version\":\"0.3.0\"}", "INVALID_JSON"),
    ("{\"manifest_version\":\"0.3.0\",\"profile\":\"instance-sync-v1\",\"components\":[],\"bindings\":[],\"resources\":{}}", "UNKNOWN_FIELD"),
  ] {
    guard compile(source, Map([])) is Err(d) else { fail("invalid input succeeded") }
    assert_eq(d.code, code)
  }
}

///|
test "D1 inputs require exact component byte IDs and preserve semantic error paths" {
  guard compile(manifest(), Map([])) is Err(missing) else { fail("missing bytes succeeded") }
  assert_eq(missing.code, "MISSING_BINARY")
  let extra = bins("source")
  extra.set("undeclared", b"ignored?")
  guard compile(manifest(), extra) is Err(d) else { fail("extra binary succeeded") }
  assert_eq(d.code, "UNEXPECTED_BINARY")
  for (mode, code) in [("missing", "MISSING_MEMBER"), ("wrong-type", "TYPE_MISMATCH")] {
    guard compile(manifest(), bins(mode)) is Err(d) else { fail("bad binding compiled") }
    assert_eq(d.code, code)
    assert_eq(d.component, "consumer")
    assert_true(d.path.contains("ops"))
  }
}

///|
test "D1 canonical output is unchanged by declaration and binary-map order" {
  let source = manifest()
  let map = bins("source")
  let (m, cs) = prepare(source, map)
  let p = @plan.plan(cs, m.bindings)
  let reversed = Array::makei(m.components.length(), i => m.components[m.components.length() - i - 1])
  assert_eq(encode({ ..m, components: reversed }, p), encode(m, p))
  guard compile(source, map) is Ok(first) else { fail("first compile") }
  let reverse_map = Map([("consumer", map.get("consumer").unwrap()), ("source", map.get("source").unwrap())])
  guard compile(source, reverse_map) is Ok(second) else { fail("second compile") }
  assert_eq(first.json, second.json)
}
