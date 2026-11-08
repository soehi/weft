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
test "E1 actual native cross-instance import: 41 -> +1 -> x2 = 84" {
  let linker = @linker.ComponentLinker::with_core_execution_engine(
    @native.open_native_component_session(),
  )
  defer linker.close()
  let src = linker.instantiate("source", linker.validate_input(source(1)))
  let exported = src.get_export("inc").unwrap()
  linker.add_import("inc", exported)
  let dst = linker.instantiate("consumer", linker.validate_input(consumer()))
  assert_true(dst.call_exported_func("run", [@linker.U32(41)]) is [U32(84)])
}

///|
test "E1 disconnecting the wire fails consumer instantiation" {
  let linker = @linker.ComponentLinker::with_core_execution_engine(
    @native.open_native_component_session(),
  )
  defer linker.close()
  let _ = linker.instantiate("source", linker.validate_input(source(1)))
  let validated = linker.validate_input(consumer())
  try linker.instantiate("consumer", validated) catch {
    error => assert_true(error.to_string().contains("inc"))
  } noraise {
    _ => fail("unbound import unexpectedly instantiated")
  }
}

///|
test "E1 rewiring to another live source changes result to 86" {
  let linker = @linker.ComponentLinker::with_core_execution_engine(
    @native.open_native_component_session(),
  )
  defer linker.close()
  let original = linker.instantiate(
    "original",
    linker.validate_input(source(1)),
  )
  let alternate = linker.instantiate(
    "alternate",
    linker.validate_input(source(2)),
  )
  assert_true(
    original.call_exported_func("inc", [@linker.U32(41)]) is [U32(42)],
  )
  linker.add_import("inc", alternate.get_export("inc").unwrap())
  let dst = linker.instantiate("consumer", linker.validate_input(consumer()))
  assert_true(dst.call_exported_func("run", [@linker.U32(41)]) is [U32(86)])
}
