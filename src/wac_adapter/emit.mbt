// Manifest -> WAC text.
//
// This is the documented fallback path: if the native execution adapter is not
// available, a plan can still be turned into standard WAC and handed to an
// external `wasm-tools compose` / `wasmtime`. It is also what makes "plan ->
// executable artifact" a closed loop without our own runtime.
//
// The emitted WAC only instantiates each component once and wires exports to
// imports. It deliberately does not attempt renames or spreads.

///|
/// Quote a WAC identifier if it contains characters outside `[A-Za-z0-9_-]`.
/// WAC accepts string-literal names in most positions, so we always quote
/// export names to be safe.
fn wac_name(s : String) -> String {
  "\"" + s + "\""
}

///|
/// Render a manifest as a WAC package. The package name defaults to
/// `weft:generated`; component packages are
/// `weft:<name>`.
pub fn manifest_to_wac(m : @manifest.Manifest) -> String {
  let sb = StringBuilder()
  sb.write_string("package weft:generated;\n\n")
  // Declare one external package per component and instantiate each.
  let mut i = 0
  for c in m.components {
    sb.write_string("// component \{c.name} (artifact: \{c.path})\n")
    i = i + 1
  }
  sb.write_string("\n")
  for c in m.components {
    // Arguments: every wire whose destination is this component contributes a
    // named argument bound to the source instance's export.
    let args : Array[String] = []
    for w in m.wires {
      if w.to_component == c.name {
        args.push("\{w.to_port}: \{instance_name(w.from_component)}.\{w.from_port}")
      }
    }
    // WAC requires a body for `new`, even when empty.
    let arg_text = if args.length() == 0 {
      " {}"
    } else {
      " { " + args.join(", ") + " }"
    }
    sb.write_string(
      "let \{instance_name(c.name)} = new weft:\{instance_name(c.name)}\{arg_text};\n",
    )
  }
  sb.write_string("\n")
  for c in m.components {
    sb.write_string(
      "export \{instance_name(c.name)} as \{wac_name(c.name)};\n",
    )
  }
  sb.to_string()
}

///|
/// Instance identifiers must be valid WAC names. Component names already are
/// (manifest parser permits arbitrary names but the graph rejects duplicates);
/// we sanitize dots because `.` is the access operator in WAC.
pub fn instance_name(comp : String) -> String {
  let sb = StringBuilder()
  for c in comp {
    if c == '.' || c == ':' || c == '/' || c == '@' {
      sb.write_char('_')
    } else {
      sb.write_char(c)
    }
  }
  sb.to_string()
}