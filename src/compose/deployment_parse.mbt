///|
fn protocol_json(source : String) -> Map[String, @json.Json] raise InputError {
  let value = @json.parse(source, max_nesting_depth=128, reject_duplicate_keys=true) catch {
    e => { reject("INVALID_JSON", "", [], e.to_string()); abort("unreachable") }
  }
  obj(value, [])
}

///|
fn fixed(m : Map[String, @json.Json], key : String, expected : String, at : Array[String]) -> Unit raise InputError {
  let actual = text(required(m, key, at), at + [key])
  if actual != expected { reject("UNSUPPORTED_PROTOCOL", "", at + [key], actual) }
}

///|
fn natural(j : @json.Json, at : Array[String]) -> Int32 raise InputError {
  guard j is @json.Number(n, ..) && n >= 0 && n <= 2147483647.0 && n.to_int().to_double() == n else {
    reject("INVALID_INDEX", "", at, "expected nonnegative int32")
    abort("unreachable")
  }
  n.to_int()
}

///|
fn hex_digest(j : @json.Json, at : Array[String]) -> String raise InputError {
  let value = text(j, at)
  if value.length() != 64 || !value.iter().all(c => (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) {
    reject("INVALID_DIGEST", "", at, "expected 64 lowercase hexadecimal characters")
  }
  value
}

///|
fn tagged_digest(j : @json.Json, at : Array[String]) -> String raise InputError {
  let m = obj(j, at)
  allowed(m, ["algorithm", "value"], at)
  fixed(m, "algorithm", "sha256", at)
  hex_digest(required(m, "value", at), at + ["value"])
}

///|
fn parse_artifact(m : Map[String, @json.Json], at : Array[String]) -> Artifact raise InputError {
  fixed(m, "algorithm", "sha256", at)
  {
    id: text(required(m, "id", at), at + ["id"]),
    digest: hex_digest(required(m, "digest", at), at + ["digest"]),
    length: natural(required(m, "length", at), at + ["length"]),
  }
}

///|
fn parse_binding(m : Map[String, @json.Json], at : Array[String]) -> @plan.Binding raise InputError {
  let kind = match text(required(m, "kind", at), at + ["kind"]) {
    "function" => @plan.Function
    "instance" => @plan.Instance
    other => { reject("UNSUPPORTED_BINDING_KIND", "", at + ["kind"], other); abort("unreachable") }
  }
  { kind, from: endpoint(required(m, "from", at), at + ["from"]), to: endpoint(required(m, "to", at), at + ["to"]) }
}

///|
fn parse_lock(source : String) -> LockedInput raise InputError {
  let m = protocol_json(source)
  allowed(m, ["lock_version", "profile", "artifacts", "bindings"], [])
  fixed(m, "lock_version", "0.1.0", [])
  fixed(m, "profile", "instance-sync-v1", [])
  let artifacts : Array[Artifact] = []
  let ids : Map[String, Unit] = Map([])
  for entry in array(required(m, "artifacts", []), ["artifacts"]) {
    let at = ["artifacts", "\{artifacts.length()}"]
    let fields = obj(entry, at)
    allowed(fields, ["id", "algorithm", "digest", "length"], at)
    let artifact = parse_artifact(fields, at)
    if ids.contains(artifact.id) { reject("DUPLICATE_COMPONENT", artifact.id, at, "duplicate locked artifact ID") }
    ids.set(artifact.id, ())
    artifacts.push(artifact)
  }
  let bindings : Array[@plan.Binding] = []
  for entry in array(required(m, "bindings", []), ["bindings"]) {
    let at = ["bindings", "\{bindings.length()}"]
    let fields = obj(entry, at)
    allowed(fields, ["kind", "from", "to"], at)
    bindings.push(parse_binding(fields, at))
  }
  { artifacts, bindings }
}

///|
fn parse_deployment(source : String) -> ParsedDeployment raise InputError {
  let m = protocol_json(source)
  allowed(m, ["plan_version", "profile", "planner_version", "lock_digest", "instances", "bindings", "operations", "plan_digest"], [])
  fixed(m, "plan_version", "0.4.0", [])
  fixed(m, "profile", "instance-sync-v1", [])
  fixed(m, "planner_version", "instance-planner-v1", [])
  let lock_digest = tagged_digest(required(m, "lock_digest", []), ["lock_digest"])
  let digest = tagged_digest(required(m, "plan_digest", []), ["plan_digest"])
  let instances : Array[DeploymentInstance] = []
  for entry in array(required(m, "instances", []), ["instances"]) {
    let at = ["instances", "\{instances.length()}"]
    let fields = obj(entry, at)
    allowed(fields, ["id", "algorithm", "digest", "length", "order", "imports"], at)
    let imports : Array[Int32] = []
    for index in array(required(fields, "imports", at), at + ["imports"]) {
      imports.push(natural(index, at + ["imports", "\{imports.length()}"]))
    }
    instances.push({ artifact: parse_artifact(fields, at), order: natural(required(fields, "order", at), at + ["order"]), imports })
  }
  let bindings : Array[DeploymentBinding] = []
  for entry in array(required(m, "bindings", []), ["bindings"]) {
    let at = ["bindings", "\{bindings.length()}"]
    let fields = obj(entry, at)
    allowed(fields, ["kind", "from", "to", "from_signature", "to_signature"], at)
    bindings.push({ binding: parse_binding(fields, at), from_signature: hex_digest(required(fields, "from_signature", at), at + ["from_signature"]), to_signature: hex_digest(required(fields, "to_signature", at), at + ["to_signature"]) })
  }
  let operations : Array[@plan.Operation] = []
  for entry in array(required(m, "operations", []), ["operations"]) {
    let at = ["operations", "\{operations.length()}"]
    let fields = obj(entry, at)
    match text(required(fields, "op", at), at + ["op"]) {
      "instantiate" => {
        allowed(fields, ["op", "component"], at)
        operations.push(@plan.Instantiate(text(required(fields, "component", at), at + ["component"])))
      }
      "install-import" => {
        allowed(fields, ["op", "binding"], at)
        operations.push(@plan.InstallImport(natural(required(fields, "binding", at), at + ["binding"])))
      }
      other => reject("INVALID_OPERATION", "", at, other)
    }
  }
  { lock_digest, instances, bindings, operations, digest }
}
