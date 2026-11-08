// A deliberately strict, lossless subset of manifest -> WAC. Unsupported
// names/paths or resource metadata fail explicitly instead of being sanitized.

///|
fn safe_name(name : String) -> Bool {
  let mut start = true
  for c in name {
    if c == '-' {
      if start {
        return false
      }
      start = true
    } else if c >= 'a' && c <= 'z' {
      start = false
    } else if c >= '0' && c <= '9' && !start {
      ()
    } else {
      return false
    }
  }
  !start
}

///|
fn require_name(name : String, context : String) -> Unit raise WacError {
  if !safe_name(name) {
    raise Unsupported(
      "\{context} `\{name}` is not a lowercase kebab name; interface paths and escaped names cannot be emitted",
    )
  }
}

///|
/// Injective identifiers with a non-keyword prefix. Package references retain
/// the original validated name: the dependency is always weft:<component>.
pub fn instance_name(comp : String) -> String {
  "c-" + comp
}

///|
pub fn manifest_to_wac(m : @manifest.Manifest) -> String raise WacError {
  if m.resources.max_memory_pages is Some(_) || m.resources.quota is Some(_) {
    raise Unsupported(
      "WAC cannot preserve resource limits; remove them explicitly before emitting",
    )
  }
  let g = @graph.build_graph(m) catch {
    @graph.UnknownComponent(n) => raise Unsupported("unknown component `\{n}`")
    @graph.InvalidManifest(msg) => raise Unsupported(msg)
    @graph.Cycle(names) =>
      raise Unsupported("dependency cycle: " + names.join(" -> "))
  }
  @graph.check_acyclic(g) catch {
    @graph.Cycle(names) =>
      raise Unsupported("dependency cycle: " + names.join(" -> "))
    _ => raise Unsupported("invalid dependency graph")
  }
  for name in g.nodes {
    require_name(name, "component")
  }
  let wires = m.wires.copy()
  wires.sort_by(fn(a, b) {
    let akey = [a.to_component, a.to_port, a.from_component, a.from_port]
    let bkey = [b.to_component, b.to_port, b.from_component, b.from_port]
    for i = 0; i < 4; i = i + 1 {
      let c = @ir.cmp_str(akey[i], bkey[i])
      if c != 0 {
        return c
      }
    }
    0
  })
  let seen : Map[(String, String), Unit] = Map([])
  for w in wires {
    require_name(w.from_port, "source port on " + w.from_component)
    require_name(w.to_port, "target port on " + w.to_component)
    let key = (w.to_component, w.to_port)
    if seen.contains(key) {
      raise Unsupported(
        "duplicate binding for `\{w.to_component}.\{w.to_port}`",
      )
    }
    seen.set(key, ())
  }
  let sb = StringBuilder()
  sb.write_string("package weft:generated;\n\n")
  for idx in @graph.topo_order(g) {
    let name = g.nodes[idx]
    let args : Array[String] = []
    for w in wires {
      if w.to_component == name {
        args.push(
          "\"\{w.to_port}\": \{instance_name(w.from_component)}[\"\{w.from_port}\"]",
        )
      }
    }
    let body = if args.length() == 0 {
      " {}"
    } else {
      " { " + args.join(", ") + " }"
    }
    sb.write_string("let \{instance_name(name)} = new weft:\{name}\{body};\n")
  }
  sb.write_string("\n")
  for name in g.nodes {
    sb.write_string("export \{instance_name(name)} as \"\{name}\";\n")
  }
  sb.to_string()
}
