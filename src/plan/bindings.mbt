// Complete deployment plans have no implicit host dependencies. Interface
// imports require whole-instance semantics that function wires cannot express.

///|
fn check_bindings(
  input : Input,
  wires : Array[PlannedWire],
) -> Unit raise PlanError {
  let providers : Map[(String, String), String] = Map([])
  // Wires are already sorted, making provider ordering in diagnostics stable.
  for w in wires {
    let key = (w.to_component, w.to_port)
    let provider = "\{w.from_component}.\{w.from_port}"
    match providers.get(key) {
      Some(first) =>
        raise DuplicateBinding(w.to_component, w.to_port, first, provider)
      None => providers.set(key, provider)
    }
  }
  let components = input.manifest.components.copy()
  components.sort_by(fn(a, b) { @ir.cmp_str(a.name, b.name) })
  for c in components {
    let iface = lookup_iface(input, c.name)
    // Sort descriptors once instead of rescanning the entire import table for
    // every name. Ordinals preserve duplicate-entry order in public IR; placing
    // unwireable descriptors first preserves their same-name error precedence.
    let entries : Array[(String, Int32, @ir.Port?)] = []
    for name in iface.unwireable_imports {
      entries.push((name, entries.length(), None))
    }
    for entry in iface.imports {
      entries.push((entry.name, entries.length(), Some(entry.port)))
    }
    entries.sort_by(fn(a, b) {
      let (an, ai, _) = a
      let (bn, bi, _) = b
      let order = @ir.cmp_str(an, bn)
      if order == 0 {
        ai - bi
      } else {
        order
      }
    })
    for (name, _, port) in entries {
      match port {
        None =>
          raise Unsupported(
            c.name,
            name,
            "non-function import cannot be bound by function wires",
          )
        Some(@ir.Func(_)) =>
          if !providers.contains((c.name, name)) {
            raise UnboundImport(c.name, name)
          }
        Some(@ir.Interface(_, _)) =>
          raise Unsupported(
            c.name,
            name,
            "interface instance imports require whole-instance binding",
          )
      }
    }
  }
}
