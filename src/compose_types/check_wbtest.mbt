///|
fn graph(name : String, kinds : Array[@ir.Kind]) -> @ir.Component {
  let instance = kinds.length() - 1
  {
    name, world: -1, scopes: [],
    types: kinds.map(kind => { name: None, kind }),
    imports: [{ name: "ops", item: @ir.Instance(instance) }],
    exports: [{ name: "ops", item: @ir.Instance(instance) }],
  }
}

///|
fn synthetic() -> @ir.Component {
  graph("synthetic", [
    @ir.Scalar("u32"),
    @ir.Alias(0),
    @ir.Record([{ name: "value", ty: 1 }, { name: "other", ty: 0 }]),
    @ir.List(2),
    @ir.Option(3),
    @ir.Tuple([4, 0]),
    @ir.Result(Some(5), None),
    @ir.Variant([{ name: "ok", ty: Some(6) }, { name: "empty", ty: None }]),
    @ir.Function([{ name: "input", ty: 7 }], Some(0), false),
    @ir.Interface(None, [], [
      { name: "payload", item: @ir.Type(2) },
      { name: "calculate", item: @ir.Function(8) },
    ]),
  ])
}

///|
fn failure(provider : @ir.Component, consumer : @ir.Component) -> Diagnostic raise {
  try check_instance(provider, "ops", consumer, "ops") catch {
    Rejected(d) => d
  } noraise { _ => fail("expected compatibility rejection") }
}

///|
test "D1 whole instances compare real functions named types and aliases" {
  let consumer = @ir.decode("consumer", @fixture.consumer())
  for mode in ["source", "alternate"] {
    let provider = @ir.decode(mode, @fixture.provider(mode))
    let relation = check_instance(provider, "ops", consumer, "ops")
    assert_eq(relation.consumer_component, "consumer")
    assert_eq(relation.provider_component, mode)
    assert_true(relation.pairs.length() > 0)
  }
  let missing = failure(@ir.decode("missing", @fixture.provider("missing")), consumer)
  assert_eq(missing.code, "MISSING_MEMBER")
  assert_eq(missing.component, "consumer")
  assert_eq(missing.path, ["imports", "ops", "function:twice"])
  let wrong = failure(@ir.decode("wrong", @fixture.provider("wrong-type")), consumer)
  assert_eq(wrong.code, "TYPE_MISMATCH")
  assert_eq(wrong.path, ["imports", "ops", "function:inc", "parameter:0"])
}

///|
test "D1 alias chains and different arena numbering preserve nested value compatibility" {
  let consumer = synthetic()
  // One consumer scalar is matched to a differently numbered provider scalar,
  // with a longer alias chain and independently resolved nested structures.
  let provider = graph("renumbered", [
    @ir.Scalar("bool"), @ir.Scalar("u32"), @ir.Alias(1), @ir.Alias(2),
    @ir.Record([{ name: "value", ty: 3 }, { name: "other", ty: 1 }]),
    @ir.List(4), @ir.Option(5), @ir.Tuple([6, 1]), @ir.Result(Some(7), None),
    @ir.Variant([{ name: "ok", ty: Some(8) }, { name: "empty", ty: None }]),
    @ir.Function([{ name: "renamed-label", ty: 9 }], Some(1), false),
    @ir.Interface(Some("another-name"), [], [
      { name: "calculate", item: @ir.Function(10) },
      { name: "payload", item: @ir.Type(4) },
    ]),
  ])
  let result = check_instance(provider, "ops", consumer, "ops")
  assert_true(result.pairs.contains((0, 1)))
  assert_true(result.pairs.contains((2, 4)))
}

///|
test "D1 interface member order and extra supported exports do not prevent binding" {
  let consumer = synthetic()
  let provider = synthetic()
  provider.types[9] = { name: None, kind: @ir.Interface(None, [], [
    { name: "z-extra", item: @ir.Type(0) },
    { name: "payload", item: @ir.Type(2) },
    { name: "calculate", item: @ir.Function(8) },
  ]) }
  let _ = check_instance(provider, "ops", consumer, "ops")
}

///|
test "D1 shared consumer type may correspond to distinct equivalent provider nodes" {
  let consumer = graph("consumer", [@ir.Scalar("u32"), @ir.Interface(None, [], [
    { name: "a", item: @ir.Type(0) }, { name: "b", item: @ir.Type(0) },
  ])])
  let provider = graph("provider", [@ir.Scalar("u32"), @ir.Scalar("u32"), @ir.Interface(None, [], [
    { name: "a", item: @ir.Type(0) }, { name: "b", item: @ir.Type(1) },
  ])])
  let result = check_instance(provider, "ops", consumer, "ops")
  assert_true(result.pairs.contains((0, 0)))
  assert_true(result.pairs.contains((0, 1)))
}

///|
test "D1 cyclic graphs on both sides are not accepted by visited-pair memoization" {
  for kinds in [
    [@ir.Alias(1), @ir.Alias(0), @ir.Interface(None, [], [{ name: "loop", item: @ir.Type(0) }])],
    [@ir.Record([{ name: "self", ty: 0 }]), @ir.Interface(None, [], [{ name: "loop", item: @ir.Type(0) }])],
  ] {
    let d = failure(graph("provider", kinds), graph("consumer", kinds))
    assert_eq(d.code, "CYCLIC_TYPE")
  }
}

