// verifier arena -> IR. Two conversions live here:
//   1. arena types -> IR `TypeDef?` table (for the emitted plan / canonical).
//   2. IR `ValTy` -> `@model.ValType` + `@model.TypeDef?` table (for reusing
//      the upstream canonical ABI flattening).

///|
fn scalar_to_valty(s : String) -> ValTy? {
  match s {
    "bool" => Some(Bool)
    "s8" => Some(S8)
    "u8" => Some(U8)
    "s16" => Some(S16)
    "u16" => Some(U16)
    "s32" => Some(S32)
    "u32" => Some(U32)
    "s64" => Some(S64)
    "u64" => Some(U64)
    "f32" => Some(F32)
    "f64" => Some(F64)
    "char" => Some(Char)
    "string" => Some(String)
    "error-context" => Some(ErrorContext)
    _ => None
  }
}

///|
/// Follow `Alias` chains to the underlying index. Returns the final index.
fn resolve_alias(
  i : Int32,
  arena : ReadOnlyArray[@verifier.ResolvedType],
) -> Int32 {
  let mut cur = i
  let mut hops = 0
  while hops < arena.length() {
    if cur < 0 || cur >= arena.length() {
      return cur
    }
    match arena[cur].kind {
      Alias(j) => {
        cur = j
        hops = hops + 1
      }
      _ => return cur
    }
  }
  cur
}

///|
/// Convert an arena type reference into an IR `ValTy`. Scalars inline; anything
/// else keeps its (alias-resolved) index so it points at the converted table.
fn arena_valty(
  i : Int32,
  arena : ReadOnlyArray[@verifier.ResolvedType],
) -> ValTy {
  let idx = resolve_alias(i, arena)
  if idx >= 0 && idx < arena.length() {
    match arena[idx].kind {
      Scalar(s) =>
        match scalar_to_valty(s) {
          Some(v) => v
          None => Index(idx)
        }
      _ => Index(idx)
    }
  } else {
    Index(idx)
  }
}

///|
fn arena_opt_valty(
  i : Int32?,
  arena : ReadOnlyArray[@verifier.ResolvedType],
) -> ValTy? {
  match i {
    Some(i) => Some(arena_valty(i, arena))
    None => None
  }
}

///|
fn arena_func(
  f : ReadOnlyArray[@verifier.TypeMember],
  result : Int32?,
  is_async : Bool,
  arena : ReadOnlyArray[@verifier.ResolvedType],
  name : String,
) -> FuncSig {
  let ps : Array[ParamSig] = []
  for p in f {
    ps.push({ name: p.name, ty: arena_valty(p.ty, arena), })
  }
  { name, is_async, params: ps, result: arena_opt_valty(result, arena), }
}

///|
fn to_array(a : ReadOnlyArray[String]) -> Array[String] {
  let out : Array[String] = []
  for x in a {
    out.push(x)
  }
  out
}

///|
/// Build the IR type table from a verifier arena. Index alignment is preserved:
/// entry `i` always corresponds to arena index `i`.
fn build_types(
  arena : ReadOnlyArray[@verifier.ResolvedType],
) -> Array[TypeDef?] {
  let out : Array[TypeDef?] = []
  for t in arena {
    let d : TypeDef? = match t.kind {
      Scalar(_) => None
      Alias(_) => None
      // Interfaces and worlds are structural containers, not value types.
      Interface(_, _, _) => None
      World(_, _, _, _) => None
      Module(_) => None
      Function(params, result, is_async) =>
        Some(Func(arena_func(params, result, is_async, arena, "")))
      Record(fields) => {
        let fs : Array[ParamSig] = []
        for f in fields {
          fs.push({ name: f.name, ty: arena_valty(f.ty, arena), })
        }
        Some(Record(fs))
      }
      List(t) => Some(List(arena_valty(t, arena)))
      FixedList(t, n) => Some(FixedList(arena_valty(t, arena), n))
      Map(k, v) => Some(MapType(arena_valty(k, arena), arena_valty(v, arena)))
      Tuple(ts) => {
        let xs : Array[ValTy] = []
        for x in ts {
          xs.push(arena_valty(x, arena))
        }
        Some(Tuple(xs))
      }
      Option(t) => Some(Option(arena_valty(t, arena)))
      Result(ok, err) =>
        Some(Result(arena_opt_valty(ok, arena), arena_opt_valty(err, arena)))
      Variant(cases) => {
        let cs : Array[CaseSig] = []
        for c in cases {
          cs.push({ label: c.name, payload: arena_opt_valty(c.payload, arena), })
        }
        Some(Variant(cs))
      }
      Flags(names) => Some(Flags(to_array(names)))
      Enum(names) => Some(Enum(to_array(names)))
      Own(i) => Some(Own(i))
      Borrow(i) => Some(Borrow(i))
      Future(t) => Some(Future(arena_opt_valty(t, arena)))
      Stream(t) => Some(Stream(arena_opt_valty(t, arena)))
      Resource(_) => Some(Resource)
    }
    out.push(d)
  }
  out
}

