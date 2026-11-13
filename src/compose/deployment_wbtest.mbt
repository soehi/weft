///|
fn String::swapped(self : String, old : String, new : String) -> String { self.replace(old~, new~) }

///|
fn sealed_bundle() -> Deployment raise {
  guard seal(manifest(), bins("source")) is Ok(bundle) else { fail("seal failed") }
  bundle
}

///|
fn verify_error(plan_text : String, lock_text : String, binaries : Map[String, Bytes], code : String) -> Unit raise {
  guard verify(plan_text, lock_text, binaries) is Err(d) else { fail("expected \{code}") }
  assert_eq(d.code, code)
}

///|
test "D2 pure seal and independent verification accept a canonical deployment" {
  let bundle = sealed_bundle()
  guard verify(bundle.plan_text, bundle.lock_text, bins("source")) is Ok(verified) else { fail("verification failed") }
  assert_true(verified.canonical)
  assert_eq(verified.plan.order, ["source", "consumer"])
  assert_true(!bundle.plan_text.contains("path"))
  assert_true(!bundle.lock_text.contains("path"))
  assert_true(bundle.plan_text.contains("\"plan_version\":\"0.4.0\""))
  guard compile(manifest(), bins("source")) is Ok(d1) else { fail("D1 failed") }
  assert_true(d1.json.contains("\"plan_version\":\"0.3.0\""))
  verify_error(d1.json, bundle.lock_text, bins("source"), "UNSUPPORTED_PROTOCOL")
}

///|
test "D2 behavior replacement with same interface fails against original lock" {
  let original = sealed_bundle()
  verify_error(original.plan_text, original.lock_text, bins("alternate"), "BINARY_DIGEST_MISMATCH")
  guard seal(manifest(), bins("alternate")) is Ok(changed) else { fail("alternate failed") }
  let a = parse_deployment(original.plan_text)
  let b = parse_deployment(changed.plan_text)
  assert_true(a.digest != b.digest)
  assert_eq(a.bindings[0].from_signature, b.bindings[0].from_signature)
  verify_error(changed.plan_text, original.lock_text, bins("alternate"), "LOCK_DIGEST_MISMATCH")
  guard verify(changed.plan_text, changed.lock_text, bins("alternate")) is Ok(v) else { fail("new review must succeed") }
  assert_true(v.canonical)
}

///|
test "D2 paths and input ordering do not define artifact identity" {
  let bundle = sealed_bundle()
  let relocated = manifest().swapped("source.wasm", "elsewhere/source.wasm").swapped("consumer.wasm", "../other/consumer.wasm")
  let m = parse(relocated)
  let fields = "{\"manifest_version\":\"0.3.0\",\"profile\":\"instance-sync-v1\",\"components\":[{\"name\":\"consumer\",\"path\":\"elsewhere\"},{\"name\":\"source\",\"path\":\"moved\"}],\"bindings\":[{" + binding_json(m.bindings[0]) + "}]}"
  guard seal(fields, bins("source")) is Ok(moved) else { fail("relocation failed") }
  assert_eq(moved.plan_text, bundle.plan_text)
  assert_eq(moved.lock_text, bundle.lock_text)
  guard verify(bundle.plan_text, " \n" + bundle.lock_text, bins("source")) is Ok(_) else { fail("lock formatting should not define identity") }
}

///|
test "D2 exact byte set rejects missing extra duplicate and substituted identities" {
  let bundle = sealed_bundle()
  verify_error(bundle.plan_text, bundle.lock_text, Map([]), "MISSING_BINARY")
  let extra = bins("source")
  extra.set("unexpected", b"")
  verify_error(bundle.plan_text, bundle.lock_text, extra, "UNEXPECTED_BINARY")
  let p = parse_deployment(bundle.plan_text)
  let duplicate = { ..p, instances: [p.instances[0], p.instances[0]] }
  verify_error(deployment_json(duplicate), bundle.lock_text, bins("source"), "DUPLICATE_COMPONENT")
  let omitted = { ..p, instances: [p.instances[0]] }
  verify_error(deployment_json(omitted), bundle.lock_text, bins("source"), "INSTANCE_SET_MISMATCH")
  let changed = { ..p.instances[0].artifact, length: 0 }
  let forged = { ..p, instances: [{ ..p.instances[0], artifact: changed }, p.instances[1]] }
  verify_error(deployment_json(forged), bundle.lock_text, bins("source"), "ARTIFACT_MISMATCH")
}