///|
test "D1 record and variant order remains part of strict value matching" {
  let consumer = synthetic()
  let provider = synthetic()
  provider.types[2] = { name: None, kind: @ir.Record([{ name: "other", ty: 0 }, { name: "value", ty: 1 }]) }
  let d = failure(provider, consumer)
  assert_eq(d.code, "TYPE_MISMATCH")
  assert_true(d.path.contains("field:value"))
  let provider = synthetic()
  provider.types[7] = { name: None, kind: @ir.Variant([{ name: "empty", ty: None }, { name: "ok", ty: Some(6) }]) }
  assert_eq(failure(provider, consumer).code, "TYPE_MISMATCH")
}

///|
test "D1 scalar semantic mismatch inside a nested payload is located" {
  let provider = synthetic()
  let consumer = synthetic()
  provider.types[0] = { name: None, kind: @ir.Scalar("bool") }
  let d = failure(provider, consumer)
  assert_eq(d.code, "TYPE_MISMATCH")
  assert_true(d.path.contains("parameter:0"))
  assert_true(d.path.contains("case:ok"))
  assert_true(d.path.contains("field:value"))
}

///|
test "D1 unsupported resources async and extra capabilities are explicit failures" {
  for kind in [@ir.Resource(None), @ir.Own(0), @ir.Borrow(0), @ir.Future(None), @ir.Stream(None), @ir.FixedList(0, 1), @ir.Map(0, 0), @ir.Scalar("error-context")] {
    let provider = synthetic()
    provider.types[0] = { name: None, kind }
    assert_eq(failure(provider, synthetic()).code, "UNSUPPORTED_TYPE")
  }
  let provider = synthetic()
  provider.types[8] = { name: None, kind: @ir.Function([], None, true) }
  assert_eq(failure(provider, synthetic()).code, "UNSUPPORTED_TYPE")
}

///|
test "D1 malformed public IR references kinds and duplicate members fail deterministically" {
  let provider = synthetic()
  provider.types[1] = { name: None, kind: @ir.Alias(999) }
  assert_eq(failure(provider, synthetic()).code, "INVALID_TYPE_REFERENCE")
  let provider = synthetic()
  provider.types[9] = { name: None, kind: @ir.Interface(None, [], [
    { name: "same", item: @ir.Type(0) }, { name: "same", item: @ir.Function(8) },
  ]) }
  assert_eq(failure(provider, synthetic()).code, "DUPLICATE_MEMBER")
  let provider = synthetic()
  provider.types[9] = { name: None, kind: @ir.Interface(None, [], [{ name: "not-a-function", item: @ir.Function(0) }]) }
  assert_eq(failure(provider, synthetic()).code, "INVALID_MEMBER_KIND")
}

///|
test "D1 no cross-call type cache survives mutation of public IR" {
  let provider = synthetic()
  let consumer = synthetic()
  let _ = check_instance(provider, "ops", consumer, "ops")
  provider.types[0] = { name: None, kind: @ir.Scalar("bool") }
  assert_eq(failure(provider, consumer).code, "TYPE_MISMATCH")
}

///|
test "D1 flags and enum names retain order and payload presence is exact" {
  for (kind, other) in [
    (@ir.Flags(["a", "b"]), @ir.Flags(["b", "a"])),
    (@ir.Enum(["a", "b"]), @ir.Enum(["a", "b", "c"])),
    (@ir.Result(Some(1), None), @ir.Result(None, Some(1))),
  ] {
    let a = graph("a", [kind, @ir.Scalar("u32"), @ir.Interface(None, [], [{ name: "t", item: @ir.Type(0) }])])
    let b = graph("b", [other, @ir.Scalar("u32"), @ir.Interface(None, [], [{ name: "t", item: @ir.Type(0) }])])
    let _ = check_instance(a, "ops", a, "ops")
    assert_eq(failure(a, b).code, "TYPE_MISMATCH")
  }
}

///|
test "D1 nested instance members use local references and reject recursive instances" {
  let consumer = graph("consumer", [
    @ir.Scalar("u32"),
    @ir.Interface(None, [], [{ name: "value", item: @ir.Type(0) }]),
    @ir.Interface(None, [], [{ name: "child", item: @ir.Instance(1) }]),
  ])
  let provider = graph("provider", [
    @ir.Scalar("u32"),
    @ir.Interface(None, [], [{ name: "extra", item: @ir.Type(0) }, { name: "value", item: @ir.Type(0) }]),
    @ir.Interface(None, [], [{ name: "child", item: @ir.Instance(1) }]),
  ])
  let _ = check_instance(provider, "ops", consumer, "ops")
  provider.types[1] = { name: None, kind: @ir.Interface(None, [], [{ name: "loop", item: @ir.Instance(2) }]) }
  assert_eq(failure(provider, consumer).code, "CYCLIC_TYPE")
}

///|
test "D1 a re-exported function retains the same declared import signature" {
  let c = @ir.decode("forwarder", @fixture.forwarded_import())
  let _ = check_function(c, "run", None, c, "inc") catch {
    Rejected(d) => fail(d.code + " " + d.path.join(" / ") + " " + d.detail)
  }
}

///|
test "D1 even structurally matching public IR cannot use function or instance types as values" {
  for kind in [@ir.Kind::Function([], None, false), @ir.Kind::Interface(None, [], [])] {
    let provider = synthetic()
    let consumer = synthetic()
    provider.types[0] = { name: None, kind }
    consumer.types[0] = { name: None, kind }
    assert_eq(failure(provider, consumer).code, "INVALID_VALUE_TYPE")
  }
}
