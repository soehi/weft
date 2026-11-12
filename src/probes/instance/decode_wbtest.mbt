///|
fn decode_package(bytes : Bytes) -> @verifier.BinaryPackage raise {
  match @verifier.decode_component_package(bytes) {
    Ok(p) => p
    Err(ds) => fail(ds.map(d => d.render()).join("; "))
  }
}

///|
test "D0 real instance binaries decode all four providers and the consumer" {
  for mode in ["source", "alternate", "missing", "wrong-type"] {
    let p = decode_package(provider(mode))
    let arena = p.types()
    guard arena[p.world()].kind is @verifier.World(_, _, _, outs) else {
      fail("provider world lost")
    }
    let mut i = -1
    for e in outs {
      if e.name == "ops" {
        if e.kind is @verifier.Instance(index) { i = index }
      }
    }
    assert_true(i >= 0)
    guard arena[i].kind is @verifier.Interface(_, _, members) else {
      fail("instance members lost")
    }
    assert_true(members.any(e => e.name == "value" && e.kind is Type(_)))
    assert_true(members.any(e => e.name == "inc" && e.kind is Function(_)))
    assert_eq(members.any(e => e.name == "twice"), mode != "missing")
    assert_true(outs.any(e => e.name == "value-copy" && e.kind is Type(_)))
    assert_true(arena.any(t => t.kind is Alias(_)))
    let ir = @ir.decode_component(mode, mode + ".wasm", provider(mode))
    guard ir.exports[0].port is @ir.Interface(_, fs) else {
      fail("provider interface lost")
    }
    let inc = fs[0]
    assert_eq(inc.name, "inc")
    assert_eq(inc.params[0].ty, if mode == "wrong-type" { @ir.Bool } else { @ir.U32 })
  }
  let p = decode_package(consumer())
  guard p.types()[p.world()].kind is @verifier.World(_, _, ins, _) else {
    fail("consumer world lost")
  }
  assert_true(ins.any(e => e.name == "ops" && e.kind is Instance(_)))
  let imported = @ir.decode_component("consumer", "consumer.wasm", consumer())
  guard imported.imports[0].port is @ir.Interface(_, fs) else {
    fail("consumer instance lost")
  }
  assert_eq(fs.map(f => f.name), ["inc", "twice"])
}

///|
test "D0 documents existing IR loss: named types and aliases are not instance members" {
  let decoded = @ir.decode_component("source", "source.wasm", provider("source"))
  assert_eq(decoded.exports.length(), 1)
  assert_eq(decoded.exports[0].name, "ops")
  guard decoded.exports[0].port is @ir.Interface(_, fs) else {
    fail("interface export lost")
  }
  assert_eq(fs.map(f => f.name), ["inc", "twice"])
  let p = decode_package(provider("source"))
  for i in 0..<p.types().length() {
    if p.types()[i].kind is Alias(_) {
      assert_true(decoded.types[i] is None)
    }
  }
}
