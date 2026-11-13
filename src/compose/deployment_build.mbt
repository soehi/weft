///|
fn endpoint_signature(c : @ir.Component, e : @plan.Endpoint, exporting : Bool) -> String raise InputError {
  let entries = if exporting { c.exports } else { c.imports }
  let mut item : @ir.Item? = None
  for entry in entries { if entry.name == e.port { item = Some(entry.item) } }
  if e.member_name is Some(name) {
    guard item is Some(@ir.Instance(start)) else {
      reject("INVALID_ENDPOINT", c.name, [e.port], "member selection requires an instance")
      abort("unreachable")
    }
    let mut index = start
    for _ in 0..<=c.types.length() {
      if index < 0 || index >= c.types.length() { break }
      match c.types[index].kind {
        @ir.Alias(next) => index = next
        @ir.Interface(_, _, members) => {
          item = None
          for entry in members { if entry.name == name { item = Some(entry.item) } }
          break
        }
        _ => break
      }
    }
  }
  let index = match item {
    Some(@ir.Function(i)) | Some(@ir.Instance(i)) => i
    _ => { reject("INVALID_ENDPOINT", c.name, [e.port], "missing function or instance endpoint"); abort("unreachable") }
  }
  @types.fingerprint(c, index) catch { @types.Rejected(d) => raise Rejected(d) }
}

///|
fn signed_binding(b : @plan.Binding, components : Map[String, @ir.Component]) -> DeploymentBinding raise InputError {
  {
    binding: b,
    from_signature: endpoint_signature(components.get(b.from.component).unwrap(), b.from, true),
    to_signature: endpoint_signature(components.get(b.to.component).unwrap(), b.to, false),
  }
}

///|
fn ordered_deployment(input : LockedInput, order : Array[String], bindings : Array[DeploymentBinding]) -> ParsedDeployment {
  let instances : Array[DeploymentInstance] = []
  let operations : Array[@plan.Operation] = []
  for id in order {
    let imports : Array[Int32] = []
    for j in 0..<bindings.length() {
      if bindings[j].binding.to.component == id {
        imports.push(j)
        operations.push(@plan.InstallImport(j))
      }
    }
    for artifact in input.artifacts {
      if artifact.id == id { instances.push({ artifact, order: instances.length(), imports }) }
    }
    operations.push(@plan.Instantiate(id))
  }
  { lock_digest: lock_hash(input), instances, bindings, operations, digest: "" }
}

///|
/// New deployment format; compile's D1 plan and the old API remain unchanged.
pub fn seal(source : String, binaries : Map[String, Bytes]) -> Result[Deployment, @types.Diagnostic] {
  try {
    let (m, decoded) = prepare(source, binaries)
    let plan = @plan.plan(decoded, m.bindings) catch { @plan.Rejected(d) => raise Rejected(d) }
    let components : Map[String, @ir.Component] = Map([])
    let artifacts : Array[Artifact] = []
    for c in decoded {
      components.set(c.name, c)
      let bytes = binaries.get(c.name).unwrap()
      artifacts.push({ id: c.name, digest: sha256(bytes), length: bytes.length() })
    }
    let input = { artifacts, bindings: plan.bindings.map(b => b.binding) }
    let bindings : Array[DeploymentBinding] = []
    for b in plan.bindings { bindings.push(signed_binding(b.binding, components)) }
    Ok({ plan_text: deployment_json(ordered_deployment(input, plan.order, bindings)), lock_text: lock_json(input) })
  } catch { Rejected(d) => Err(d) }
}
