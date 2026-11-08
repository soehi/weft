// Subcommand implementations. Backend-agnostic: they take already-read strings
// and bytes, so native and wasm/js entry points differ only in how they acquire
// input and emit output.

///|
/// Result of a pure subcommand: either text to print, or an error message.
pub(all) struct CmdResult {
  ok : Bool
  text : String
}

///|
fn fail_command(msg : String) -> CmdResult {
  { ok: false, text: msg, }
}

///|
fn succeed(text : String) -> CmdResult {
  { ok: true, text, }
}

///|
/// Load a manifest from JSON text and decode each component binary.
pub fn load_plan_input(
  manifest_text : String,
  binaries : Map[String, Bytes],
) -> @plan.Input raise @plan.PlanError {
  match @api.load_input(manifest_text, binaries) {
    Ok(input) => input
    Err(d) => raise @plan.InvalidManifest(d.message)
  }
}

///|
/// The CLI shares the exact compiler and canonical emitter with embedders.
pub fn cmd_plan(
  manifest_text : String,
  binaries : Map[String, Bytes],
) -> CmdResult {
  match @api.compile(manifest_text, binaries) {
    Ok(output) => succeed(output.json)
    Err(d) => fail_command(d.message)
  }
}

///|
/// `emit-wac`: parse the manifest and render WAC (no binaries needed).
pub fn cmd_emit_wac(manifest_text : String) -> CmdResult {
  let m = @manifest.parse(manifest_text) catch {
    e => return fail_command(e.to_string())
  }
  let text = @wac.manifest_to_wac(m) catch {
    e => return fail_command(e.to_string())
  }
  succeed(text)
}

///|
/// `convert`: verify a WAC file against supplied component binaries and emit a
/// manifest JSON.
pub fn cmd_convert(wac_text : String, deps : Array[@wac.WacDep]) -> CmdResult {
  let m = @wac.wac_to_manifest(wac_text, deps) catch {
    e => return fail_command(e.to_string())
  }
  succeed(manifest_json(m))
}

///|
/// Serialize a manifest back to JSON in the same shape the parser accepts.
pub fn manifest_json(m : @manifest.Manifest) -> String {
  let comps : Array[String] = []
  for c in m.components {
    comps.push(
      "{\"name\":" + quote(c.name) + ",\"path\":" + quote(c.path) + "}",
    )
  }
  let wires : Array[String] = []
  for w in m.wires {
    wires.push(
      "{\"from\":" +
      quote("\{w.from_component}.\{w.from_port}") +
      ",\"to\":" +
      quote("\{w.to_component}.\{w.to_port}") +
      "}",
    )
  }
  let res = match (m.resources.max_memory_pages, m.resources.quota) {
    (None, None) => ""
    (a, b) => {
      let parts : Array[String] = []
      match a {
        Some(n) => parts.push("\"max_memory_pages\":" + n.to_string())
        None => ()
      }
      match b {
        Some(n) => parts.push("\"quota\":" + n.to_string())
        None => ()
      }
      ",\"resources\":{" + parts.join(",") + "}"
    }
  }
  "{\"version\":" +
  quote(m.version) +
  ",\"components\":[" +
  comps.join(",") +
  "],\"wires\":[" +
  wires.join(",") +
  "]" +
  res +
  "}"
}

///|
fn quote(s : String) -> String {
  @json.to_json(s).stringify()
}
