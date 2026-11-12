///|
test "D1 WAC keeps whole-instance transfer and dependency order" {
  let text = emit_wac(components(), [instance_binding()])
  assert_eq(text,
    "package weft:composition;\n\nlet c-source = new weft:source {};\nlet c-consumer = new weft:consumer { \"ops\": c-source[\"ops\"] };\n\nexport c-source as \"source\";\nexport c-consumer as \"consumer\";\n",
  )
}

///|
test "D1 WAC rejects unsupported names without sanitizing logical component IDs" {
  let source = @ir.decode("source.with.dot", @fixture.provider("source"))
  let consumer = @ir.decode("consumer", @fixture.consumer())
  let binding : Binding = { kind: Instance, from: ep(source.name, "ops"), to: ep(consumer.name, "ops") }
  let _ = plan([source, consumer], [binding])
  try emit_wac([source, consumer], [binding]) catch {
    Rejected(d) => assert_eq(d.code, "WAC_UNREPRESENTABLE")
  } noraise { _ => fail("unrepresentable WAC name silently changed") }
}
