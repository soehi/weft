///|
test "D2 Merkle scalar vector is fixed independently of arena indices and aliases" {
  let c = graph("hash", [@ir.Scalar("u32"), @ir.Alias(0), @ir.Alias(1)])
  for i in 0..<3 {
    assert_eq(fingerprint(c, i), "8af9aafb8305662baa02403c8bc7d4ec6119d679cf39dd40c12042d25ebe999b")
  }
  let malformed = graph("bad", [@ir.Alias(0)])
  try fingerprint(malformed, 0) catch {
    Rejected(d) => assert_eq(d.code, "CYCLIC_TYPE")
  } noraise { _ => fail("cyclic signature accepted") }
}

///|
test "D2 signature ignores arena permutation and legal aliases across 2000 seeds" {
  for seed in 0..<2000 {
    let c = generated(seed)
    let p = permuted(c)
    assert_eq(fingerprint(c, c.types.length() - 1), fingerprint(p, 0))
    let scalar = p.types.length() - 1
    let alias_index = p.types.length()
    let nodes : Array[@ir.Node] = p.types.map(n => {
      name: None, kind: rewritten(n.kind, i => if i == scalar { alias_index } else { i }, false),
    })
    nodes.push({ name: None, kind: @ir.Alias(scalar) })
    assert_eq(fingerprint(p, 0), fingerprint({ ..p, types: nodes }, 0))
  }
}