///|
test "D2 recomputed self-checksums do not authorize changed or deleted bindings" {
  let bundle = sealed_bundle()
  let p = parse_deployment(bundle.plan_text)
  let b = p.bindings[0]
  let changed = { ..b, binding: { ..b.binding, from: { ..b.binding.from, component: "consumer" } } }
  verify_error(deployment_json({ ..p, bindings: [changed] }), bundle.lock_text, bins("source"), "BINDING_INTENT_MISMATCH")
  verify_error(deployment_json({ ..p, bindings: [] }), bundle.lock_text, bins("source"), "BINDING_INTENT_MISMATCH")
  verify_error(deployment_json({ ..p, bindings: [b, b] }), bundle.lock_text, bins("source"), "BINDING_INTENT_MISMATCH")
}

///|
test "D2 actual decoded types reject forged signatures even after rehash" {
  let bundle = sealed_bundle()
  let p = parse_deployment(bundle.plan_text)
  let fake = "0".repeat(64)
  for b in [{ ..p.bindings[0], from_signature: fake }, { ..p.bindings[0], to_signature: fake }] {
    verify_error(deployment_json({ ..p, bindings: [b] }), bundle.lock_text, bins("source"), "TYPE_SIGNATURE_MISMATCH")
  }
}

///|
test "D2 checksum domains reject tampered plan and lock digest" {
  let bundle = sealed_bundle()
  let p = parse_deployment(bundle.plan_text)
  verify_error(bundle.plan_text.swapped(p.digest, "0".repeat(64)), bundle.lock_text, bins("source"), "PLAN_DIGEST_MISMATCH")
  verify_error(deployment_json({ ..p, lock_digest: "0".repeat(64) }), bundle.lock_text, bins("source"), "LOCK_DIGEST_MISMATCH")
  let input = parse_lock(bundle.lock_text)
  assert_true(lock_hash(input) != sha256(@utf8.encode(bundle.lock_text, bom=false)))
}

///|
test "D2 order and incoming are checked independently of their checksum" {
  let bundle = sealed_bundle()
  let p = parse_deployment(bundle.plan_text)
  let reversed = [{ ..p.instances[1], order: 0 }, { ..p.instances[0], order: 1 }]
  verify_error(deployment_json({ ..p, instances: reversed }), bundle.lock_text, bins("source"), "INVALID_ORDER")
  verify_error(deployment_json({ ..p, instances: [{ ..p.instances[0], order: 1 }, p.instances[1]] }), bundle.lock_text, bins("source"), "INVALID_ORDER")
  for imports in [[], [0, 0], [1]] {
    let changed = [{ ..p.instances[0] }, { ..p.instances[1], imports }]
    verify_error(deployment_json({ ..p, instances: changed }), bundle.lock_text, bins("source"), if imports == [1] { "INVALID_INDEX" } else { "INVALID_INCOMING" })
  }
}

///|
test "D2 execution operations require a complete contiguous consumer group" {
  let bundle = sealed_bundle()
  let p = parse_deployment(bundle.plan_text)
  for operations in [
    [],
    [@plan.InstallImport(0), @plan.Instantiate("source"), @plan.Instantiate("consumer")],
    [@plan.Instantiate("source"), @plan.Instantiate("consumer"), @plan.InstallImport(0)],
    [@plan.Instantiate("source"), @plan.InstallImport(1), @plan.Instantiate("consumer")],
    p.operations + [@plan.Instantiate("source")],
  ] {
    verify_error(deployment_json({ ..p, operations }), bundle.lock_text, bins("source"), "INVALID_OPERATIONS")
  }
}

