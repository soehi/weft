///|
fn prepare(source : String, binaries : Map[String, Bytes]) -> (Manifest, Array[@ir.Component]) raise InputError {
  let m = parse(source)
  let declarations = m.components.copy()
  declarations.sort_by((a, b) => @order.cmp_str(a.name, b.name))
  let names : Map[String, Unit] = Map([])
  for c in declarations { names.set(c.name, ()) }
  let extra = binaries.keys().filter(n => !names.contains(n)).to_array()
  extra.sort_by(@order.cmp_str)
  if !extra.is_empty() { reject("UNEXPECTED_BINARY", extra[0], [], "binary is not a declared component") }
  let components : Array[@ir.Component] = []
  for c in declarations {
    let bytes = match binaries.get(c.name) {
      Some(bytes) => bytes
      None => { reject("MISSING_BINARY", c.name, [], "component bytes not supplied"); abort("unreachable") }
    }
    let decoded = @ir.decode(c.name, bytes) catch {
      @ir.InvalidComponent(name, detail) => {
        reject("DECODE_FAILED", name, [], detail)
        abort("unreachable")
      }
    }
    components.push(decoded)
  }
  (m, components)
}

///|
pub fn compile(source : String, binaries : Map[String, Bytes]) -> Result[Output, @types.Diagnostic] {
  try {
    let (m, components) = prepare(source, binaries)
    let p = @plan.plan(components, m.bindings) catch {
      @plan.Rejected(d) => raise Rejected(d)
    }
    Ok({ manifest: m, plan: p, json: encode(m, p) })
  } catch { Rejected(d) => Err(d) }
}

///|
pub fn emit_wac(source : String, binaries : Map[String, Bytes]) -> Result[String, @types.Diagnostic] {
  try {
    let (m, components) = prepare(source, binaries)
    let text = @plan.emit_wac(components, m.bindings) catch {
      @plan.Rejected(d) => raise Rejected(d)
    }
    Ok(text)
  } catch { Rejected(d) => Err(d) }
}
