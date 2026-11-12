///|
test "D0 whole instance import calls both source functions: 41 -> +1 -> x2" {
  let linker = @linker.ComponentLinker::with_core_execution_engine(
    @native.open_native_component_session(),
  )
  defer linker.close()
  let source = linker.instantiate(
    "source", linker.validate_input(@instance_fixture.provider("source")),
  )
  let ops = source.get_export("ops").unwrap()
  assert_true(ops is @linker.Instance(_))
  linker.add_import("ops", ops)
  let consumer = linker.instantiate(
    "consumer", linker.validate_input(@instance_fixture.consumer()),
  )
  for (input, expected) in [(0, 2), (7, 16), (41, 84)] {
    assert_true(
      consumer.call_exported_func("run", [@linker.U32(input)]) is [U32(value)] &&
      value == expected,
    )
  }
}

///|
test "D0 whole instance import rejects disconnected missing and wrong-type providers" {
  for mode in ["disconnected", "missing", "wrong-type"] {
    let linker = @linker.ComponentLinker::with_core_execution_engine(
      @native.open_native_component_session(),
    )
    defer linker.close()
    if mode != "disconnected" {
      // The provider is valid in isolation; only the consumer binding must fail.
      let source = linker.instantiate(
        "source", linker.validate_input(@instance_fixture.provider(mode)),
      )
      linker.add_import("ops", source.get_export("ops").unwrap())
    }
    let validated = linker.validate_input(@instance_fixture.consumer())
    try linker.instantiate("consumer", validated) catch {
      error => {
        let message = error.to_string()
        match mode {
          "disconnected" => assert_true(message.contains("ops"))
          "missing" => assert_true(message.contains("twice"))
          _ => assert_true(message.contains("value") || message.contains("inc"))
        }
      }
    } noraise {
      _ => fail("invalid instance binding instantiated: " + mode)
    }
  }
}

///|
test "D0 replacing the complete provider instance changes guest computation to 102" {
  let linker = @linker.ComponentLinker::with_core_execution_engine(
    @native.open_native_component_session(),
  )
  defer linker.close()
  let _ = linker.instantiate(
    "original", linker.validate_input(@instance_fixture.provider("source")),
  )
  let alternate = linker.instantiate(
    "alternate", linker.validate_input(@instance_fixture.provider("alternate")),
  )
  linker.add_import("ops", alternate.get_export("ops").unwrap())
  let consumer = linker.instantiate(
    "consumer", linker.validate_input(@instance_fixture.consumer()),
  )
  assert_true(consumer.call_exported_func("run", [@linker.U32(41)]) is [U32(102)])
}
