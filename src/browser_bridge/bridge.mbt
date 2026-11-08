///|
fn q(s : String) -> String {
  @json.to_json(s).stringify()
}

///|
fn optional(s : String?) -> String {
  match s {
    Some(s) => q(s)
    None => "null"
  }
}

///|
fn location(l : @api.Location) -> String {
  "{\"component\":" +
  optional(l.component) +
  ",\"port\":" +
  optional(l.port) +
  ",\"field\":" +
  optional(l.field) +
  "}"
}

///|
fn transport_error(msg : String) -> String {
  "{\"ok\":false,\"diagnostic\":{\"code\":\"BROWSER_INPUT\",\"stage\":\"input\",\"message\":" +
  q(msg) +
  ",\"location\":{\"component\":null,\"port\":null,\"field\":null},\"related\":[],\"detail\":null}}"
}

///|
/// Stable JS boundary. Byte object keys are exact component names, never paths.
pub fn compile_json(manifest : String, components : String) -> String {
  let input = @json.parse(components, reject_duplicate_keys=true) catch {
    _ => return transport_error("invalid component byte mapping")
  }
  guard input is Object(entries) else {
    return transport_error("component bytes must be an object")
  }
  let binaries : Map[String, Bytes] = Map([])
  for name, value in entries {
    guard value is Array(values) else {
      return transport_error("bytes for `" + name + "` must be an array")
    }
    let bytes : Array[Byte] = []
    for i = 0; i < values.length(); i = i + 1 {
      guard values[i] is Number(n, ..) else {
        return transport_error("invalid byte")
      }
      if n < 0.0 || n > 255.0 || n != n.to_int().to_double() {
        return transport_error("invalid byte")
      }
      bytes.push(n.to_int().to_byte())
    }
    binaries.set(name, Bytes::from_array(bytes))
  }
  match @api.compile(manifest, binaries) {
    Ok(output) => "{\"ok\":true,\"plan_json\":" + q(output.json) + "}"
    Err(d) => {
      let related = d.related.map(location).join(",")
      "{\"ok\":false,\"diagnostic\":{\"code\":" +
      q(d.code) +
      ",\"stage\":" +
      q(d.stage) +
      ",\"message\":" +
      q(d.message) +
      ",\"location\":" +
      location(d.location) +
      ",\"related\":[" +
      related +
      "],\"detail\":" +
      optional(d.detail) +
      "}}"
    }
  }
}
