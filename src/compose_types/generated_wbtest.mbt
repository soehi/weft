// Early D3 oracle. Bounded, deterministic small graphs; no production shape,
// alias-resolution or compatibility helper is used by the reference renderer.

///|
fn draw(state : Ref[UInt32]) -> Int32 {
  state.val = state.val * 1664525U + 1013904223U
  (state.val >> 16).reinterpret_as_int()
}

///|
fn generated(seed : Int32) -> @ir.Component {
  let state = Ref(seed.reinterpret_as_uint())
  let kinds : Array[@ir.Kind] = [@ir.Scalar("u32")]
  let count = 3 + draw(state) % 5
  for _ in 0..<count {
    let prev = kinds.length() - 1
    let next : @ir.Kind = match draw(state) % 9 {
      0 => @ir.Alias(prev)
      1 => @ir.List(prev)
      2 => @ir.Option(prev)
      3 => @ir.Record([{ name: "value", ty: prev, }, { name: "tail", ty: 0, }])
      4 => @ir.Tuple([prev, 0])
      5 => @ir.Result(Some(prev), None)
      6 =>
        @ir.Variant([
          { name: "ok", ty: Some(prev), },
          { name: "empty", ty: None, },
        ])
      7 => @ir.Flags(["a", "b"])
      _ => @ir.Enum(["first", "second"])
    }
    kinds.push(next)
  }
  let payload = kinds.length() - 1
  let function = kinds.length()
  kinds.push(@ir.Function([{ name: "argument", ty: payload, }], Some(0), false))
  kinds.push(
    @ir.Interface(None, [], [
      { name: "call", item: @ir.Function(function), },
      { name: "payload", item: @ir.Type(payload), },
    ]),
  )
  graph("generated", kinds)
}

///|
fn reference_value(
  c : @ir.Component,
  i : Int32,
  active : Array[Int32],
) -> String? {
  if i < 0 ||
    i >= c.types.length() ||
    active.contains(i) ||
    active.length() > 32 {
    return None
  }
  let active = active + [i]
  fn child(index : Int32) -> String? {
    reference_value(c, index, active)
  }
  match c.types[i].kind {
    @ir.Scalar(s) => Some("scalar(" + s + ")")
    @ir.Alias(t) => child(t)
    @ir.Record(fields) => {
      let parts : Array[String] = []
      for f in fields {
        guard child(f.ty) is Some(s) else { return None }
        parts.push(f.name + "=" + s)
      }
      Some("record(" + parts.join(",") + ")")
    }
    @ir.Tuple(ts) => {
      let parts : Array[String] = []
      for t in ts {
        guard child(t) is Some(s) else { return None }
        parts.push(s)
      }
      Some("tuple(" + parts.join(",") + ")")
    }
    @ir.List(t) => child(t).map(s => "list(" + s + ")")
    @ir.Option(t) => child(t).map(s => "option(" + s + ")")
    @ir.Result(a, b) => {
      let a = if a is Some(t) { child(t) } else { Some("absent") }
      let b = if b is Some(t) { child(t) } else { Some("absent") }
      if a is Some(x) && b is Some(y) {
        Some("result(" + x + "," + y + ")")
      } else {
        None
      }
    }
    @ir.Variant(cases) => {
      let parts : Array[String] = []
      for entry in cases {
        let s = if entry.ty is Some(t) { child(t) } else { Some("absent") }
        guard s is Some(s) else { return None }
        parts.push(entry.name + "=" + s)
      }
      Some("variant(" + parts.join(",") + ")")
    }
    @ir.Flags(ns) => Some("flags(" + ns.join(",") + ")")
    @ir.Enum(ns) => Some("enum(" + ns.join(",") + ")")
    _ => None
  }
}

///|
fn reference_function(c : @ir.Component, i : Int32) -> String? {
  if i < 0 || i >= c.types.length() {
    return None
  }
  guard c.types[i].kind is @ir.Function(ps, r, false) else { return None }
  let parts : Array[String] = []
  for p in ps {
    guard reference_value(c, p.ty, []) is Some(s) else { return None }
    parts.push(s)
  }
  let result = if r is Some(t) {
    reference_value(c, t, [])
  } else {
    Some("absent")
  }
  result.map(s => "fn(" + parts.join(",") + ")->" + s)
}

