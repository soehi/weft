///|
fn quote(s : String) -> String { @json.to_json(s).stringify(escape_slash=false) }

///|
fn error(code : String, component : String, path : Array[String], message : String) -> String {
  "{\"ok\":false,\"diagnostic\":{\"code\":" + quote(code) + ",\"component\":" + quote(component) + ",\"path\":[" + path.map(quote).join(",") + "],\"message\":" + quote(message) + "}}"
}

///|
/// Exact logical IDs and immutable byte arrays; no filesystem or execution.
pub fn seal_json(manifest : String, components : String) -> String {
  let input = @json.parse(components, reject_duplicate_keys=true) catch {
    _ => return error("BROWSER_INPUT", "", [], "invalid component byte mapping")
  }
  guard input is @json.Object(entries) else { return error("BROWSER_INPUT", "", [], "expected component byte object") }
  let binaries : Map[String, Bytes] = Map([])
  for (id, value) in entries {
    guard value is @json.Array(values) else { return error("BROWSER_INPUT", id, [], "expected byte array") }
    let bytes : Array[Byte] = []
    for j in 0..<values.length() {
      guard values[j] is @json.Number(n, ..) && n >= 0.0 && n <= 255.0 && n.to_int().to_double() == n else {
        return error("BROWSER_INPUT", id, ["\{j}"], "invalid byte")
      }
      bytes.push(n.to_int().to_byte())
    }
    binaries.set(id, Bytes::from_array(bytes))
  }
  match @compose.seal(manifest, binaries) {
    Ok(bundle) => "{\"ok\":true,\"plan_json\":" + quote(bundle.plan_text) + ",\"lock_json\":" + quote(bundle.lock_text) + "}"
    Err(d) => error(d.code, d.component, d.path, d.detail)
  }
}