///|
/// Convert an arena reference to its IR port shape, or `None` if the named item
/// is not something a wire can address.
fn arena_port(
  kind : @verifier.ItemKind,
  arena : ReadOnlyArray[@verifier.ResolvedType],
) -> Port? {
  match kind {
    Type(i) =>
      if i >= 0 && i < arena.length() {
        match arena[i].kind {
          Interface(_, _, externs) =>
            Some(Interface("", iface_funcs(externs, arena)))
          _ => None
        }
      } else {
        None
      }
    Function(i) =>
      if i >= 0 && i < arena.length() {
        match arena[i].kind {
          Function(params, result, is_async) =>
            Some(Func(arena_func(params, result, is_async, arena, "")))
          _ => None
        }
      } else {
        None
      }
    // An imported interface may be addressed as an instance rather than a
    // type; both point into the same arena shape.
    Instance(i) =>
      if i >= 0 && i < arena.length() {
        match arena[i].kind {
          Interface(_, _, externs) =>
            Some(Interface("", iface_funcs(externs, arena)))
          _ => None
        }
      } else {
        None
      }
    _ => None
  }
}

///|
/// Collect the function members of an interface's extern list, sorted by name.
fn iface_funcs(
  externs : ReadOnlyArray[@verifier.Extern],
  arena : ReadOnlyArray[@verifier.ResolvedType],
) -> Array[FuncSig] {
  let fs : Array[FuncSig] = []
  for e in externs {
    match e.kind {
      Function(fi) =>
        if fi >= 0 && fi < arena.length() {
          match arena[fi].kind {
            Function(params, result, is_async) =>
              fs.push(arena_func(params, result, is_async, arena, e.name))
            _ => ()
          }
        }
      _ => ()
    }
  }
  fs.sort_by(fn(a, b) { cmp_str(a.name, b.name) })
  fs
}

///|
/// Sort port entries by name, and interface function lists by name, so the plan
/// is byte-stable regardless of binary declaration order.
fn sort_entries(entries : Array[PortEntry]) -> Unit {
  entries.sort_by(fn(a, b) { cmp_str(a.name, b.name) })
}

///|
fn sort_iface_funcs(entries : Array[PortEntry]) -> Unit {
  for e in entries {
    match e.port {
      Interface(name, fs) => {
        fs.sort_by(fn(a, b) { cmp_str(a.name, b.name) })
        let _ = name
      }
      Func(_) => ()
    }
  }
}

///|
/// Decode a component binary into an IR interface. `name`/`path` come from the
/// manifest so error messages can name the component.
pub fn decode_component(
  name : String,
  path : String,
  bytes : Bytes,
) -> Iface raise IrError {
  let pkg = match @verifier.decode_component_package(bytes, source_id=name) {
    Ok(p) => p
    Err(diags) => {
      let msgs : Array[String] = []
      for d in diags {
        msgs.push("[\{d.code}] \{d.message}")
      }
      raise DecodeFailed(name, msgs.join("; "))
    }
  }
  let arena = pkg.types()
  let types = build_types(arena)
  let w = pkg.world()
  let exports : Array[PortEntry] = []
  let imports : Array[PortEntry] = []
  let unwireable_imports : Array[String] = []
  if w >= 0 && w < arena.length() {
    match arena[w].kind {
      World(_, _, ins, outs) => {
        for e in ins {
          match arena_port(e.kind, arena) {
            Some(p) => imports.push({ name: e.name, port: p, })
            None => unwireable_imports.push(e.name)
          }
        }
        for e in outs {
          match arena_port(e.kind, arena) {
            Some(p) => exports.push({ name: e.name, port: p, })
            None => ()
          }
        }
      }
      _ => raise DecodeFailed(name, "root type is not a world")
    }
  } else {
    raise DecodeFailed(name, "component has no world type")
  }
  sort_entries(exports)
  sort_entries(imports)
  sort_iface_funcs(exports)
  sort_iface_funcs(imports)
  unwireable_imports.sort_by(cmp_str)
  { name, path, exports, imports, unwireable_imports, types, }
}

// --- IR -> model conversion, for canonical ABI reuse -----------------------

