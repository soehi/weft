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
fn fail(msg : String) -> CmdResult {
  { ok: false, text: msg }
}

///|
fn succeed(text : String) -> CmdResult {
  { ok: true, text }
}

///|
/// Load a manifest from JSON text and decode each component binary.
pub fn load_plan_input(
  manifest_text : String,
  binaries : Map[String, Bytes],
) -> @plan.Input raise @plan.PlanError {
  let m = @manifest.parse(manifest_text) catch {
    e => raise @plan.InvalidManifest(e.to_string())
  }
  let ifaces : Map[String, @ir.Iface] = Map([])
  for c in m.components {
    match binaries.get(c.name) {
      Some(bytes) =>
        ifaces.set(
          c.name,
          @ir.decode_component(c.name, c.path, bytes) catch {
            e => raise @plan.InvalidManifest(e.to_string())
          },
        )
      None =>
        raise @plan.InvalidManifest(
          "no binary supplied for component `\{c.name}` (path \{c.path})",
        )
    }
  }
  { manifest: m, ifaces }
}

///|
/// `plan`: parse, decode, plan, render JSON.
pub fn cmd_plan(manifest_text : String, binaries : Map[String, Bytes]) -> CmdResult {
  let input = load_plan_input(manifest_text, binaries) catch {
    e => {
      return fail(e.to_string())
    }
  }
  let p = @plan.plan(input) catch {
    e => {
      return fail(e.to_string())
    }
  }
  succeed(@plan.plan_json(p))
}

///|
/// `emit-wac`: parse the manifest and render WAC (no binaries needed).
pub fn cmd_emit_wac(manifest_text : String) -> CmdResult {
  let m = @manifest.parse(manifest_text) catch {
    e => {
      return fail(e.to_string())
    }
  }
  succeed(@wac.manifest_to_wac(m))
}

///|
/// `convert`: verify a WAC file against supplied component binaries and emit a
/// manifest JSON.
pub fn cmd_convert(wac_text : String, deps : Array[(String, Bytes)]) -> CmdResult {
  let wdeps : Array[@wac.WacDep] = []
  for (name, bytes) in deps {
    // The dep spec is `ns:name=path`; the path half is only used for the
    // emitted manifest's `path` field. The caller passes name and bytes, and
    // we synthesize a readable path from the name.
    wdeps.push({ name, version: None, path: "\{name}.wasm", bytes })
  }
  let m = @wac.wac_to_manifest(wac_text, wdeps) catch {
    e => {
      return fail(e.to_string())
    }
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