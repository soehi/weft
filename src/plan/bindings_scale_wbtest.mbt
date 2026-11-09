///|
fn scale_binding_input(size : Int32) -> (Input, Array[PlannedWire]) {
  let imports : Array[@ir.PortEntry] = []
  let wires : Array[PlannedWire] = []
  for i in 0..<size {
    let name = "in-\{i}"
    imports.push({
      name,
      port: @ir.Func({ name, is_async: false, params: [], result: None, }),
    })
    wires.push({
      from_component: "source",
      from_port: "out",
      to_component: "sink",
      to_port: name,
      from_flat_params: [],
      from_flat_results: [],
      to_flat_params: [],
      to_flat_results: [],
    })
  }
  let m : @manifest.Manifest = {
    version: "0.2.0",
    components: [{ name: "source", path: "source" },{ name: "sink", path: "sink", }],
    wires: wires.map(w => {from_component:w.from_component,from_port:w.from_port,to_component:w.to_component,to_port:w.to_port}),
    resources: { max_memory_pages: None, quota: None, },
  }
  let iface : @ir.Iface = {
    name: "sink",
    path: "sink",
    imports,
    exports: [],
    types: [],
    unwireable_imports: [],
  }
  let source : @ir.Iface = {name:"source",path:"source",imports:[],types:[],unwireable_imports:[],
    exports:[{name:"out",port:@ir.Func({name:"out",is_async:false,params:[],result:None})}]}
  ({ manifest: m, ifaces: Map([("sink", iface),("source",source)]), }, wires)
}

///|
fn binding_outcome(
  input : Input,
  wires : Array[PlannedWire],
  reference : Bool,
) -> String {
  try {
    if reference {
      scan_bindings(input, wires)
    } else {
      check_bindings(input, wires)
    }
    "ok"
  } catch {
    e => e.to_string()
  }
}

///|
test "bindings: sorted coverage preserves wide-table diagnostics" {
  let (input, wires) = scale_binding_input(1000)
  assert_eq(binding_outcome(input, wires, false), "ok")
  assert_eq(plan(input).wires.length(),1000)
  for missing in [0, 1, 99, 999] {
    let partial = wires.copy()
    let _ = partial.remove(missing)
    assert_eq(
      binding_outcome(input, partial, false),
      binding_outcome(input, partial, true),
    )
  }
}

///|
test "bindings: duplicate and unwireable public IR entries preserve precedence" {
  let (input, wires) = scale_binding_input(3)
  let original = input.ifaces.get("sink").unwrap()
  let interface_entry : @ir.PortEntry = {
    name: "in-0",
    port: @ir.Interface("in-0", []),
  }
  for
    imports in [
      original.imports + [interface_entry],
      [interface_entry] + original.imports,
    ] {
    for unwireable in [[], ["in-0"], ["a", "in-0"], ["in-2"]] {
      let ifaces = Map([("source",input.ifaces.get("source").unwrap()),
        ("sink", { ..original, imports, unwireable_imports: unwireable, }),
      ])
      let candidate = { ..input, ifaces, }
      for provided in [wires, [], wires + [wires[0]]] {
        assert_eq(
          binding_outcome(candidate, provided, false),
          binding_outcome(candidate, provided, true),
        )
      }
    }
  }
}

///|
test "bindings coverage 100/1000 direct-call benchmark" (b : @bench.T) {
  for size in [100, 1000] {
    let (input, wires) = scale_binding_input(size)
    b.bench(
      name="scan-\{size}",
      fn() { b.keep(binding_outcome(input, wires, true)) },
      count=3,
    )
    b.bench(
      name="current-\{size}",
      fn() { b.keep(binding_outcome(input, wires, false)) },
      count=3,
    )
  }
}
