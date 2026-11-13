///|
test "D1 scope IR retains type exports instance members alias edges and binary scopes" {
  let c = decode("provider", @fixture.provider("source"))
  assert_eq(c.name, "provider")
  assert_true(c.scopes.length() > 0)
  assert_true(c.exports.any(e => e.name == "value-copy" && e.item is Type(_)))
  let mut ops = -1
  for e in c.exports {
    if e.name == "ops" && e.item is Instance(i) { ops = i }
  }
  assert_true(ops >= 0)
  guard c.types[ops].kind is Interface(_, _, es) else { fail("instance type lost") }
  assert_true(es.any(e => e.name == "value" && e.item is Type(_)))
  assert_true(es.any(e => e.name == "inc" && e.item is Function(_)))
  assert_true(es.any(e => e.name == "twice" && e.item is Function(_)))
  assert_true(c.types.any(n => n.kind is Alias(_)))
  for node in c.types {
    if node.kind is Alias(i) {
      assert_true(i >= 0 && i < c.types.length())
    }
  }
}

///|
test "D1 separately decoded components keep their own arena and instance imports" {
  let source = decode("source", @fixture.provider("source"))
  let consumer = decode("consumer", @fixture.consumer())
  assert_true(consumer.imports.any(e => e.name == "ops" && e.item is Instance(_)))
  assert_true(source.types.length() != consumer.types.length())
  let alias_count = source.types.filter(n => n.kind is Alias(_)).length()
  // Decoder outputs are independently owned; no cross-call mutable arena cache.
  source.types.clear()
  let again = decode("source", @fixture.provider("source"))
  assert_eq(again.types.filter(n => n.kind is Alias(_)).length(), alias_count)
}

///|
test "D1 decode errors identify the component without exposing verifier objects" {
  try decode("broken", b"not wasm") catch {
    InvalidComponent(name, detail) => {
      assert_eq(name, "broken")
      assert_true(detail.length() > 0)
    }
  } noraise { _ => fail("invalid component decoded") }
}

///|
test "D1 real named composite type aliases retain the consumer reference graph" {
  let bytes = @text.parse_component_wat(
    (
      #|(component
      #| (import "ops" (instance $ops
      #|  (type $payload (record (field "value" u32)))
      #|  (export "payload" (type $public (eq $payload)))
      #|  (type $maybe (option $public))
      #|  (export "maybe" (type $public-maybe (eq $maybe)))
      #|  (export "read" (func (param "x" $public-maybe) (result $public)))))
      #| (alias export $ops "payload" (type $copy))
      #| (export "copy" (type $copy)))
    ),
  )
  let c = decode("composite", bytes) catch {
    InvalidComponent(_, detail) => fail(detail)
  }
  assert_true(c.exports.any(e => e.name == "copy" && e.item is Type(_)))
  assert_true(c.types.any(n => n.kind is Record(_)))
  assert_true(c.types.any(n => n.kind is Option(_)))
  assert_true(c.types.any(n => n.kind is Alias(_)))
  let mut referenced_option = false
  for n in c.types {
    if n.kind is Function(ps, result, _) {
      assert_eq(ps.length(), 1)
      assert_true(result is Some(_))
      let mut ty = ps[0].ty
      for _ in 0..<c.types.length() {
        if c.types[ty].kind is Alias(next) { ty = next } else { break }
      }
      referenced_option = c.types[ty].kind is Option(_)
    }
  }
  assert_true(referenced_option)
}

///|
test "D1 dependency re-exports and independently instantiated roots have distinct validation rules" {
  let raw = @fixture.forwarded_import()
  let c = decode("forwarder", raw)
  assert_true(c.exports.any(e => e.name == "run" && e.item is Function(_)))
  let input = @component.parse_component(raw)
  try @validator.validate_component_for_instantiation(input) catch {
    @validator.ExportedImportedFunc(index) => assert_eq(index, 0)
    _ => fail("unexpected root validation failure")
  } noraise { _ => fail("fixed root validator unexpectedly accepted imported function re-export") }
  let _ = @validator.validate_component_for_instantiation(@component.parse_component(@fixture.function_consumer()))
}
