///|
fn source(delta : Int32) -> Bytes raise {
  @text.parse_component_wat(
    (
      $|(component
      $| (core module $m
      $|  (func (export "inc") (param i32) (result i32)
      $|   local.get 0 i32.const \{delta} i32.add))
      $| (core instance $i (instantiate $m))
      $| (func (export "inc") (param "x" u32) (result u32)
      $|  (canon lift (core func $i "inc"))))
    ),
  )
}

///|
fn consumer() -> Bytes raise {
  @text.parse_component_wat(
    (
      #|(component
      #| (import "inc" (func $inc (param "x" u32) (result u32)))
      #| (core func $lower (canon lower (func $inc)))
      #| (core module $m
      #|  (import "env" "inc" (func $inc (param i32) (result i32)))
      #|  (func (export "run") (param i32) (result i32)
      #|   local.get 0 call $inc i32.const 2 i32.mul))
      #| (core instance $i (instantiate $m
      #|  (with "env" (instance (export "inc" (func $lower))))))
      #| (func (export "run") (param "x" u32) (result u32)
      #|  (canon lift (core func $i "run"))))
    ),
  )
}

///|
fn manifest(wires : String) -> String {
  "{\"components\":[{\"name\":\"source\",\"path\":\"same.wasm\"},{\"name\":\"consumer\",\"path\":\"same.wasm\"}],\"wires\":" +
  wires +
  "}"
}

///|
fn inputs(delta : Int32) -> Map[String, Bytes] raise {
  Map([("source", source(delta)), ("consumer", consumer())])
}

///|
let wires = "[{\"from\":\"source.inc\",\"to\":\"consumer.inc\"}]"

///|
test "executor compiles manifest then performs real wiring and explicit calls" {
  let m = manifest(wires)
  inspect(
    execute(m, inputs(1), "consumer", "run", [@linker.U32(41)]),
    content="84",
  )
  inspect(
    execute(m, inputs(2), "consumer", "run", [@linker.U32(41)]),
    content="86",
  )
  inspect(
    execute(m, inputs(1), "source", "inc", [@linker.U32(41)]),
    content="42",
  )
}

///|
test "executor rejects disconnected manifests and invalid call targets" {
  for
    (m, target, port, args) in [
      (manifest("[]"), "consumer", "run", [@linker.U32(41)]),
      (manifest(wires), "absent", "run", [@linker.U32(41)]),
      (manifest(wires), "consumer", "absent", [@linker.U32(41)]),
      (manifest(wires), "consumer", "run", []),
      (manifest(wires), "consumer", "run", [@linker.Bool(true)]),
    ] {
    try execute(m, inputs(1), target, port, args) catch {
      _ => ()
    } noraise {
      _ => fail("invalid execution succeeded")
    }
  }
}

///|
test "argument parsing rejects invalid bool and multi-scalar chars" {
  for (kind, text) in [("bool", "yes"), ("char", "ab"), ("char", "")] {
    try parse_arg(kind, text) catch {
      _ => ()
    } noraise {
      _ => fail("invalid argument accepted")
    }
  }
  assert_true(parse_arg("bool", "false") is @linker.Bool(false))
  assert_true(parse_arg("char", "😀") is @linker.Char('😀'))
}

///|
test "unsigned values retain full width during parse and render" {
  inspect(show_value(parse_arg("u32", "4294967295")), content="4294967295")
  inspect(
    show_value(parse_arg("u64", "18446744073709551615")),
    content="18446744073709551615",
  )
}

///|
test "executor rejects requested limits before execution" {
  let m = "{\"resources\":{\"quota\":1}," + manifest(wires).substring(start=1)
  try execute(m, inputs(1), "consumer", "run", [@linker.U32(41)]) catch {
    error => assert_true(error.to_string().contains("resource limits"))
  } noraise {
    _ => fail("unsupported quota accepted")
  }
}
