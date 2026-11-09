// Previous linear resolver retained as an independent diagnostic oracle.

///|
fn scan_resolve_port(
  iface : @ir.Iface,
  side : Side,
  port_path : String,
) -> @ir.FuncSig raise PlanError {
  let table = match side {
    ExportSide => iface.exports
    ImportSide => iface.imports
  }
  // Try the full path first: it may name an interface directly, or a plain func.
  // Paths are `iface.func` or `func`.
  let segments = port_path.split(".").to_array()
  let dot = if segments.length() < 2 { -1 } else { segments[0].length() }
  if dot < 0 {
    // Plain function name.
    for e in table {
      if @ir.cmp_str(e.name, port_path) == 0 {
        match e.port {
          @ir.Func(sig) => return sig
          @ir.Interface(_, _) =>
            raise PortKindMismatch(
              iface.name,
              port_path,
              "an interface, not a function",
            )
        }
      }
    }
    raise UnknownPort(iface.name, port_path)
  }
  let iface_name = port_path[:dot].to_owned()
  let func_name = port_path[dot + 1:].to_owned()
  for e in table {
    if @ir.cmp_str(e.name, iface_name) == 0 {
      match e.port {
        @ir.Interface(_, funcs) => {
          for f in funcs {
            if @ir.cmp_str(f.name, func_name) == 0 {
              return f
            }
          }
          raise UnknownPort(iface.name, "\{iface_name}.\{func_name}")
        }
        @ir.Func(_) =>
          raise PortKindMismatch(
            iface.name,
            iface_name,
            "a function, not an interface",
          )
      }
    }
  }
  raise UnknownPort(iface.name, iface_name)
}
