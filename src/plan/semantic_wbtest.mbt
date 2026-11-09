// Regression tests distinguish component values that share the same core ABI.

///|
fn typed_sig(ty : @ir.ValTy, async_~ : Bool = false) -> @ir.FuncSig {
  { name: "f", is_async: async_, params: [{ name: "x", ty, }], result: None, }
}

///|
fn typed_input(
  a : @ir.FuncSig,
  at : Array[@ir.TypeDef?],
  b : @ir.FuncSig,
  bt : Array[@ir.TypeDef?],
) -> Input raise {
  let m = manifest_of(
    "{\"components\":[{\"name\":\"source\",\"path\":\"s\"},{\"name\":\"sink\",\"path\":\"t\"}],\"wires\":[{\"from\":\"source.out\",\"to\":\"sink.in\"}]}",
  )
  let source : @ir.Iface = {
    name: "source",
    path: "s",
    exports: [{ name: "out", port: @ir.Func(a), }],
    imports: [],
    unwireable_imports: [],
    types: at,
  }
  let sink : @ir.Iface = {
    name: "sink",
    path: "t",
    exports: [],
    imports: [{ name: "in", port: @ir.Func(b), }],
    unwireable_imports: [],
    types: bt,
  }
  { manifest: m, ifaces: Map([("source", source), ("sink", sink)]), }
}

///|
test "semantics: bool and u32 with identical ABI are rejected through decoding" {
  let a = func_comp(
    [("out", "(param \"x\" bool) (result u32)", "(param i32) (result i32)")],
    [],
  )
  let b = func_comp([], [
    ("in", "(param \"x\" u32) (result u32)", "(param i32) (result i32)"),
  ])
  let m = manifest_of(
    "{\"components\":[{\"name\":\"source\",\"path\":\"s\"},{\"name\":\"sink\",\"path\":\"t\"}],\"wires\":[{\"from\":\"source.out\",\"to\":\"sink.in\"}]}",
  )
  let input = input_of(m, [("source", a), ("sink", b)])
  assert_eq(
    plan_err(input),
    "plan: signature mismatch on wire source.out -> sink.in: parameter 0: bool vs u32",
  )
}

///|
test "semantics: same table index with different list elements is rejected" {
  let input = typed_input(
    typed_sig(@ir.Index(0)),
    [Some(@ir.List(@ir.Bool))],
    typed_sig(@ir.Index(0)),
    [Some(@ir.List(@ir.U32))],
  )
  assert_eq(
    plan_err(input),
    "plan: signature mismatch on wire source.out -> sink.in: parameter 0.element: bool vs u32",
  )
}

///|
test "semantics: async is unsupported even when the ABI matches" {
  let input = typed_input(
    typed_sig(@ir.U32, async_=true),
    [],
    typed_sig(@ir.U32),
    [],
  )
  assert_eq(plan_err(input), "plan: unsupported `source.out`: async function")
}

///|
test "semantics: future handles are unsupported instead of matching u32" {
  let input = typed_input(typed_sig(@ir.U32), [], typed_sig(@ir.Index(0)), [
    Some(@ir.Future(None)),
  ])
  assert_eq(plan_err(input), "plan: unsupported `sink.in`: parameter 0: future")
}

///|
test "semantics: all supported scalars match only themselves" {
  let scalars : Array[@ir.ValTy] = [
    @ir.Bool,
    @ir.S8,
    @ir.U8,
    @ir.S16,
    @ir.U16,
    @ir.S32,
    @ir.U32,
    @ir.S64,
    @ir.U64,
    @ir.F32,
    @ir.F64,
    @ir.Char,
    @ir.String,
  ]
  for a in scalars {
    for b in scalars {
      let input = typed_input(typed_sig(a), [], typed_sig(b), [])
      if a == b {
        let _ = plan(input)
      } else {
        assert_true(
          plan_err(input).contains(
            "signature mismatch on wire source.out -> sink.in",
          ),
        )
      }
    }
  }
}

