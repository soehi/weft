///|
fn reject(code : String, component : String, path : Array[String], detail : String) -> Unit raise PlanError {
  raise Rejected({ code, component, path, detail })
}

///|
fn compare_endpoint(a : Endpoint, b : Endpoint) -> Int32 {
  for (x, y) in [(a.component, b.component), (a.port, b.port)] {
    let c = @order.cmp_str(x, y)
    if c != 0 { return c }
  }
  match (a.member_name, b.member_name) {
    (None, None) => 0
    (None, Some(_)) => -1
    (Some(_), None) => 1
    (Some(x), Some(y)) => @order.cmp_str(x, y)
  }
}

///|
fn lookup(components : Map[String, @ir.Component], endpoint : Endpoint) -> @ir.Component raise PlanError {
  match components.get(endpoint.component) {
    Some(c) => c
    None => {
      reject("UNKNOWN_COMPONENT", endpoint.component, [endpoint.port], "component is not declared")
      abort("unreachable")
    }
  }
}

///|
/// Complete composition, with no implicit host imports. The typed entry point
/// validates public mutable IR on every call; it does not cache correspondence.
pub fn plan(components : Array[@ir.Component], bindings : Array[Binding]) -> Plan raise PlanError {
  let sorted_components = components.copy()
  sorted_components.sort_by((a, b) => @order.cmp_str(a.name, b.name))
  let by_name : Map[String, @ir.Component] = Map([])
  for c in sorted_components {
    if c.name == "" { reject("INVALID_COMPONENT", c.name, [], "empty component name") }
    if by_name.contains(c.name) { reject("DUPLICATE_COMPONENT", c.name, [], "component name must be unique") }
    by_name.set(c.name, c)
  }
  let sorted = bindings.copy()
  sorted.sort_by((a, b) => {
    let target = compare_endpoint(a.to, b.to)
    if target != 0 { return target }
    let source = compare_endpoint(a.from, b.from)
    if source != 0 { return source }
    match (a.kind, b.kind) { (Instance, Function) => -1; (Function, Instance) => 1; _ => 0 }
  })
  let target_roots : Map[(String, String), Binding] = Map([])
  // Detect complete/partial or function/instance conflicts before admitting any
  // member binding. A partial member never satisfies an entire import instance.
  for b in sorted {
    let _ = lookup(by_name, b.from)
    let _ = lookup(by_name, b.to)
    let key = (b.to.component, b.to.port)
    match target_roots.get(key) {
      None => target_roots.set(key, b)
      Some(first) => {
        let same_kind = match (first.kind, b.kind) { (Function, Function) | (Instance, Instance) => true; _ => false }
        if !same_kind || first.to.member_name != b.to.member_name {
          reject("MIXED_BINDING", b.to.component, ["imports", b.to.port], "whole instance and member/function bindings cannot be mixed")
        }
        reject("DUPLICATE_BINDING", b.to.component, ["imports", b.to.port], "import has multiple providers")
      }
    }
  }
  let checked : Array[CheckedBinding] = []
  for b in sorted {
    if b.to.member_name is Some(_) {
      reject("PARTIAL_INSTANCE_BINDING", b.to.component, ["imports", b.to.port], "bind the complete instance, including its named types")
    }
    let source = lookup(by_name, b.from)
    let target = lookup(by_name, b.to)
    if b.kind is Instance && b.from.member_name is Some(_) {
      reject("INVALID_ENDPOINT", b.from.component, ["exports", b.from.port], "instance binding cannot select a function member")
    }
    let relation = try {
      match b.kind {
        Instance => {
          @types.check_instance(source, b.from.port, target, b.to.port)
        }
        Function => @types.check_function(source, b.from.port, b.from.member_name, target, b.to.port)
      }
    } catch {
      @types.Rejected(d) => raise Rejected(d)
    }
    checked.push({ binding: b, correspondence: relation })
  }
  for c in sorted_components {
    let imports = c.imports.copy()
    imports.sort_by((a, b) => @order.cmp_str(a.name, b.name))
    for i in 0..<imports.length() {
      let entry = imports[i]
      if i > 0 && entry.name == imports[i - 1].name {
        reject("DUPLICATE_MEMBER", c.name, ["imports", entry.name], "duplicate import name")
      }
      match entry.item {
        @ir.Function(_) | @ir.Instance(_) => {
          if !target_roots.contains((c.name, entry.name)) {
            reject("UNBOUND_IMPORT", c.name, ["imports", entry.name], "no declared provider; host capabilities are not implicit")
          }
        }
        _ => reject("UNSUPPORTED_IMPORT", c.name, ["imports", entry.name], "non-function/non-instance root import")
      }
    }
  }
  let m : @manifest.Manifest = {
    version: "0.2.0",
    components: sorted_components.map(c => { name: c.name, path: c.name }),
    wires: sorted.map(b => {
      from_component: b.from.component, from_port: b.from.port,
      to_component: b.to.component, to_port: b.to.port,
    }),
    resources: { max_memory_pages: None, quota: None },
  }
  let order = try {
    let graph = @graph.build_graph(m)
    @graph.check_acyclic(graph)
    @graph.topo_order(graph).map(i => graph.nodes[i])
  } catch {
    @graph.Cycle(names) => {
      reject("DEPENDENCY_CYCLE", "", names, "component dependency cycle")
      abort("unreachable")
    }
    _ => {
      reject("INVALID_GRAPH", "", [], "component graph is invalid")
      abort("unreachable")
    }
  }
  let operations : Array[Operation] = []
  for name in order {
    for i in 0..<checked.length() {
      if checked[i].binding.to.component == name { operations.push(InstallImport(i)) }
    }
    operations.push(Instantiate(name))
  }
  { order, bindings: checked, operations }
}
