///|
fn port_batch(size : Int32, fast : Bool) -> Int32 raise {
  let (input, _) = scale_binding_input(size)
  let iface = input.ifaces.get("sink").unwrap()
  let cache : Map[(String, Bool), Map[String, @ir.Port]] = Map([])
  let mut checksum = 0
  for entry in iface.imports {
    let sig = if fast {
      resolve_indexed_port(iface, "sink", ImportSide, entry.name, cache)
    } else {
      scan_resolve_port(iface, ImportSide, entry.name)
    }
    checksum += sig.name.length()
  }
  checksum
}

///|
test "ports: wide indexed batches agree with scan" {
  for size in [1, 15, 16, 100, 1000] {
    assert_eq(port_batch(size, true), port_batch(size, false))
  }
}

///|
test "ports: duplicate order Unicode paths and errors agree with old resolver" {
  let (input, _) = scale_binding_input(20)
  let original = input.ifaces.get("sink").unwrap()
  let func : @ir.FuncSig = {
    name: "尾",
    is_async: false,
    params: [],
    result: None,
  }
  let a : @ir.PortEntry = { name: "🧵", port: @ir.Interface("🧵", [func]), }
  let b : @ir.PortEntry = { name: "🧵", port: @ir.Func(func), }
  for entries in [original.imports + [a, b], [b, a] + original.imports] {
    let iface = { ..original, imports: entries, exports: entries, }
    let cache : Map[(String, Bool), Map[String, @ir.Port]] = Map([])
    for side in [ImportSide, ExportSide] {
      for
        path in [
          "in-0", "in-19", "absent", "absent.x", "🧵", "🧵.尾", "🧵.absent",
          "🧵.尾.extra", ".x", "",
        ] {
        let expected = try
          "ok:" + scan_resolve_port(iface, side, path).name
        catch {
          e => e.to_string()
        }
        let actual = try
          "ok:" + resolve_indexed_port(iface, "sink", side, path, cache).name
        catch {
          e => e.to_string()
        }
        assert_eq(actual, expected)
      }
    }
  }
}

///|
test "ports: planner index is rebuilt after public IR mutation" {
  let (input, _) = scale_binding_input(20)
  let before = plan_json(plan(input))
  let iface = input.ifaces.get("sink").unwrap()
  let first = iface.imports[0]
  iface.imports[0] = {
    name: first.name,
    port: @ir.Func({
      name: first.name,
      is_async: false,
      params: [{ name: "x", ty: @ir.Bool, }],
      result: None,
    }),
  }
  try plan(input) catch {
    SignatureMismatch(_, _, _, _, _) => ()
    e => fail(e.to_string())
  } noraise {
    _ => fail("stale signature cache accepted mutated input")
  }
  iface.imports[0] = first
  assert_eq(plan_json(plan(input)), before)
}

///|
test "port lookup full batch benchmark includes index construction" (
  b : @bench.T,
) {
  for size in [100, 1000] {
    b.bench(
      name="port-scan-\{size}",
      fn() { b.keep(port_batch(size, false) catch { _ => -1 }) },
      count=3,
    )
    b.bench(
      name="port-index-\{size}",
      fn() { b.keep(port_batch(size, true) catch { _ => -1 }) },
      count=3,
    )
  }
}
