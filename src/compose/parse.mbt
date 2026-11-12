///|
fn reject(code : String, component : String, path : Array[String], detail : String) -> Unit raise InputError {
  raise Rejected({ code, component, path, detail })
}

///|
fn obj(j : @json.Json, at : Array[String]) -> Map[String, @json.Json] raise InputError {
  guard j is @json.Object(m) else {
    reject("WRONG_FIELD_TYPE", "", at, "expected object")
    abort("unreachable")
  }
  m
}

///|
fn allowed(m : Map[String, @json.Json], keys : Array[String], at : Array[String]) -> Unit raise InputError {
  let extras = m.keys().filter(k => !keys.contains(k)).to_array()
  extras.sort_by(@order.cmp_str)
  if !extras.is_empty() { reject("UNKNOWN_FIELD", "", at + [extras[0]], "unknown field") }
}

///|
fn required(m : Map[String, @json.Json], key : String, at : Array[String]) -> @json.Json raise InputError {
  match m.get(key) {
    Some(j) => j
    None => { reject("MISSING_FIELD", "", at + [key], "required field"); abort("unreachable") }
  }
}

///|
fn text(j : @json.Json, at : Array[String]) -> String raise InputError {
  guard j is @json.String(s) && s != "" else {
    reject("WRONG_FIELD_TYPE", "", at, "expected nonempty string")
    abort("unreachable")
  }
  s
}

///|
fn array(j : @json.Json, at : Array[String]) -> Array[@json.Json] raise InputError {
  guard j is @json.Array(xs) else {
    reject("WRONG_FIELD_TYPE", "", at, "expected array")
    abort("unreachable")
  }
  xs
}

///|
fn endpoint(j : @json.Json, at : Array[String]) -> @plan.Endpoint raise InputError {
  let m = obj(j, at)
  allowed(m, ["component", "port", "member"], at)
  let member_name = match m.get("member") {
    Some(j) => Some(text(j, at + ["member"]))
    None => None
  }
  {
    component: text(required(m, "component", at), at + ["component"]),
    port: text(required(m, "port", at), at + ["port"]),
    member_name,
  }
}

///|
/// Explicit new version/profile only; old function manifests use api.compile.
pub fn parse(source : String) -> Manifest raise InputError {
  let json = @json.parse(source, max_nesting_depth=128, reject_duplicate_keys=true) catch {
    e => { reject("INVALID_JSON", "", [], e.to_string()); abort("unreachable") }
  }
  let m = obj(json, [])
  allowed(m, ["manifest_version", "profile", "components", "bindings"], [])
  let version = text(required(m, "manifest_version", []), ["manifest_version"])
  if version != "0.3.0" { reject("UNSUPPORTED_MANIFEST_VERSION", "", ["manifest_version"], version) }
  let profile = text(required(m, "profile", []), ["profile"])
  if profile != "instance-sync-v1" { reject("UNSUPPORTED_PROFILE", "", ["profile"], profile) }
  let components : Array[ComponentDecl] = []
  let names : Map[String, Unit] = Map([])
  let raw = array(required(m, "components", []), ["components"])
  for i in 0..<raw.length() {
    let at = ["components", "\{i}"]
    let c = obj(raw[i], at)
    allowed(c, ["name", "path"], at)
    let name = text(required(c, "name", at), at + ["name"])
    if names.contains(name) { reject("DUPLICATE_COMPONENT", name, at, "duplicate component name") }
    names.set(name, ())
    components.push({ name, path: text(required(c, "path", at), at + ["path"]) })
  }
  let bindings : Array[@plan.Binding] = []
  let raw = array(required(m, "bindings", []), ["bindings"])
  for i in 0..<raw.length() {
    let at = ["bindings", "\{i}"]
    let b = obj(raw[i], at)
    allowed(b, ["kind", "from", "to"], at)
    let kind = match text(required(b, "kind", at), at + ["kind"]) {
      "function" => @plan.Function
      "instance" => @plan.Instance
      other => { reject("UNSUPPORTED_BINDING_KIND", "", at + ["kind"], other); abort("unreachable") }
    }
    bindings.push({ kind, from: endpoint(required(b, "from", at), at + ["from"]), to: endpoint(required(b, "to", at), at + ["to"]) })
  }
  { components, bindings }
}