///|
test "D2 strict parser rejects duplicate keys unknown algorithms profile versions and invalid indices" {
  let bundle = sealed_bundle()
  for plan_text in [
    bundle.plan_text.swapped("\"plan_version\":", "\"plan_version\":\"0.4.0\",\"plan_version\":"),
    bundle.plan_text.swapped("\"binding\":0", "\"binding\":-1"),
    bundle.plan_text.swapped("\"binding\":0", "\"binding\":0.5"),
    bundle.plan_text.swapped("\"binding\":0", "\"binding\":2147483648"),
    bundle.plan_text.swapped("sha256", "md5"),
    bundle.plan_text.swapped("instance-sync-v1", "unknown-profile"),
    bundle.plan_text.swapped("0.4.0", "0.3.0"),
  ] {
    guard verify(plan_text, bundle.lock_text, bins("source")) is Err(_) else { fail("invalid protocol accepted") }
  }
  let input = parse_lock(bundle.lock_text)
  verify_error(bundle.plan_text, lock_json({ ..input, artifacts: input.artifacts + [input.artifacts[0]] }), bins("source"), "DUPLICATE_COMPONENT")
}

///|
test "D2 a valid noncanonical topological order is accepted and distinguished" {
  let source = manifest()
  let m = parse(source)
  let extra_manifest = "{\"manifest_version\":\"0.3.0\",\"profile\":\"instance-sync-v1\",\"components\":[{\"name\":\"source\",\"path\":\"x\"},{\"name\":\"consumer\",\"path\":\"y\"},{\"name\":\"alternate\",\"path\":\"z\"}],\"bindings\":[{" + binding_json(m.bindings[0]) + "}]}"
  let bytes = bins("source")
  bytes.set("alternate", @fixture.provider("alternate"))
  guard seal(extra_manifest, bytes) is Ok(bundle) else { fail("seal failed") }
  let p = parse_deployment(bundle.plan_text)
  assert_eq(p.instances.map(i => i.artifact.id), ["alternate", "source", "consumer"])
  let changed = ordered_deployment(parse_lock(bundle.lock_text), ["source", "consumer", "alternate"], p.bindings)
  guard verify(deployment_json(changed), bundle.lock_text, bytes) is Ok(v) else { fail("valid alternate order rejected") }
  assert_true(!v.canonical)
  guard verify(" " + bundle.plan_text, bundle.lock_text, bytes) is Ok(formatted) else { fail("format rejected") }
  assert_true(!formatted.canonical)
  // Rewire to the other compatible provider; type signatures remain the same,
  // but the reviewed binding intention must still reject it.
  let binding = p.bindings[0]
  let rewired = { ..binding, binding: { ..binding.binding, from: { ..binding.binding.from, component: "alternate" } } }
  verify_error(deployment_json({ ..p, bindings: [rewired] }), bundle.lock_text, bytes, "BINDING_INTENT_MISMATCH")
}

///|
test "D2 verifier checks coverage and types even when a trusted lock is malformed" {
  let bundle = sealed_bundle()
  let p = parse_deployment(bundle.plan_text)
  let input = parse_lock(bundle.lock_text)
  let unbound = { ..input, bindings: [] }
  let plan = { ..p, lock_digest: lock_hash(unbound), bindings: [] }
  verify_error(deployment_json(plan), lock_json(unbound), bins("source"), "UNBOUND_IMPORT")
  let duplicates = { ..input, bindings: input.bindings + input.bindings }
  let plan = { ..p, lock_digest: lock_hash(duplicates), bindings: p.bindings + p.bindings }
  verify_error(deployment_json(plan), lock_json(duplicates), bins("source"), "DUPLICATE_BINDING")
  let wrong_bytes = bins("wrong-type")
  let artifacts = input.artifacts.map(a => if a.id == "source" { { ..a, digest: sha256(wrong_bytes.get("source").unwrap()), length: wrong_bytes.get("source").unwrap().length() } } else { a })
  let wrong = { ..input, artifacts }
  let plan = ordered_deployment(wrong, ["source", "consumer"], p.bindings)
  verify_error(deployment_json(plan), lock_json(wrong), wrong_bytes, "TYPE_MISMATCH")
}