///|
fn rich_types(offset : Int32) -> Array[@ir.TypeDef?] {
  let table : Array[@ir.TypeDef?] = []
  for i = 0; i < offset; i = i + 1 {
    table.push(None)
  }
  table.push(Some(@ir.List(@ir.U32)))
  table.push(Some(@ir.Option(@ir.Index(offset))))
  table.push(Some(@ir.Result(Some(@ir.Index(offset + 1)), Some(@ir.String))))
  table.push(
    Some(
      @ir.Variant([
        { label: "empty", payload: None, },
        { label: "full", payload: Some(@ir.Index(offset + 2)), },
      ]),
    ),
  )
  table.push(
    Some(
      @ir.Record([
        { name: "nested", ty: @ir.Index(offset + 3), },
        { name: "tag", ty: @ir.Char, },
      ]),
    ),
  )
  table.push(Some(@ir.Tuple([@ir.Index(offset + 4), @ir.Bool])))
  table.push(Some(@ir.Flags(["read", "write"])))
  table.push(Some(@ir.Enum(["first", "second"])))
  table
}

///|
test "semantics: every supported aggregate matches across different type indices" {
  for i = 0; i < 8; i = i + 1 {
    let input = typed_input(
      typed_sig(@ir.Index(i)),
      rich_types(0),
      typed_sig(@ir.Index(i + 3)),
      rich_types(3),
    )
    let p = plan(input)
    assert_eq(p.wires.length(), 1)
  }
}

///|
fn aggregate_err(a : @ir.TypeDef, b : @ir.TypeDef) -> String raise {
  plan_err(
    typed_input(typed_sig(@ir.Index(0)), [Some(a)], typed_sig(@ir.Index(0)), [
      Some(b),
    ]),
  )
}

///|
test "semantics: nested scalar changes are detected in all payload positions" {
  let pairs : Array[(@ir.TypeDef, @ir.TypeDef, String)] = [
    (
      @ir.Record([{ name: "active", ty: @ir.Bool, }]),
      @ir.Record([{ name: "active", ty: @ir.U32, }]),
      ".field(\"active\")",
    ),
    (@ir.Tuple([@ir.Bool]), @ir.Tuple([@ir.U32]), ".tuple[0]"),
    (@ir.Option(@ir.Bool), @ir.Option(@ir.U32), ".some"),
    (@ir.Result(Some(@ir.Bool), None), @ir.Result(Some(@ir.U32), None), ".ok"),
    (@ir.Result(None, Some(@ir.Bool)), @ir.Result(None, Some(@ir.U32)), ".err"),
    (
      @ir.Variant([{ label: "yes", payload: Some(@ir.Bool), }]),
      @ir.Variant([{ label: "yes", payload: Some(@ir.U32), }]),
      ".case(\"yes\")",
    ),
  ]
  for (a, b, suffix) in pairs {
    assert_eq(
      aggregate_err(a, b),
      "plan: signature mismatch on wire source.out -> sink.in: parameter 0\{suffix}: bool vs u32",
    )
  }
}

///|
test "semantics: ordered labels and aggregate kinds are significant" {
  let pairs : Array[(@ir.TypeDef, @ir.TypeDef)] = [
    (
      @ir.Record([{ name: "a", ty: @ir.U32, }]),
      @ir.Record([{ name: "b", ty: @ir.U32, }]),
    ),
    (
      @ir.Record([{ name: "a", ty: @ir.U32, }, { name: "b", ty: @ir.U32, }]),
      @ir.Record([{ name: "b", ty: @ir.U32, }, { name: "a", ty: @ir.U32, }]),
    ),
    (
      @ir.Variant([{ label: "a", payload: None, }]),
      @ir.Variant([{ label: "b", payload: None, }]),
    ),
    (
      @ir.Variant([
        { label: "a", payload: None, },
        { label: "b", payload: None, },
      ]),
      @ir.Variant([
        { label: "b", payload: None, },
        { label: "a", payload: None, },
      ]),
    ),
    (@ir.Flags(["a", "b"]), @ir.Flags(["b", "a"])),
    (@ir.Enum(["a", "b"]), @ir.Enum(["b", "a"])),
    (@ir.Flags(["a"]), @ir.Enum(["a"])),
    (@ir.Record([{ name: "a", ty: @ir.U32, }]), @ir.Tuple([@ir.U32])),
    (@ir.Tuple([@ir.Bool, @ir.U32]), @ir.Tuple([@ir.U32, @ir.Bool])),
  ]
  for (a, b) in pairs {
    assert_true(
      aggregate_err(a, b).contains(
        "signature mismatch on wire source.out -> sink.in",
      ),
    )
  }
}

