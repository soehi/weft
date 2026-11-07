// The planning driver: manifest + decoded components -> Plan.
//
// Steps, each independently testable and independently failable:
//   1. index components by name (unknown names already caught by the graph)
//   2. resolve both endpoints of every wire to concrete function signatures
//   3. check supported value semantics and structural equality, then canonical ABI
//   4. topologically order the components (deterministic)
//   5. attach incoming-wire indices and compute the plan hash
//
// Failure messages always name the component and port, never just "plan failed".

///|
/// The raw material: a manifest plus the decoded interface for each component.
pub(all) struct Input {
  manifest : @manifest.Manifest
  /// Interfaces keyed by component name; must cover every component.
  ifaces : Map[String, @ir.Iface]
}

///|
fn lookup_iface(input : Input, name : String) -> @ir.Iface raise PlanError {
  match input.ifaces.get(name) {
    Some(i) => i
    None => raise UnknownComponent(name)
  }
}

///|
/// Resolve one wire into a `PlannedWire`, checking both ports exist and have
/// matching component-value types and supplementary canonical signatures.
fn plan_wire(
  input : Input,
  w : @manifest.WireDecl,
) -> PlannedWire raise PlanError {
  let from_iface = lookup_iface(input, w.from_component)
  let to_iface = lookup_iface(input, w.to_component)
  let from_sig = resolve_port(from_iface, ExportSide, w.from_port)
  let to_sig = resolve_port(to_iface, ImportSide, w.to_port)
  check_wire_value_types(
    from_iface,
    w.from_port,
    from_sig,
    to_iface,
    w.to_port,
    to_sig,
  )
  let from_flat = flatten_sig(
    w.from_component,
    w.from_port,
    from_sig,
    from_iface.types,
  )
  let to_flat = flatten_sig(w.to_component, w.to_port, to_sig, to_iface.types)
  check_wire_signatures(
    w.from_component,
    w.from_port,
    from_flat,
    w.to_component,
    w.to_port,
    to_flat,
  )
  {
    from_component: w.from_component,
    from_port: w.from_port,
    to_component: w.to_component,
    to_port: w.to_port,
    from_flat_params: from_flat.params,
    from_flat_results: from_flat.results,
    to_flat_params: to_flat.params,
    to_flat_results: to_flat.results,
  }
}

///|
/// Wires must be emitted in a deterministic order that does not depend on
/// manifest ordering. We sort by (from_component, from_port, to_component,
/// to_port) with our own lexicographic comparator.
fn sort_wires(wires : Array[PlannedWire]) -> Unit {
  wires.sort_by(fn(a, b) {
    let c1 = @ir.cmp_str(a.from_component, b.from_component)
    if c1 != 0 {
      return c1
    }
    let c2 = @ir.cmp_str(a.from_port, b.from_port)
    if c2 != 0 {
      return c2
    }
    let c3 = @ir.cmp_str(a.to_component, b.to_component)
    if c3 != 0 {
      return c3
    }
    @ir.cmp_str(a.to_port, b.to_port)
  })
}

///|
/// Build the plan. This is the whole public entry point for S1.
pub fn plan(input : Input) -> Plan raise PlanError {
  let g = build_graph(input.manifest)
  check_acyclic(g)
  let order = topo_order(g)
  // Wires: resolve all first, so a port error is reported before any ordering
  // result could be mistaken for the cause.
  let wires : Array[PlannedWire] = []
  for w in input.manifest.wires {
    wires.push(plan_wire(input, w))
  }
  sort_wires(wires)
  // Incoming wires per component, as indices into the sorted wire list.
  let incoming : Map[String, Array[Int32]] = Map([])
  for i in 0..<wires.length() {
    let key = wires[i].to_component
    match incoming.get(key) {
      Some(arr) => arr.push(i)
      None => incoming.set(key, [i])
    }
  }
  let decl_by_name : Map[String, @manifest.ComponentDecl] = Map([])
  for c in input.manifest.components {
    decl_by_name.set(c.name, c)
  }
  let instances : Array[PlannedInstance] = []
  let mut pos = 0
  for node_idx in order {
    let name = g.nodes[node_idx]
    let decl = match decl_by_name.get(name) {
      Some(d) => d
      None => raise InvalidManifest("manifest lost component `\{name}`")
    }
    let inc = match incoming.get(name) {
      Some(x) => x
      None => []
    }
    instances.push({ name, path: decl.path, order: pos, incoming: inc, })
    pos = pos + 1
  }
  let resources : PlannedResources = {
    max_memory_pages: input.manifest.resources.max_memory_pages,
    quota: input.manifest.resources.quota,
  }
  let probe : Plan = {
    plan_version: "0.1.0",
    instances,
    wires,
    resources,
    hash: "",
  }
  // Hash covers the plan body before the hash field exists.
  let hash = fnv1a64_hex(plan_body(probe))
  {
    plan_version: probe.plan_version,
    instances: probe.instances,
    wires: probe.wires,
    resources: probe.resources,
    hash,
  }
}
