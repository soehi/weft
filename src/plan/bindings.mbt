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
    // Merge all imports for deterministic name ordering, including previously
    // unrepresentable type/value/module/component imports.
    let names = iface.unwireable_imports.copy()
    for entry in iface.imports {
      names.push(entry.name)
    }
    names.sort_by(@ir.cmp_str)
    for name in names {
      if iface.unwireable_imports.contains(name) {
        raise Unsupported(
          c.name,
          name,
          "non-function import cannot be bound by function wires",
        )
      }
      for entry in iface.imports {
        if entry.name == name {
          match entry.port {
            @ir.Func(_) =>
              if !providers.contains((c.name, name)) {
                raise UnboundImport(c.name, name)
              }
            @ir.Interface(_, _) =>
              raise Unsupported(
                c.name,
                name,
                "interface instance imports require whole-instance binding",
              )
          }
        }
      }
    }
  }
}