///|
test "semantics: aggregate sizes and payload absence are significant" {
  let pairs : Array[(@ir.TypeDef, @ir.TypeDef)] = [
    (@ir.Record([]), @ir.Record([{ name: "a", ty: @ir.U32, }])),
    (@ir.Tuple([]), @ir.Tuple([@ir.U32])),
    (@ir.Variant([]), @ir.Variant([{ label: "a", payload: None, }])),
    (@ir.Flags([]), @ir.Flags(["a"])),
    (@ir.Enum([]), @ir.Enum(["a"])),
    (@ir.Result(None, None), @ir.Result(Some(@ir.U32), None)),
    (@ir.Result(None, Some(@ir.U32)), @ir.Result(None, None)),
    (
      @ir.Variant([{ label: "a", payload: None, }]),
      @ir.Variant([{ label: "a", payload: Some(@ir.U32), }]),
    ),
  ]
  for (a, b) in pairs {
    assert_true(aggregate_err(a, b).contains("signature mismatch"))
  }
  let input = typed_input(
    { name: "out", is_async: false, params: [], result: None, },
    [],
    { name: "in", is_async: false, params: [], result: Some(@ir.Index(0)), },
    [Some(@ir.Tuple([]))],
  )
  assert_true(plan_err(input).contains("result arity 0 vs 1"))
}

///|
test "semantics: result values and parameter labels are checked" {
  let input = typed_input(
    { name: "out", is_async: false, params: [], result: Some(@ir.Bool), },
    [],
    { name: "in", is_async: false, params: [], result: Some(@ir.U32), },
    [],
  )
  assert_true(plan_err(input).contains("result: bool vs u32"))
  let input = typed_input(
    typed_sig(@ir.U32),
    [],
    {
      name: "in",
      is_async: false,
      params: [{ name: "renamed", ty: @ir.U32, }],
      result: None,
    },
    [],
  )
  assert_true(
    plan_err(input).contains("parameter 0 name: \"x\" vs \"renamed\""),
  )
}

///|
test "semantics: unsupported kinds are rejected on either endpoint and when nested" {
  let unsupported : Array[(@ir.TypeDef, String)] = [
    (@ir.Own(0), "own"),
    (@ir.Borrow(0), "borrow"),
    (@ir.Resource, "resource"),
    (@ir.Future(None), "future"),
    (@ir.Stream(None), "stream"),
    (@ir.FixedList(@ir.U32, 2), "fixed-list"),
    (@ir.MapType(@ir.U32, @ir.U32), "map"),
    (@ir.Func(typed_sig(@ir.U32)), "function used as a value"),
  ]
  for (ty, name) in unsupported {
    for source in [true, false] {
      let table = [
        Some(@ir.Record([{ name: "hidden", ty: @ir.Index(1), }])),
        Some(ty),
      ]
      let input = if source {
        typed_input(typed_sig(@ir.Index(0)), table, typed_sig(@ir.U32), [])
      } else {
        typed_input(typed_sig(@ir.U32), [], typed_sig(@ir.Index(0)), table)
      }
      let endpoint = if source { "source.out" } else { "sink.in" }
      assert_eq(
        plan_err(input),
        "plan: unsupported `\{endpoint}`: parameter 0.field(\"hidden\"): \{name}",
      )
    }
  }
  let input = typed_input(typed_sig(@ir.ErrorContext), [], typed_sig(@ir.U32), [])
  assert_true(plan_err(input).contains("parameter 0: error-context"))
  let input = typed_input(
    typed_sig(@ir.U32),
    [],
    typed_sig(@ir.U32, async_=true),
    [],
  )
  assert_true(plan_err(input).contains("unsupported `sink.in`: async function"))
}

///|
test "semantics: invalid and recursive public IR cannot reach the ABI flattener" {
  for
    (ty, table) in [
      (@ir.Index(-1), []),
      (@ir.Index(2), []),
      (@ir.Index(0), [None]),
      (@ir.Index(0), [Some(@ir.List(@ir.Index(0)))]),
      (
        @ir.Index(0),
        [Some(@ir.List(@ir.Index(1))), Some(@ir.Option(@ir.Index(0)))],
      ),
    ] {
    let input = typed_input(typed_sig(ty), table, typed_sig(ty), table)
    assert_true(
      plan_err(input).contains("unsupported `source.out`: parameter 0"),
    )
  }
}

