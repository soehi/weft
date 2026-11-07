// Strict component-value compatibility. Canonical ABI equality is a separate
// supplementary check; an i32 can represent many incompatible component types.

///|
priv struct ValueShape {
  kind : String
  members : Array[(String, @ir.ValTy?)]
}

///|
fn value_shape(
  comp : String,
  port : String,
  path : String,
  ty : @ir.ValTy,
  types : Array[@ir.TypeDef?],
) -> ValueShape raise PlanError {
  let scalar = match ty {
    @ir.Bool => "bool"
    @ir.S8 => "s8"
    @ir.U8 => "u8"
    @ir.S16 => "s16"
    @ir.U16 => "u16"
    @ir.S32 => "s32"
    @ir.U32 => "u32"
    @ir.S64 => "s64"
    @ir.U64 => "u64"
    @ir.F32 => "f32"
    @ir.F64 => "f64"
    @ir.Char => "char"
    @ir.String => "string"
    @ir.ErrorContext => raise Unsupported(comp, port, "\{path}: error-context")
    @ir.Index(_) => ""
  }
  if scalar != "" {
    return { kind: scalar, members: [], }
  }
  guard ty is @ir.Index(i) else { abort("indexed value expected") }
  if i < 0 || i >= types.length() {
    raise Unsupported(comp, port, "\{path}: invalid value type index \{i}")
  }
  match types[i] {
    Some(@ir.Record(fields)) => {
      let members = fields.map(f => (".field(" + q(f.name) + ")", Some(f.ty)))
      { kind: "record", members, }
    }
    Some(@ir.Tuple(xs)) => {
      let members : Array[(String, @ir.ValTy?)] = []
      for i = 0; i < xs.length(); i = i + 1 {
        members.push((".tuple[\{i}]", Some(xs[i])))
      }
      { kind: "tuple", members, }
    }
    Some(@ir.List(t)) => { kind: "list", members: [(".element", Some(t))], }
    Some(@ir.Option(t)) => { kind: "option", members: [(".some", Some(t))], }
    Some(@ir.Result(ok, err)) =>
      { kind: "result", members: [(".ok", ok), (".err", err)], }
    Some(@ir.Variant(cases)) => {
      let members = cases.map(c => (".case(" + q(c.label) + ")", c.payload))
      { kind: "variant", members, }
    }
    Some(@ir.Flags(names)) =>
      { kind: "flags", members: names.map(n => (".flag(" + q(n) + ")", None)), }
    Some(@ir.Enum(names)) =>
      { kind: "enum", members: names.map(n => (".case(" + q(n) + ")", None)), }
    Some(@ir.Own(_)) => raise Unsupported(comp, port, "\{path}: own")
    Some(@ir.Borrow(_)) => raise Unsupported(comp, port, "\{path}: borrow")
    Some(@ir.Resource) => raise Unsupported(comp, port, "\{path}: resource")
    Some(@ir.Future(_)) => raise Unsupported(comp, port, "\{path}: future")
    Some(@ir.Stream(_)) => raise Unsupported(comp, port, "\{path}: stream")
    Some(@ir.FixedList(_, _)) =>
      raise Unsupported(comp, port, "\{path}: fixed-list")
    Some(@ir.MapType(_, _)) => raise Unsupported(comp, port, "\{path}: map")
    Some(@ir.Func(_)) =>
      raise Unsupported(comp, port, "\{path}: function used as a value")
    None =>
      raise Unsupported(comp, port, "\{path}: unresolved value type index \{i}")
  }
}

