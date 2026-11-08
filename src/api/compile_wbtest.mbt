///|
fn wasm(wat : String) -> Bytes raise {
  @text.parse_component_wat(wat)
}

///|
fn failure(text : String, binaries : Map[String, Bytes]) -> Diagnostic raise {
  match compile(text, binaries) {
    Err(d) => d
    Ok(_) => fail("expected a diagnostic")
  }
}

///|
fn source_wat(ty : String) -> String {
  "(component (core module $m (func (export \"f\") (param i32) (result i32) i32.const 0)) (core instance $i (instantiate $m)) (func (export \"out\") (param \"x\" \{ty}) (result u32) (canon lift (core func $i \"f\"))))"
}

///|
fn pair_text() -> String {
  "{\"components\":[{\"name\":\"source\",\"path\":\"unreadable/source\"},{\"name\":\"sink\",\"path\":\"unreadable/sink\"}],\"wires\":[{\"from\":\"source.out\",\"to\":\"sink.in\"}]}"
}

///|
fn pair_bytes(ty : String) -> Map[String, Bytes] raise {
  Map([
    ("source", wasm(source_wat(ty))),
    (
      "sink",
      wasm("(component (import \"in\" (func (param \"x\" u32) (result u32))))"),
    ),
  ])
}

///|
test "API: memory bytes override paths and extra entries are ignored" {
  let bins = pair_bytes("u32")
  bins.set("irrelevant", Bytes::new(0))
  let output = match compile(pair_text(), bins) {
    Ok(x) => x
    Err(d) => fail(d.message)
  }
  assert_eq(output.plan.plan_version, "0.2.0")
  assert_eq(output.plan.instances[0].path, "unreadable/source")
  assert_eq(output.json, @plan.plan_json(output.plan))
  assert_eq(bins.length(), 3)
}

///|
test "API: manifest fields and versions retain structured locations" {
  let d = failure(
    "{\"components\":[],\"resources\":{\"quota\":2147483648}}",
    Map([]),
  )
  assert_eq(d.code, "MANIFEST_NUMBER_RANGE")
  assert_eq(d.stage, "manifest")
  assert_eq(d.location.field, Some("manifest.resources.quota"))
  let d = failure("{\"version\":\"next\",\"components\":[]}", Map([]))
  assert_eq(d.code, "MANIFEST_VERSION")
  assert_eq(d.location.field, Some("manifest.version"))
}

///|
test "API: missing binaries are selected by exact component name in stable order" {
  let text = "{\"components\":[{\"name\":\"z\",\"path\":\"same\"},{\"name\":\"alpha\",\"path\":\"same\"}]}"
  let d = failure(text, Map([("same", wasm("(component)"))]))
  assert_eq(d.code, "INPUT_MISSING_BINARY")
  assert_eq(d.location.component, Some("alpha"))
  assert_eq(d.detail, Some("same"))
}

///|
test "API: invalid bytes retain decode stage and component" {
  let bins = pair_bytes("u32")
  bins.set("source", [0xff])
  let d = failure(pair_text(), bins)
  assert_eq(d.code, "COMPONENT_DECODE")
  assert_eq(d.stage, "decode")
  assert_eq(d.location.component, Some("source"))
  assert_true(d.detail is Some(_))
}

///|
test "API: type mismatches retain both endpoints and nested detail" {
  let d = failure(pair_text(), pair_bytes("bool"))
  assert_eq(d.code, "PLAN_TYPE_MISMATCH")
  assert_eq(d.location.component, Some("source"))
  assert_eq(d.location.port, Some("out"))
  assert_eq(d.related[0].component, Some("sink"))
  assert_eq(d.related[0].port, Some("in"))
  assert_eq(d.detail, Some("parameter 0: bool vs u32"))
}

///|
test "API: unbound imports and unsupported values are machine-readable" {
  let text = "{\"components\":[{\"name\":\"sink\",\"path\":\"x\"}]}"
  let d = failure(text, pair_bytes("u32"))
  assert_eq(d.code, "PLAN_UNBOUND_IMPORT")
  assert_eq(d.location.port, Some("in"))
  let bins = pair_bytes("u32")
  bins.set(
    "sink",
    wasm(
      "(component (type $t (func async (param \"x\" u32) (result u32))) (import \"in\" (func (type $t))))",
    ),
  )
  let d = failure(pair_text(), bins)
  assert_eq(d.code, "PLAN_UNSUPPORTED")
  assert_eq(d.location.component, Some("sink"))
}

///|
test "API: cycles carry related components without parsing a message" {
  let text = "{\"components\":[{\"name\":\"a\",\"path\":\"x\"}],\"wires\":[{\"from\":\"a.out\",\"to\":\"a.in\"}]}"
  let d = failure(text, Map([("a", wasm("(component)"))]))
  assert_eq(d.code, "PLAN_CYCLE")
  assert_eq(d.related[0].component, Some("a"))
}