///|
test "semantics: shared subtypes are accepted without being mistaken for recursion" {
  let table : Array[@ir.TypeDef?] = [
    Some(@ir.Tuple([@ir.Index(1), @ir.Index(1)])),
    Some(@ir.List(@ir.U32)),
  ]
  let input = typed_input(
    typed_sig(@ir.Index(0)),
    table,
    typed_sig(@ir.Index(0)),
    table,
  )
  let _ = plan(input)
}

///|
test "semantics: decoded aggregates resolve their own type tables" {
  let a = "(component (type $unused (tuple u64)) " +
    "(type $L (list u32)) (export $lp \"items\" (type $L)) " +
    "(type $R (record (field \"items\" $lp))) (export $rp \"row\" (type $R)) " +
    "(core module $M (memory (export \"mem\") 1) " +
    "(func (export \"f\") (param i32 i32) (result i32) (i32.const 0)) " +
    "(func (export \"realloc\") (param i32 i32 i32 i32) (result i32) (i32.const 0))) " +
    "(core instance $m (instantiate $M)) " +
    "(func (export \"out\") (param \"x\" $rp) (result u32) " +
    "(canon lift (core func $m \"f\") (memory $m \"mem\") (realloc (core func $m \"realloc\")))))"
  let b = "(component (type $L (list u32)) (import \"items\" (type $lp (eq $L))) " +
    "(type $R (record (field \"items\" $lp))) (import \"row\" (type $rp (eq $R))) " +
    "(import \"in\" (func (param \"x\" $rp) (result u32))))"
  let m = manifest_of(
    "{\"components\":[{\"name\":\"a\",\"path\":\"a\"},{\"name\":\"b\",\"path\":\"b\"}],\"wires\":[{\"from\":\"a.out\",\"to\":\"b.in\"}]}",
  )
  let input = input_of(m, [("a", a), ("b", b)])
  let from_sig = resolve_port(input.ifaces["a"], ExportSide, "out")
  let to_sig = resolve_port(input.ifaces["b"], ImportSide, "in")
  assert_true(from_sig.params[0].ty != to_sig.params[0].ty)
  let w = plan_wire(input, input.manifest.wires[0], Map([]))
  assert_eq(w.from_port, "out")
}

///|
test "semantics: decoded async and handle functions are explicitly unsupported" {
  let a = func_comp(
    [("out", "(param \"x\" u32) (result u32)", "(param i32) (result i32)")],
    [],
  )
  let cases = [
    (
      "(component (type $t (func async (param \"x\" u32))) (import \"in\" (func (type $t))))",
      "async function",
    ),
    (
      "(component (import \"in\" (func (param \"x\" (future u32)))))", "parameter 0: future",
    ),
    (
      "(component (import \"in\" (func (param \"x\" (stream u32)))))", "parameter 0: stream",
    ),
    (
      "(component (import \"r\" (type $r (sub resource))) (import \"in\" (func (param \"x\" (own $r)))))",
      "parameter 0: own",
    ),
    (
      "(component (import \"r\" (type $r (sub resource))) (import \"in\" (func (param \"x\" (borrow $r)))))",
      "parameter 0: borrow",
    ),
  ]
  let m = manifest_of(
    "{\"components\":[{\"name\":\"a\",\"path\":\"a\"},{\"name\":\"b\",\"path\":\"b\"}],\"wires\":[{\"from\":\"a.out\",\"to\":\"b.in\"}]}",
  )
  for (b, detail) in cases {
    let input = input_of(m, [("a", a), ("b", b)])
    assert_eq(plan_err(input), "plan: unsupported `b.in`: \{detail}")
  }
}

///|
test "semantics: unsupported results are rejected even without parameters" {
  let input = typed_input(
    { name: "out", is_async: false, params: [], result: Some(@ir.Index(0)), },
    [Some(@ir.Stream(None))],
    { name: "in", is_async: false, params: [], result: Some(@ir.U32), },
    [],
  )
  assert_eq(plan_err(input), "plan: unsupported `source.out`: result: stream")
}

///|
test "semantics: flatten_sig cannot bypass the supported subset" {
  let _ = flatten_sig("a", "out", typed_sig(@ir.U32, async_=true), []) catch {
    Unsupported(comp, port, detail) => {
      assert_eq(comp, "a")
      assert_eq(port, "out")
      assert_eq(detail, "async function")
      return
    }
    e => fail(e.to_string())
  }
  fail("async should not flatten as a supported plan signature")
}
