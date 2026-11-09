// Port addressing and supplementary canonical ABI checks.
//
// A wire endpoint is `<component>.<port>` where `<port>` is either a plain
// function name (`f`) or an interface path (`iface.f`). This module resolves
// that path against an `Iface` and flattens the resulting signature through the
// canonical ABI.

///|
/// Which side of a component a port lives on. Used only in error text.
pub(all) enum Side {
  ExportSide
  ImportSide
}

///|
/// Resolve a port path against an interface's export or import table.
/// Returns the resolved `FuncSig`, or a structured error naming the component,
/// the path, and the reason.
pub fn resolve_port(
  iface : @ir.Iface,
  side : Side,
  port_path : String,
) -> @ir.FuncSig raise PlanError {
  let table = match side {
    ExportSide => iface.exports
    ImportSide => iface.imports
  }
  resolve_port_using(iface.name, port_path, fn(name) {
    for entry in table {
      if @ir.cmp_str(entry.name, name) == 0 {
        return Some(entry.port)
      }
    }
    None
  })
}

///|
fn resolve_port_using(
  component : String,
  port_path : String,
  lookup : (String) -> @ir.Port?,
) -> @ir.FuncSig raise PlanError {
  let segments = port_path.split(".").to_array()
  if segments.length() < 2 {
    match lookup(port_path) {
      Some(@ir.Func(sig)) => return sig
      Some(@ir.Interface(_, _)) =>
        raise PortKindMismatch(
          component, port_path, "an interface, not a function",
        )
      None => raise UnknownPort(component, port_path)
    }
  }
  let dot = segments[0].length()
  let name = port_path[:dot].to_owned()
  let function = port_path[dot + 1:].to_owned()
  match lookup(name) {
    Some(@ir.Interface(_, funcs)) => {
      for f in funcs {
        if @ir.cmp_str(f.name, function) == 0 {
          return f
        }
      }
      raise UnknownPort(component, "\{name}.\{function}")
    }
    Some(@ir.Func(_)) =>
      raise PortKindMismatch(component, name, "a function, not an interface")
    None => raise UnknownPort(component, name)
  }
}

///|
// Index only wide tables, lazily and within a single plan invocation. Small
// tables retain the linear resolver, avoiding per-instance map allocations.
fn resolve_indexed_port(
  iface : @ir.Iface,
  handle : String,
  side : Side,
  port : String,
  cache : Map[(String, Bool), Map[String, @ir.Port]],
) -> @ir.FuncSig raise PlanError {
  let table = match side {
    ExportSide => iface.exports
    ImportSide => iface.imports
  }
  if table.length() < 16 {
    return resolve_port(iface, side, port)
  }
  let key = (handle, side is ImportSide)
  let index = match cache.get(key) {
    Some(index) => index
    None => {
      let index : Map[String, @ir.Port] = Map([])
      // Public IR may contain duplicates: linear lookup chooses the first.
      for entry in table {
        if !index.contains(entry.name) {
          index.set(entry.name, entry.port)
        }
      }
      cache.set(key, index)
      index
    }
  }
  resolve_port_using(iface.name, port, name => index.get(name))
}

///|

///|
/// Core value type name, e.g. `i32`. Used for plan output.
fn core_name(t : @core.ValueType) -> String {
  match t {
    @core.I32 => "i32"
    @core.I64 => "i64"
    @core.F32 => "f32"
    @core.F64 => "f64"
    @core.V128 => "v128"
    _ => "other"
  }
}

///|
fn core_names(xs : Array[@core.ValueType]) -> Array[String] {
  let out : Array[String] = []
  for x in xs {
    out.push(core_name(x))
  }
  out
}

///|
/// A flattened signature in a plan-friendly form.
pub(all) struct FlatSig {
  params : Array[String]
  results : Array[String]
}

///|
/// Reject unsupported function/value semantics, then flatten via canonical ABI.
/// Structural wire compatibility is checked separately before this step.
pub fn flatten_sig(
  comp : String,
  port : String,
  sig : @ir.FuncSig,
  types : Array[@ir.TypeDef?],
) -> FlatSig raise PlanError {
  check_supported_func(comp, port, sig, types)
  match @ir.flatten_func(sig, types) {
    Some((params, results)) =>
      { params: core_names(params), results: core_names(results), }
    None => raise Unflattenable(comp, port)
  }
}

///|
/// Supplementary core-ABI equality check only. Equal flat signatures do not
/// establish component-value compatibility; plan() checks semantics first.
pub fn check_wire_signatures(
  from_comp : String,
  from_port : String,
  from_side : FlatSig,
  to_comp : String,
  to_port : String,
  to_side : FlatSig,
) -> Unit raise PlanError {
  let mut detail = ""
  if from_side.params.length() != to_side.params.length() {
    detail = "parameter arity \{from_side.params.length()} vs \{to_side.params.length()}"
  } else if from_side.results.length() != to_side.results.length() {
    detail = "result arity \{from_side.results.length()} vs \{to_side.results.length()}"
  } else {
    let mut i = 0
    while i < from_side.params.length() {
      if from_side.params[i] != to_side.params[i] {
        detail = "parameter \{i}: \{from_side.params[i]} vs \{to_side.params[i]}"
        break
      }
      i = i + 1
    }
    if detail == "" {
      let mut j = 0
      while j < from_side.results.length() {
        if from_side.results[j] != to_side.results[j] {
          detail = "result \{j}: \{from_side.results[j]} vs \{to_side.results[j]}"
          break
        }
        j = j + 1
      }
    }
  }
  if detail != "" {
    raise SignatureMismatch(from_comp, from_port, to_comp, to_port, detail)
  }
}

///|
/// Render a flat signature as `(i32, i32) -> (i32)`, for plan output.
pub fn render_flat(f : FlatSig) -> String {
  "(" + f.params.join(", ") + ") -> (" + f.results.join(", ") + ")"
}
