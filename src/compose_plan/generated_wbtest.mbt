///|
fn dag_draw(state : Ref[UInt32]) -> Int32 {
  state.val = state.val * 1664525U + 1013904223U
  (state.val >> 16).reinterpret_as_int()
}

///|
fn dag_case(seed : Int32) -> (Array[@ir.Component], Array[Binding]) {
  let state = Ref(seed.reinterpret_as_uint())
  let count = 3 + dag_draw(state) % 4
  let components : Array[@ir.Component] = []
  for i in 0..<count {
    components.push({
      name: "node-\{count - i}", world: -1, scopes: [],
      types: [
        { name: None, kind: @ir.Scalar("u32") },
        { name: None, kind: @ir.Function([{ name: "x", ty: 0 }], Some(0), false) },
        { name: None, kind: @ir.Interface(None, [], [{ name: "call", item: @ir.Function(1) }, { name: "value", item: @ir.Type(0) }]) },
      ],
      imports: [], exports: [{ name: "ops", item: @ir.Instance(2) }],
    })
  }
  let bindings : Array[Binding] = []
  for consumer in 1..<count {
    for provider in 0..<consumer {
      if (provider == 0 && consumer == count - 1) || dag_draw(state) % 3 == 0 {
        let port = "need-\{provider}"
        components[consumer].imports.push({ name: port, item: @ir.Instance(2) })
        bindings.push({ kind: Instance, from: ep(components[provider].name, "ops"), to: ep(components[consumer].name, port) })
      }
    }
  }
  (components, bindings)
}

///|
// Independent exhaustive permutation oracle, deliberately not Kahn/graph.
// At most 6! complete candidates; check edges only after a full permutation.
fn reference_order(components : Array[@ir.Component], bindings : Array[Binding]) -> Array[String] {
  let names = components.map(c => c.name)
  names.sort_by(@order.cmp_str)
  let path : Array[String] = []
  fn search() -> Bool {
    if path.length() == names.length() {
      let positions : Map[String, Int32] = Map([])
      for i in 0..<path.length() { positions.set(path[i], i) }
      for b in bindings {
        if positions.get(b.from.component).unwrap() >= positions.get(b.to.component).unwrap() { return false }
      }
      return true
    }
    for name in names {
      if path.contains(name) { continue }
      path.push(name)
      if search() { return true }
      let _ = path.pop()
    }
    false
  }
  if !search() { abort("bounded generated DAG unexpectedly cyclic") }
  path
}

///|
fn dag_binding_key(b : Binding) -> String {
  b.from.component + "/" + b.from.port + "->" + b.to.component + "/" + b.to.port
}

///|
fn dag_operation_key(op : Operation) -> String {
  match op { Instantiate(name) => "new:" + name; InstallImport(index) => "import:\{index}" }
}

///|
fn reference_replay(p : Plan, bindings : Array[Binding], seed : Int32) -> Unit raise {
  let started : Map[String, Unit] = Map([])
  let pending : Map[String, Array[String]] = Map([])
  for op in p.operations {
    match op {
      InstallImport(i) => {
        if i < 0 || i >= p.bindings.length() { fail("seed=\{seed}: invalid install index") }
        let b = p.bindings[i].binding
        assert_true(started.contains(b.from.component), msg="seed=\{seed}: source not yet instantiated")
        assert_true(!started.contains(b.to.component), msg="seed=\{seed}: import after instantiation")
        let group = pending.get_or_init(b.to.component, () => [])
        let key = dag_binding_key(b)
        assert_true(!group.contains(key), msg="seed=\{seed}: duplicate install")
        group.push(key)
      }
      Instantiate(name) => {
        assert_true(!started.contains(name), msg="seed=\{seed}: duplicate instantiation")
        let expected = bindings.filter(b => b.to.component == name).map(dag_binding_key)
        let actual = pending.get(name).unwrap_or([])
        assert_eq(actual.length(), expected.length(), msg="seed=\{seed}: incomplete imports")
        for key in expected { assert_true(actual.contains(key), msg="seed=\{seed}: wrong installed import") }
        started.set(name, ())
      }
    }
  }
  assert_eq(started.length(), p.order.length(), msg="seed=\{seed}: missing instantiation")
}

///|
test "D3 2000 fixed small DAGs agree with exhaustive reference and reject single faults" {
  for seed in 0..<2000 {
    let (cs, bs) = dag_case(seed)
    let p = plan(cs, bs)
    assert_eq(p.order, reference_order(cs, bs), msg="seed=\{seed}: topology differs")
    reference_replay(p, bs, seed)
    let reversed_cs = Array::makei(cs.length(), i => cs[cs.length() - i - 1])
    let reversed_bs = Array::makei(bs.length(), i => bs[bs.length() - i - 1])
    let permuted = plan(reversed_cs, reversed_bs)
    assert_eq(permuted.order, p.order, msg="seed=\{seed}: declaration permutation")
    assert_eq(permuted.bindings.map(b => dag_binding_key(b.binding)), p.bindings.map(b => dag_binding_key(b.binding)), msg="seed=\{seed}: binding permutation")
    assert_eq(permuted.operations.map(dag_operation_key), p.operations.map(dag_operation_key), msg="seed=\{seed}: operation permutation")
    assert_eq(error_code(cs, bs[1:].to_owned()), "UNBOUND_IMPORT", msg="seed=\{seed}: deleted edge")
    assert_eq(error_code(cs, bs + [bs[0]]), "DUPLICATE_BINDING", msg="seed=\{seed}: repeated edge")
    let first = cs[0]
    let cyclic = { ..first, imports: first.imports + [{ name: "cycle", item: @ir.Instance(2) }] }
    let cycle_binding : Binding = { kind: Instance, from: ep(first.name, "ops"), to: ep(first.name, "cycle") }
    let mutated = cs.copy()
    mutated[0] = cyclic
    assert_eq(error_code(mutated, bs + [cycle_binding]), "DEPENDENCY_CYCLE", msg="seed=\{seed}: self loop")
  }
}