///|
fn ir_valty_to_model(t : ValTy) -> @model.ValType {
  match t {
    Bool => @model.Prim(@model.Bool)
    S8 => @model.Prim(@model.S8)
    U8 => @model.Prim(@model.U8)
    S16 => @model.Prim(@model.S16)
    U16 => @model.Prim(@model.U16)
    S32 => @model.Prim(@model.S32)
    U32 => @model.Prim(@model.U32)
    S64 => @model.Prim(@model.S64)
    U64 => @model.Prim(@model.U64)
    F32 => @model.Prim(@model.F32)
    F64 => @model.Prim(@model.F64)
    Char => @model.Prim(@model.Char)
    String => @model.Prim(@model.String)
    ErrorContext => @model.Prim(@model.ErrorContext)
    Index(i) => @model.TypeIdx(i)
  }
}

///|
fn ir_opt_to_model(t : ValTy?) -> @model.ValType? {
  match t {
    Some(t) => Some(ir_valty_to_model(t))
    None => None
  }
}

///|
/// Build a `model` type table from an IR table. Indices are preserved so a
/// `ValTy::Index` resolves to the same slot in both.
pub fn to_model_table(types : Array[TypeDef?]) -> Array[@model.TypeDef?] {
  let out : Array[@model.TypeDef?] = []
  for t in types {
    let d : @model.TypeDef? = match t {
      None => None
      Some(Func(sig)) => {
        let ps : Array[@model.Param] = []
        for p in sig.params {
          ps.push({ label: p.name, ty: ir_valty_to_model(p.ty), })
        }
        Some(
          @model.FuncType({
            is_async: sig.is_async,
            params: ps,
            result: ir_opt_to_model(sig.result),
          }),
        )
      }
      Some(Record(fields)) => {
        let fs : Array[@model.RecordField] = []
        for f in fields {
          fs.push({ label: f.name, ty: ir_valty_to_model(f.ty), })
        }
        Some(@model.Record(fs))
      }
      Some(List(t)) => Some(@model.List(ir_valty_to_model(t)))
      Some(FixedList(t, n)) => Some(@model.FixedList(ir_valty_to_model(t), n))
      Some(MapType(k, v)) =>
        Some(@model.MapType(ir_valty_to_model(k), ir_valty_to_model(v)))
      Some(Tuple(ts)) => {
        let xs : Array[@model.ValType] = []
        for x in ts {
          xs.push(ir_valty_to_model(x))
        }
        Some(@model.Tuple(xs))
      }
      Some(Option(t)) => Some(@model.Option(ir_valty_to_model(t)))
      Some(Result(ok, err)) =>
        Some(@model.Result(ir_opt_to_model(ok), ir_opt_to_model(err)))
      Some(Variant(cases)) => {
        let cs : Array[@model.VariantCase] = []
        for c in cases {
          cs.push({
            label: c.label,
            ty: ir_opt_to_model(c.payload),
            refines: None,
          })
        }
        Some(@model.Variant(cs))
      }
      Some(Flags(names)) => Some(@model.Flags(names.copy()))
      Some(Enum(names)) => Some(@model.Enum(names.copy()))
      Some(Own(i)) => Some(@model.Own(i))
      Some(Borrow(i)) => Some(@model.Borrow(i))
      Some(Future(t)) => Some(@model.Future(ir_opt_to_model(t)))
      Some(Stream(t)) => Some(@model.Stream(ir_opt_to_model(t)))
      Some(Resource) => None
    }
    out.push(d)
  }
  out
}

///|
/// Flatten one value type to its core Wasm value types, e.g. `string` -> i32,i32.
/// Returns `None` when the type cannot be flattened (recursive / unsupported).
pub fn flatten(t : ValTy, types : Array[TypeDef?]) -> Array[@core.ValueType]? {
  @wasm_component.canonical_flat_types(
    ir_valty_to_model(t),
    to_model_table(types),
    @core.I32,
  )
}

///|
/// Flatten a whole signature, per upstream canonical ABI. `None` if any part
/// cannot be flattened.
pub fn flatten_func(
  sig : FuncSig,
  types : Array[TypeDef?],
) -> (Array[@core.ValueType], Array[@core.ValueType])? {
  let table = to_model_table(types)
  let params : Array[@core.ValueType] = []
  for p in sig.params {
    match
      @wasm_component.canonical_flat_types(
        ir_valty_to_model(p.ty),
        table,
        @core.I32,
      ) {
      Some(flat) =>
        for v in flat {
          params.push(v)
        }
      None => return None
    }
  }
  let results : Array[@core.ValueType] = []
  match sig.result {
    Some(r) =>
      match
        @wasm_component.canonical_flat_types(
          ir_valty_to_model(r),
          table,
          @core.I32,
        ) {
        Some(flat) =>
          for v in flat {
            results.push(v)
          }
        None => return None
      }
    None => ()
  }
  Some((params, results))
}
