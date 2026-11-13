///|
fn artifact_matches(a : Artifact, b : Artifact) -> Bool {
  a.id == b.id && a.digest == b.digest && a.length == b.length
}

///|
fn same_binding(a : @plan.Binding, b : @plan.Binding) -> Bool {
  binding_json(a) == binding_json(b)
}

///|
fn verify_artifacts(input : LockedInput, p : ParsedDeployment, binaries : Map[String, Bytes]) -> Map[String, @ir.Component] raise InputError {
  let locked : Map[String, Artifact] = Map([])
  for a in input.artifacts { locked.set(a.id, a) }
  let extra = binaries.keys().filter(id => !locked.contains(id)).to_array()
  extra.sort_by(@order.cmp_str)
  if !extra.is_empty() { reject("UNEXPECTED_BINARY", extra[0], [], "not in trusted lock") }
  let components : Map[String, @ir.Component] = Map([])
  let names : Map[String, Unit] = Map([])
  if p.instances.length() != locked.length() { reject("INSTANCE_SET_MISMATCH", "", ["instances"], "plan and lock must have exactly the same IDs") }
  for i in 0..<p.instances.length() {
    let instance = p.instances[i]
    let id = instance.artifact.id
    if names.contains(id) { reject("DUPLICATE_COMPONENT", id, ["instances", "\{i}"], "duplicate instance ID") }
    names.set(id, ())
    let expected = match locked.get(id) {
      Some(a) => a
      None => { reject("INSTANCE_SET_MISMATCH", id, ["instances"], "instance is not locked"); abort("unreachable") }
    }
    if !artifact_matches(expected, instance.artifact) { reject("ARTIFACT_MISMATCH", id, ["instances", "\{i}"], "plan artifact differs from trusted lock") }
    if instance.order != i { reject("INVALID_ORDER", id, ["instances", "\{i}", "order"], "order must equal array position") }
    let bytes = match binaries.get(id) {
      Some(bytes) => bytes
      None => { reject("MISSING_BINARY", id, [], "locked bytes not supplied"); abort("unreachable") }
    }
    if bytes.length() != expected.length || sha256(bytes) != expected.digest {
      reject("BINARY_DIGEST_MISMATCH", id, [], "raw component bytes differ from trusted lock")
    }
    let c = @ir.decode(id, bytes) catch {
      @ir.InvalidComponent(_, detail) => { reject("DECODE_FAILED", id, [], detail); abort("unreachable") }
    }
    components.set(id, c)
  }
  components
}

///|
fn verify_bindings(input : LockedInput, p : ParsedDeployment, components : Map[String, @ir.Component]) -> Array[@plan.CheckedBinding] raise InputError {
  let locked = input.bindings.copy()
  locked.sort_by(binding_cmp)
  let supplied = p.bindings.map(b => b.binding)
  supplied.sort_by(binding_cmp)
  if supplied.length() != locked.length() { reject("BINDING_INTENT_MISMATCH", "", ["bindings"], "binding count differs from trusted lock") }
  for i in 0..<locked.length() {
    if !same_binding(locked[i], supplied[i]) { reject("BINDING_INTENT_MISMATCH", supplied[i].to.component, ["bindings", "\{i}"], "binding differs from trusted lock") }
  }
  let positions : Map[String, Int32] = Map([])
  for i in 0..<p.instances.length() { positions.set(p.instances[i].artifact.id, i) }
  let targets : Map[(String, String), Unit] = Map([])
  let checked : Array[@plan.CheckedBinding] = []
  for i in 0..<p.bindings.length() {
    let entry = p.bindings[i]
    let b = entry.binding
    let at = ["bindings", "\{i}"]
    let provider = match components.get(b.from.component) {
      Some(c) => c
      None => { reject("UNKNOWN_COMPONENT", b.from.component, at, "unknown provider"); abort("unreachable") }
    }
    let consumer = match components.get(b.to.component) {
      Some(c) => c
      None => { reject("UNKNOWN_COMPONENT", b.to.component, at, "unknown consumer"); abort("unreachable") }
    }
    if b.to.member_name is Some(_) || (b.kind is @plan.Instance && b.from.member_name is Some(_)) {
      reject("INVALID_ENDPOINT", b.to.component, at, "target must be a whole root import; instance source cannot select member")
    }
    let key = (b.to.component, b.to.port)
    if targets.contains(key) { reject("DUPLICATE_BINDING", b.to.component, at, "multiple providers for root import") }
    targets.set(key, ())
    if positions.get(b.from.component).unwrap() >= positions.get(b.to.component).unwrap() {
      reject("INVALID_ORDER", b.to.component, at, "provider must precede consumer; cycles are invalid")
    }
    let correspondence = try {
      match b.kind {
        @plan.Instance => @types.check_instance(provider, b.from.port, consumer, b.to.port)
        @plan.Function => @types.check_function(provider, b.from.port, b.from.member_name, consumer, b.to.port)
      }
    } catch { @types.Rejected(d) => raise Rejected(d) }
    let actual = signed_binding(b, components)
    if actual.from_signature != entry.from_signature || actual.to_signature != entry.to_signature {
      reject("TYPE_SIGNATURE_MISMATCH", b.to.component, at, "signature does not match decoded component types")
    }
    checked.push({ binding: b, correspondence })
  }
  for (id, c) in components {
    let imports : Map[String, Unit] = Map([])
    for entry in c.imports {
      if imports.contains(entry.name) { reject("DUPLICATE_MEMBER", id, ["imports", entry.name], "duplicate root import") }
      imports.set(entry.name, ())
      match entry.item {
        @ir.Function(_) | @ir.Instance(_) => ()
        _ => reject("UNSUPPORTED_IMPORT", id, ["imports", entry.name], "no implicit host capabilities")
      }
      if !targets.contains((id, entry.name)) { reject("UNBOUND_IMPORT", id, ["imports", entry.name], "every root import needs exactly one declared binding") }
    }
  }
  checked
}

