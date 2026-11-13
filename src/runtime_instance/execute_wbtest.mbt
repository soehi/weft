///|
fn manifest(bindings : String) -> String {
  "{\"manifest_version\":\"0.3.0\",\"profile\":\"instance-sync-v1\",\"components\":[{\"name\":\"consumer\",\"path\":\"consumer.wasm\"},{\"name\":\"source\",\"path\":\"source.wasm\"}],\"bindings\":" + bindings + "}"
}

///|
let whole = "[{\"kind\":\"instance\",\"from\":{\"component\":\"source\",\"port\":\"ops\"},\"to\":{\"component\":\"consumer\",\"port\":\"ops\"}}]"

///|
fn bins(mode : String) -> Map[String, Bytes] raise {
  Map([("source", @fixture.provider(mode)), ("consumer", @fixture.consumer())])
}

///|
test "D1 checked operation sequence executes both guest functions and rewires provider" {
  assert_eq(execute(manifest(whole), bins("source"), "consumer", "run", 41U), 84U)
  assert_eq(execute(manifest(whole), bins("alternate"), "consumer", "run", 41U), 102U)
  assert_eq(execute(manifest(whole), bins("source"), "consumer", "run", 0U), 2U)
}

///|
test "D1 static member errors reject before entering the runtime" {
  for (mode, code) in [("missing", "MISSING_MEMBER"), ("wrong-type", "TYPE_MISMATCH")] {
    try execute(manifest(whole), bins(mode), "consumer", "run", 41U) catch {
      Invalid(message) => assert_true(message.contains(code) && message.contains("consumer"))
      _ => fail("expected static input rejection")
    } noraise { _ => fail("invalid binding executed") }
  }
}

///|
test "D1 unbound import fails before a trapping source can instantiate" {
  let trap = @text.parse_component_wat(
    "(component (core module $m (func $start unreachable) (start $start)) (core instance $i (instantiate $m)))",
  )
  let binaries = bins("source")
  binaries.set("source", trap)
  try execute(manifest("[]"), binaries, "consumer", "run", 41U) catch {
    Invalid(message) => assert_true(message.contains("UNBOUND_IMPORT"))
    _ => fail("trapping source instantiated before static validation")
  } noraise { _ => fail("unbound input executed") }
}

///|
test "D1 invalid explicit call target is rejected before instantiation" {
  try execute(manifest(whole), bins("source"), "unknown", "run", 41U) catch {
    Invalid(message) => assert_true(message.contains("call component"))
    _ => fail("expected explicit call error")
  } noraise { _ => fail("unknown call target executed") }
}

///|
test "D1 explicit function member bindings still execute via the same operation sequence" {
  let binding = "[{\"kind\":\"function\",\"from\":{\"component\":\"source\",\"port\":\"ops\",\"member\":\"inc\"},\"to\":{\"component\":\"consumer\",\"port\":\"inc\"}}]"
  let binaries = bins("source")
  binaries.set("consumer", @fixture.function_consumer())
  let result = execute(manifest(binding), binaries, "consumer", "run", 41U) catch {
    Invalid(message) => fail("input: " + message)
    Runtime(message) => fail("runtime: " + message)
  }
  assert_eq(result, 42U)
}

///|
test "D1 all root validation completes before a provider's trapping initializer can run" {
  let binding = "[{\"kind\":\"function\",\"from\":{\"component\":\"source\",\"port\":\"ops\",\"member\":\"inc\"},\"to\":{\"component\":\"consumer\",\"port\":\"inc\"}}]"
  let binaries = Map([
    ("source", @fixture.provider("trap-start")),
    ("consumer", @fixture.forwarded_import()),
  ])
  try execute(manifest(binding), binaries, "consumer", "run", 41U) catch {
    Invalid(message) => assert_true(message.contains("consumer") && message.contains("ExportedImportedFunc"))
    _ => fail("provider initialized before all root inputs were validated")
  } noraise { _ => fail("unsupported root export executed") }
}
