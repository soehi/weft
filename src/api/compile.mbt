///|
/// Parse and decode memory-owned inputs. Extra binary entries are ignored;
/// every declared component must have an entry keyed by its exact name.
/// Paths are labels only: the API never reads them or inspects the environment.
pub fn load_input(
  manifest_text : String,
  binaries : Map[String, Bytes],
) -> Result[@plan.Input, Diagnostic] {
  let m = @manifest.parse(manifest_text) catch {
    e => return Err(manifest_diagnostic(e))
  }
  let components = m.components.copy()
  components.sort_by(fn(a, b) { @ir.cmp_str(a.name, b.name) })
  let ifaces : Map[String, @ir.Iface] = Map([])
  for c in components {
    let bytes = match binaries.get(c.name) {
      Some(bytes) => bytes
      None =>
        return Err(
          diagnostic(
            "INPUT_MISSING_BINARY",
            "input",
            "no binary supplied for component `\{c.name}` (path \{c.path})",
            component=Some(c.name),
            field=Some("components.path"),
            detail=Some(c.path),
          ),
        )
    }
    let iface = @ir.decode_component(c.name, c.path, bytes) catch {
      @ir.DecodeFailed(comp, detail) =>
        return Err(
          diagnostic(
            "COMPONENT_DECODE",
            "decode",
            @ir.DecodeFailed(comp, detail).to_string(),
            component=Some(comp),
            detail=Some(detail),
          ),
        )
      @ir.UnsupportedType(comp) =>
        return Err(
          diagnostic(
            "COMPONENT_UNSUPPORTED_TYPE",
            "decode",
            @ir.UnsupportedType(comp).to_string(),
            component=Some(comp),
          ),
        )
    }
    ifaces.set(c.name, iface)
  }
  Ok({ manifest: m, ifaces, })
}

///|
/// Compile a complete deployment plan using only supplied strings and bytes.
/// Returns the first structured diagnostic. Never executes components.
pub fn compile(
  manifest_text : String,
  binaries : Map[String, Bytes],
) -> Result[Output, Diagnostic] {
  let input = match load_input(manifest_text, binaries) {
    Ok(input) => input
    Err(d) => return Err(d)
  }
  let p = @plan.plan(input) catch { e => return Err(plan_diagnostic(e)) }
  Ok({ plan: p, json: @plan.plan_json(p), })
}
