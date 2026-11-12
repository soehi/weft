///|
fn kebab(name : String) -> Bool {
  let mut start = true
  for c in name {
    if c == '-' {
      if start { return false }
      start = true
    } else if c >= 'a' && c <= 'z' {
      start = false
    } else if c >= '0' && c <= '9' && !start { () } else { return false }
  }
  !start
}

///|
fn quoted(s : String) -> String {
  @json.to_json(s).stringify(escape_slash=false)
}

///|
// Only called with a freshly checked composition; external plans require D2
// verification before they can be treated as trusted composition intent.
fn render_wac(p : Plan) -> String raise PlanError {
  for name in p.order {
    if !kebab(name) { reject("WAC_UNREPRESENTABLE", name, [], "component is not a lowercase kebab name") }
  }
  let out = StringBuilder()
  out.write_string("package weft:composition;\n\n")
  for name in p.order {
    let args : Array[String] = []
    for checked in p.bindings {
      let b = checked.binding
      if b.to.component != name { continue }
      for port in [Some(b.from.port), b.from.member_name, Some(b.to.port)] {
        if port is Some(s) && !kebab(s) {
          reject("WAC_UNREPRESENTABLE", name, [s], "port is not a lowercase kebab name")
        }
      }
      let mut value = "c-" + b.from.component + "[" + quoted(b.from.port) + "]"
      if b.from.member_name is Some(member_name) { value = value + "[" + quoted(member_name) + "]" }
      args.push(quoted(b.to.port) + ": " + value)
    }
    let body = if args.is_empty() { " {}" } else { " { " + args.join(", ") + " }" }
    out.write_string("let c-" + name + " = new weft:" + name + body + ";\n")
  }
  out.write_string("\n")
  for name in p.order { out.write_string("export c-" + name + " as " + quoted(name) + ";\n") }
  out.to_string()
}

///|
/// Emit the same checked instance/function bindings as a WAC composition.
pub fn emit_wac(components : Array[@ir.Component], bindings : Array[Binding]) -> String raise PlanError {
  render_wac(plan(components, bindings))
}