///|
fn reference_admits(p : @ir.Component, c : @ir.Component) -> Bool {
  guard p.exports[0].item is @ir.Instance(pi) &&
    c.imports[0].item is @ir.Instance(ci) else {
    return false
  }
  guard p.types[pi].kind is @ir.Interface(_, _, provided) &&
    c.types[ci].kind is @ir.Interface(_, _, required) else {
    return false
  }
  for need in required {
    let mut found = false
    for candidate in provided {
      if candidate.name != need.name {
        continue
      }
      let (a, b) = match (need.item, candidate.item) {
        (@ir.Type(x), @ir.Type(y)) =>
          (reference_value(c, x, []), reference_value(p, y, []))
        (@ir.Function(x), @ir.Function(y)) =>
          (reference_function(c, x), reference_function(p, y))
        _ => (None, None)
      }
      if a is Some(x) && b is Some(y) && x == y {
        found = true
      }
    }
    if !found {
      return false
    }
  }
  true
}

///|
fn rewritten(
  kind : @ir.Kind,
  ref_ : (Int32) -> Int32,
  rename : Bool,
) -> @ir.Kind {
  fn fields(fs : Array[@ir.Field], labels : Bool) -> Array[@ir.Field] {
    fs.map(f => {
      name: if labels {
        "renamed-" + f.name
      } else {
        f.name
      },
      ty: ref_(f.ty),
    })
  }
  match kind {
    @ir.Scalar(s) => @ir.Scalar(s)
    @ir.Alias(i) => @ir.Alias(ref_(i))
    @ir.Record(fs) => @ir.Record(fields(fs, false))
    @ir.Tuple(ts) => @ir.Tuple(ts.map(ref_))
    @ir.List(i) => @ir.List(ref_(i))
    @ir.Option(i) => @ir.Option(ref_(i))
    @ir.Result(a, b) => @ir.Result(a.map(ref_), b.map(ref_))
    @ir.Variant(cs) =>
      @ir.Variant(
        cs.map(c => ({ name: c.name, ty: c.ty.map(ref_), } : @ir.Case)),
      )
    @ir.Flags(ns) => @ir.Flags(ns.copy())
    @ir.Enum(ns) => @ir.Enum(ns.copy())
    @ir.Function(ps, r, a) => @ir.Function(fields(ps, rename), r.map(ref_), a)
    @ir.Interface(n, _, es) =>
      @ir.Interface(
        n,
        [],
        es.map(e => {
          name: e.name,
          item: match e.item {
            @ir.Type(i) => @ir.Type(ref_(i))
            @ir.Function(i) => @ir.Function(ref_(i))
            _ => abort("generator member outside oracle subset")
          },
        }),
      )
    _ => abort("generator type outside oracle subset")
  }
}

///|
fn permuted(c : @ir.Component) -> @ir.Component {
  let size = c.types.length()
  let nodes : Array[@ir.Node] = Array::makei(size, i => {
    name: None,
    kind: rewritten(c.types[size - i - 1].kind, j => size - j - 1, true),
  })
  {
    ..c,
    types: nodes,
    imports: [{ name: "ops", item: @ir.Instance(0), }],
    exports: [{ name: "ops", item: @ir.Instance(0), }],
  }
}

///|
fn oracle_case(
  seed : Int32,
  variant : String,
  p : @ir.Component,
  c : @ir.Component,
) -> Unit raise {
  let expected = reference_admits(p, c)
  let actual = try {
    let _ = check_instance(p, "ops", c, "ops")
    true
  } catch {
    Rejected(_) => false
  }
  if actual != expected {
    fail(
      "seed=\{seed} variant=\{variant} expected=\{expected} actual=\{actual}",
    )
  }
}

///|
test "D3 seed-bounded reference oracle: 2000 small type graphs and single-point mutations" {
  // At most 11 nodes per original graph; max reference depth 32; 4 variants.
  for seed in 0..<2000 {
    let c = generated(seed)
    let p = permuted(c)
    oracle_case(seed, "arena permutation and label rename", p, c)
    let bad = permuted(c)
    bad.types[bad.types.length() - 1] = {
      name: None,
      kind: @ir.Scalar("bool"),
    }
    oracle_case(seed, "scalar mutation", bad, c)
    let missing = permuted(c)
    guard missing.types[0].kind is @ir.Interface(n, us, es) else {
      fail("generator root invariant")
    }
    missing.types[0] = {
      name: None,
      kind: @ir.Interface(n, us, es.filter(e => e.name != "call")),
    }
    oracle_case(seed, "deleted function", missing, c)
    let expanded = permuted(c)
    let scalar = expanded.types.length() - 1
    let alias_index = expanded.types.length()
    let nodes : Array[@ir.Node] = expanded.types.map(n => {
      name: None,
      kind: rewritten(
        n.kind,
        i => if i == scalar { alias_index } else { i },
        false,
      ),
    })
    nodes.push({ name: None, kind: @ir.Alias(scalar), })
    oracle_case(
      seed,
      "legal alias replacement",
      { ..expanded, types: nodes, },
      c,
    )
  }
}
