///|
fn ep(component : String, port : String, member_name? : String) -> Endpoint {
  { component, port, member_name }
}

///|
fn instance_binding() -> Binding {
  { kind: Instance, from: ep("source", "ops"), to: ep("consumer", "ops") }
}

///|
fn components() -> Array[@ir.Component] raise {
  [@ir.decode("consumer", @fixture.consumer()), @ir.decode("source", @fixture.provider("source"))]
}

///|
fn error_code(cs : Array[@ir.Component], bs : Array[Binding]) -> String raise {
  try plan(cs, bs) catch { Rejected(d) => d.code } noraise { _ => fail("expected plan rejection") }
}

///|
test "D1 plan installs a complete instance after provider and before consumer" {
  let p = plan(components(), [instance_binding()])
  assert_eq(p.order, ["source", "consumer"])
  assert_eq(p.bindings.length(), 1)
  assert_true(p.operations is [Instantiate("source"), InstallImport(0), Instantiate("consumer")])
}

///|
test "D1 complete imports reject absence duplicate and mixed member binding" {
  let cs = components()
  let whole = instance_binding()
  let partial : Binding = { kind: Function, from: ep("source", "ops", member_name="inc"), to: ep("consumer", "ops", member_name="inc") }
  assert_eq(error_code(cs, []), "UNBOUND_IMPORT")
  assert_eq(error_code(cs, [whole, whole]), "DUPLICATE_BINDING")
  assert_eq(error_code(cs, [partial]), "PARTIAL_INSTANCE_BINDING")
  assert_eq(error_code(cs, [whole, partial]), "MIXED_BINDING")
  assert_eq(error_code(cs, [partial, whole]), "MIXED_BINDING")
}

///|
test "D1 function bindings address source interface members explicitly" {
  let source = @ir.decode("source", @fixture.provider("source"))
  let target = @ir.decode("target", @text.parse_component_wat(
    "(component (import \"read\" (func (param \"renamed\" u32) (result u32))))",
  ))
  let binding : Binding = { kind: Function, from: ep("source", "ops", member_name="inc"), to: ep("target", "read") }
  let p = plan([target, source], [binding])
  assert_eq(p.order, ["source", "target"])
  let wrong : Binding = { ..binding, from: ep("source", "ops") }
  assert_eq(error_code([target, source], [wrong]), "INVALID_MEMBER_KIND")
}

///|
fn cyclic_component(name : String) -> @ir.Component {
  {
    name, world: -1, scopes: [],
    types: [
      { name: None, kind: @ir.Scalar("u32") },
      { name: None, kind: @ir.Interface(None, [], [{ name: "value", item: @ir.Type(0) }]) },
    ],
    imports: [{ name: "ops", item: @ir.Instance(1) }],
    exports: [{ name: "ops", item: @ir.Instance(1) }],
  }
}

///|
test "D1 type-correct instance cycles fail instead of producing an execution order" {
  let a = cyclic_component("a")
  let b = cyclic_component("b")
  let ab : Binding = { kind: Instance, from: ep("a", "ops"), to: ep("b", "ops") }
  let ba : Binding = { kind: Instance, from: ep("b", "ops"), to: ep("a", "ops") }
  assert_eq(error_code([a, b], [ab, ba]), "DEPENDENCY_CYCLE")
  assert_eq(error_code([a], [{ ..ab, to: ep("a", "ops") }]), "DEPENDENCY_CYCLE")
}

///|
test "D1 logical component IDs and explicit ports do not split at punctuation" {
  let source = @ir.decode("source.with.dot", @fixture.provider("source"))
  let target = @ir.decode("consumer.with.dot", @fixture.consumer())
  let b : Binding = { kind: Instance, from: ep(source.name, "ops"), to: ep(target.name, "ops") }
  assert_eq(plan([target, source], [b]).order, [source.name, target.name])
}

///|
test "D1 complete planning rejects unknown and duplicate components and implicit host types" {
  let cs = components()
  let b = instance_binding()
  assert_eq(error_code(cs, [{ ..b, from: ep("missing", "ops") }]), "UNKNOWN_COMPONENT")
  assert_eq(error_code(cs + [cs[0]], [b]), "DUPLICATE_COMPONENT")
  let root = cyclic_component("host")
  let root : @ir.Component = { ..root, imports: [{ name: "capability", item: @ir.Type(0) }] }
  assert_eq(error_code([root], []), "UNSUPPORTED_IMPORT")
}

///|
test "D1 binding order does not change operations or target ordering" {
  let source = @ir.decode("source", @fixture.provider("source"))
  let a = @ir.decode("a", @fixture.consumer())
  let b = @ir.decode("b", @fixture.consumer())
  let first = { ..instance_binding(), to: ep("a", "ops") }
  let second = { ..instance_binding(), to: ep("b", "ops") }
  let x = plan([b, source, a], [second, first])
  let y = plan([a, source, b], [first, second])
  assert_eq(x.order, y.order)
  assert_true(x.operations is [Instantiate("source"), InstallImport(0), Instantiate("a"), InstallImport(1), Instantiate("b")])
  assert_eq(x.bindings.map(x => x.binding.to.component), y.bindings.map(x => x.binding.to.component))
}

///|
test "D1 separate root function and instance imports may both have explicit providers" {
  let source = @ir.decode("source", @fixture.provider("source"))
  let consumer = @ir.decode("consumer", @text.parse_component_wat(
    "(component (import \"ops\" (instance (type $v u32) (export \"value\" (type (eq $v))) (export \"inc\" (func (param \"x\" u32) (result u32))) (export \"twice\" (func (param \"x\" u32) (result u32))))) (import \"extra\" (func (param \"x\" u32) (result u32))))",
  ))
  let extra : Binding = { kind: Function, from: ep("source", "ops", member_name="inc"), to: ep("consumer", "extra") }
  let p = plan([consumer, source], [instance_binding(), extra])
  assert_eq(p.bindings.length(), 2)
  assert_true(p.operations is [Instantiate("source"), InstallImport(0), InstallImport(1), Instantiate("consumer")])
}