///|
// Explicit DFS stack: shared types are checked once, cycles fail before ABI
// flattening. Both the type index and the visitation state are component-local.
fn check_supported_func(
  comp : String,
  port : String,
  sig : @ir.FuncSig,
  types : Array[@ir.TypeDef?],
) -> Unit raise PlanError {
  if sig.is_async {
    raise Unsupported(comp, port, "async function")
  }
  let work : Array[(@ir.ValTy, String, Bool)] = []
  match sig.result {
    Some(t) => work.push((t, "result", false))
    None => ()
  }
  for i = sig.params.length() - 1; i >= 0; i = i - 1 {
    work.push((sig.params[i].ty, "parameter \{i}", false))
  }
  let visited : Map[Int32, Bool] = Map([])
  while work.pop() is Some((ty, path, exiting)) {
    if ty is @ir.Index(i) {
      if exiting {
        visited.set(i, false)
        continue
      }
      match visited.get(i) {
        Some(true) =>
          raise Unsupported(comp, port, "\{path}: recursive value type")
        Some(false) => continue
        None => ()
      }
      visited.set(i, true)
      work.push((ty, path, true))
    }
    let shape = value_shape(comp, port, path, ty, types)
    for i = shape.members.length() - 1; i >= 0; i = i - 1 {
      let (suffix, value) = shape.members[i]
      if value is Some(t) {
        work.push((t, path + suffix, false))
      }
    }
  }
}

///|
fn check_wire_value_types(
  from_iface : @ir.Iface,
  from_port : String,
  a : @ir.FuncSig,
  to_iface : @ir.Iface,
  to_port : String,
  b : @ir.FuncSig,
) -> Unit raise PlanError {
  check_supported_func(from_iface.name, from_port, a, from_iface.types)
  check_supported_func(to_iface.name, to_port, b, to_iface.types)
  let work : Array[(@ir.ValTy?, @ir.ValTy?, String)] = []
  if a.params.length() != b.params.length() {
    raise SignatureMismatch(
      from_iface.name,
      from_port,
      to_iface.name,
      to_port,
      "parameter arity \{a.params.length()} vs \{b.params.length()}",
    )
  }
  if (a.result is Some(_)) != (b.result is Some(_)) {
    let ac = if a.result is Some(_) { 1 } else { 0 }
    let bc = if b.result is Some(_) { 1 } else { 0 }
    raise SignatureMismatch(
      from_iface.name,
      from_port,
      to_iface.name,
      to_port,
      "result arity \{ac} vs \{bc}",
    )
  }
  for i = 0; i < a.params.length(); i = i + 1 {
    if a.params[i].name != b.params[i].name {
      raise SignatureMismatch(
        from_iface.name,
        from_port,
        to_iface.name,
        to_port,
        "parameter \{i} name: \{q(a.params[i].name)} vs \{q(b.params[i].name)}",
      )
    }
  }
  work.push((a.result, b.result, "result"))
  for i = a.params.length() - 1; i >= 0; i = i - 1 {
    work.push((Some(a.params[i].ty), Some(b.params[i].ty), "parameter \{i}"))
  }
  let seen : Map[(Int32, Int32), Unit] = Map([])
  while work.pop() is Some((a, b, path)) {
    let mut detail = ""
    match (a, b) {
      (None, None) => continue
      (Some(a), Some(b)) => {
        if a is @ir.Index(ai) && b is @ir.Index(bi) {
          if seen.contains((ai, bi)) {
            continue
          }
          seen.set((ai, bi), ())
        }
        let ashape = value_shape(
          from_iface.name,
          from_port,
          path,
          a,
          from_iface.types,
        )
        let bshape = value_shape(
          to_iface.name,
          to_port,
          path,
          b,
          to_iface.types,
        )
        if ashape.kind != bshape.kind {
          detail = "\{path}: \{ashape.kind} vs \{bshape.kind}"
        } else if ashape.members.length() != bshape.members.length() {
          detail = "\{path}: \{ashape.kind} member count \{ashape.members.length()} vs \{bshape.members.length()}"
        } else {
          for i = 0; i < ashape.members.length(); i = i + 1 {
            if ashape.members[i].0 != bshape.members[i].0 {
              detail = "\{path}: ordered \{ashape.kind} member \{i}: \{ashape.members[i].0} vs \{bshape.members[i].0}"
              break
            }
          }
          if detail == "" {
            for i = ashape.members.length() - 1; i >= 0; i = i - 1 {
              work.push(
                (
                  ashape.members[i].1,
                  bshape.members[i].1,
                  path + ashape.members[i].0,
                ),
              )
            }
          }
        }
      }
      _ => detail = "\{path}: payload presence differs"
    }
    if detail != "" {
      raise SignatureMismatch(
        from_iface.name,
        from_port,
        to_iface.name,
        to_port,
        detail,
      )
    }
  }
}
