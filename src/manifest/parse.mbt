// JSON -> Manifest parser. Strict about shape so that malformed manifests fail
// with a located message instead of a downstream null-dereference.

///|
fn json_kind(j : @json.Json) -> String {
  match j {
    Null => "null"
    True | False => "boolean"
    Number(_) => "number"
    String(_) => "string"
    Array(_) => "array"
    Object(_) => "object"
  }
}

///|
fn expect_object(j : @json.Json, loc : String) -> Map[String, @json.Json] raise ManifestError {
  match j {
    Object(m) => m
    _ => raise WrongType(loc, "", "an object, got \{json_kind(j)}")
  }
}

///|
fn expect_string(j : @json.Json, loc : String) -> String raise ManifestError {
  match j {
    String(s) => s
    _ => raise WrongType(loc, "", "a string, got \{json_kind(j)}")
  }
}

///|
fn expect_array(j : @json.Json, loc : String) -> Array[@json.Json] raise ManifestError {
  match j {
    Array(a) => a
    _ => raise WrongType(loc, "", "an array, got \{json_kind(j)}")
  }
}

///|
fn required(m : Map[String, @json.Json], field : String, loc : String) -> @json.Json raise ManifestError {
  match m.get(field) {
    Some(v) => v
    None => raise MissingField(loc, field)
  }
}

///|
fn required_string(m : Map[String, @json.Json], field : String, loc : String) -> String raise ManifestError {
  expect_string(required(m, field, loc), "\{loc}.\{field}")
}

///|
/// Non-negative integer from a JSON number. Rejects fractions and negatives so
/// resource limits cannot silently become floats.
fn optional_nonneg_int(m : Map[String, @json.Json], field : String, loc : String) -> Int? raise ManifestError {
  match m.get(field) {
    None => None
    Some(j) =>
      match j {
        Number(d, ..) => {
          let i = d.to_int()
          if d != i.to_double() {
            raise InvalidNumber(loc, field)
          }
          if i < 0 {
            raise NegativeNumber(loc, field)
          }
          Some(i)
        }
        _ => raise InvalidNumber(loc, field)
      }
  }
}

///|
/// Split `<component>.<port>` into its two halves. Empty halves are rejected;
/// the component name itself is not resolved here (that is a plan-time check).
pub fn parse_port_ref(s : String) -> (String, String)? {
  // Split at the FIRST '.': the component name is everything before it, and the
  // port is the remaining path (`f` or `iface.f`). Treating the trailing
  // segment as the port would make `reader:io/transform@1.0.0.transform`
  // ambiguous, so the component name simply may not contain dots.
  let mut idx : Int = -1
  let mut i = 0
  for c in s {
    if c == '.' && idx < 0 {
      idx = i
    }
    i = i + 1
  }
  if idx <= 0 || idx >= s.length() - 1 {
    return None
  }
  let comp = s[:idx].to_owned()
  let port = s[idx + 1 :].to_owned()
  // A port path must not itself start or end with a dot.
  if port.get_char(0) == Some('.') || port.get_char(port.char_length() - 1) == Some('.') {
    return None
  }
  Some((comp, port))
}

///|
fn parse_wire(j : @json.Json, index : Int) -> WireDecl raise ManifestError {
  let loc = "wires[\{index}]"
  let m = expect_object(j, loc)
  let from_s = required_string(m, "from", loc)
  let to_s = required_string(m, "to", loc)
  let (from_c, from_p) = match parse_port_ref(from_s) {
    Some(x) => x
    None => raise InvalidPortRef("\{loc}.from", from_s)
  }
  let (to_c, to_p) = match parse_port_ref(to_s) {
    Some(x) => x
    None => raise InvalidPortRef("\{loc}.to", to_s)
  }
  { from_component: from_c, from_port: from_p, to_component: to_c, to_port: to_p }
}

///|
fn parse_component(j : @json.Json, index : Int) -> ComponentDecl raise ManifestError {
  let loc = "components[\{index}]"
  let m = expect_object(j, loc)
  let name = required_string(m, "name", loc)
  let path = required_string(m, "path", loc)
  if name.is_empty() {
    raise MissingField(loc, "name")
  }
  { name, path }
}

///|
/// Parse a manifest string. Validation of *references* (does wire point at an
/// existing component, is the graph acyclic) is deferred to the planner.
pub fn parse(s : String) -> Manifest raise ManifestError {
  let json = @json.parse(s, max_nesting_depth=64) catch {
    e => raise InvalidJson(e.to_string())
  }
  let root = expect_object(json, "manifest")
  let version = match root.get("version") {
    Some(v) => expect_string(v, "manifest.version")
    None => "0.1.0"
  }
  if !version.has_prefix("0.1.") {
    raise UnsupportedManifestVersion(version)
  }
  let comps_json = expect_array(required(root, "components", "manifest"), "manifest.components")
  let components : Array[ComponentDecl] = []
  let seen : Map[String, Unit] = Map([])
  let mut idx = 0
  for c in comps_json {
    let decl = parse_component(c, idx)
    if seen.get(decl.name) is Some(_) {
      raise DuplicateComponent(decl.name)
    }
    seen.set(decl.name, ())
    components.push(decl)
    idx = idx + 1
  }
  let wires : Array[WireDecl] = []
  match root.get("wires") {
    None => ()
    Some(w) => {
      let arr = expect_array(w, "manifest.wires")
      let mut i = 0
      for item in arr {
        wires.push(parse_wire(item, i))
        i = i + 1
      }
    }
  }
  let resources = match root.get("resources") {
    None => { max_memory_pages: None, quota: None }
    Some(r) => {
      let rm = expect_object(r, "manifest.resources")
      {
        max_memory_pages: optional_nonneg_int(rm, "max_memory_pages", "manifest.resources"),
        quota: optional_nonneg_int(rm, "quota", "manifest.resources"),
      }
    }
  }
  { version, components, wires, resources }
}