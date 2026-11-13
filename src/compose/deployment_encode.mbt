///|
fn sha256(bytes : Bytes) -> String {
  @crypto.bytes_to_hex_string(@crypto.sha256(bytes))
}

///|
fn hash_text(domain : String, payload : String) -> String {
  sha256(@utf8.encode(domain + "\n" + payload, bom=false))
}

///|
fn artifact_json(a : Artifact) -> String {
  "\"id\":" + quote(a.id) + ",\"algorithm\":\"sha256\",\"digest\":" + quote(a.digest) + ",\"length\":\{a.length}"
}

///|
fn binding_json(b : @plan.Binding) -> String {
  let kind = match b.kind { @plan.Instance => "instance"; @plan.Function => "function" }
  "\"kind\":" + quote(kind) + ",\"from\":" + endpoint_json(b.from) + ",\"to\":" + endpoint_json(b.to)
}

///|
fn endpoint_cmp(a : @plan.Endpoint, b : @plan.Endpoint) -> Int32 {
  for (x, y) in [(a.component, b.component), (a.port, b.port)] {
    let diff = @order.cmp_str(x, y)
    if diff != 0 { return diff }
  }
  match (a.member_name, b.member_name) {
    (None, None) => 0
    (None, Some(_)) => -1
    (Some(_), None) => 1
    (Some(x), Some(y)) => @order.cmp_str(x, y)
  }
}

///|
fn binding_cmp(a : @plan.Binding, b : @plan.Binding) -> Int32 {
  let target = endpoint_cmp(a.to, b.to)
  if target != 0 { return target }
  let source = endpoint_cmp(a.from, b.from)
  if source != 0 { return source }
  match (a.kind, b.kind) { (@plan.Instance, @plan.Function) => -1; (@plan.Function, @plan.Instance) => 1; _ => 0 }
}

///|
fn lock_json(input : LockedInput) -> String {
  let artifacts = input.artifacts.copy()
  artifacts.sort_by((a, b) => @order.cmp_str(a.id, b.id))
  let bindings = input.bindings.copy()
  bindings.sort_by(binding_cmp)
  "{\"lock_version\":\"0.1.0\",\"profile\":\"instance-sync-v1\",\"artifacts\":[" + artifacts.map(a => "{" + artifact_json(a) + "}").join(",") + "],\"bindings\":[" + bindings.map(b => "{" + binding_json(b) + "}").join(",") + "]}"
}

///|
fn lock_hash(input : LockedInput) -> String {
  hash_text("weft:input-lock:v1", lock_json(input))
}

///|
fn operation_json(op : @plan.Operation) -> String {
  match op {
    @plan.Instantiate(id) => "{\"op\":\"instantiate\",\"component\":" + quote(id) + "}"
    @plan.InstallImport(i) => "{\"op\":\"install-import\",\"binding\":\{i}}"
  }
}

///|
fn deployment_payload(p : ParsedDeployment) -> String {
  let instances = p.instances.map(i => "{" + artifact_json(i.artifact) + ",\"order\":\{i.order},\"imports\":[" + i.imports.map(n => "\{n}").join(",") + "]}")
  let bindings = p.bindings.map(b => "{" + binding_json(b.binding) + ",\"from_signature\":" + quote(b.from_signature) + ",\"to_signature\":" + quote(b.to_signature) + "}")
  "{\"plan_version\":\"0.4.0\",\"profile\":\"instance-sync-v1\",\"planner_version\":\"instance-planner-v1\",\"lock_digest\":{\"algorithm\":\"sha256\",\"value\":" + quote(p.lock_digest) + "},\"instances\":[" + instances.join(",") + "],\"bindings\":[" + bindings.join(",") + "],\"operations\":[" + p.operations.map(operation_json).join(",") + "]}"
}

///|
fn deployment_hash(p : ParsedDeployment) -> String {
  hash_text("weft:deployment-plan:v1", deployment_payload(p))
}

///|
fn deployment_json(p : ParsedDeployment) -> String {
  let payload = deployment_payload(p)
  payload[:payload.length() - 1].to_owned() + ",\"plan_digest\":{\"algorithm\":\"sha256\",\"value\":" + quote(deployment_hash(p)) + "}}"
}