///|
fn verify_operations(p : ParsedDeployment) -> Unit raise InputError {
  let seen : Map[Int32, Unit] = Map([])
  let mut cursor = 0
  for instance in p.instances {
    let id = instance.artifact.id
    let mut expected = 0
    for b in p.bindings { if b.binding.to.component == id { expected = expected + 1 } }
    if instance.imports.length() != expected { reject("INVALID_INCOMING", id, ["imports"], "incoming count differs from binding targets") }
    let group : Map[Int32, Unit] = Map([])
    for index in instance.imports {
      if index >= p.bindings.length() { reject("INVALID_INDEX", id, ["imports"], "binding index out of range") }
      if p.bindings[index].binding.to.component != id || seen.contains(index) { reject("INVALID_INCOMING", id, ["imports"], "wrong target or repeated binding index") }
      seen.set(index, ())
      group.set(index, ())
    }
    let installed : Map[Int32, Unit] = Map([])
    // Imports for each consumer must be installed together immediately before
    // its instantiation. Global-linker name shadowing cannot cross this group.
    for _ in 0..<expected {
      if cursor >= p.operations.length() { reject("INVALID_OPERATIONS", id, [], "missing install operation") }
      guard p.operations[cursor] is @plan.InstallImport(index) && group.contains(index) && !installed.contains(index) else {
        reject("INVALID_OPERATIONS", id, ["operations", "\{cursor}"], "expected unique incoming binding for this consumer")
        abort("unreachable")
      }
      installed.set(index, ())
      cursor = cursor + 1
    }
    if cursor >= p.operations.length() { reject("INVALID_OPERATIONS", id, [], "missing instantiation") }
    guard p.operations[cursor] is @plan.Instantiate(name) && name == id else {
      reject("INVALID_OPERATIONS", id, ["operations", "\{cursor}"], "expected instantiation after complete import installation")
      abort("unreachable")
    }
    cursor = cursor + 1
  }
  if cursor != p.operations.length() || seen.length() != p.bindings.length() {
    reject("INVALID_OPERATIONS", "", ["operations"], "extra operations or uncovered bindings")
  }
}

///|
// Independent Kahn reference order. The verifier never calls compile/plan/seal.
fn canonical_order(input : LockedInput) -> Array[String] raise InputError {
  let ids = input.artifacts.map(a => a.id)
  ids.sort_by(@order.cmp_str)
  let done : Map[String, Unit] = Map([])
  let result : Array[String] = []
  while result.length() < ids.length() {
    let mut selected : String? = None
    for id in ids {
      if done.contains(id) { continue }
      let mut ready = true
      for b in input.bindings { if b.to.component == id && !done.contains(b.from.component) { ready = false; break } }
      if ready { selected = Some(id); break }
    }
    guard selected is Some(id) else { reject("INVALID_ORDER", "", [], "dependency cycle"); abort("unreachable") }
    done.set(id, ())
    result.push(id)
  }
  result
}

///|
/// The lock must come from a trusted review channel. A plan's self-checksum
/// alone provides neither authorization nor an author's identity.
pub fn verify(plan_text : String, trusted_lock_text : String, binaries : Map[String, Bytes]) -> Result[VerifiedDeployment, @types.Diagnostic] {
  try {
    let input = parse_lock(trusted_lock_text)
    let p = parse_deployment(plan_text)
    if p.lock_digest != lock_hash(input) { reject("LOCK_DIGEST_MISMATCH", "", ["lock_digest"], "plan was produced for a different reviewed input") }
    if p.digest != deployment_hash(p) { reject("PLAN_DIGEST_MISMATCH", "", ["plan_digest"], "checksum differs from parsed plan payload") }
    let components = verify_artifacts(input, p, binaries)
    let bindings = verify_bindings(input, p, components)
    verify_operations(p)
    let sorted = p.bindings.copy()
    sorted.sort_by((a, b) => binding_cmp(a.binding, b.binding))
    let canonical = ordered_deployment(input, canonical_order(input), sorted)
    Ok({ canonical: plan_text == deployment_json(canonical), plan: { order: p.instances.map(i => i.artifact.id), bindings, operations: p.operations } })
  } catch { Rejected(d) => Err(d) }
}
