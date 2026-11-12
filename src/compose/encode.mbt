///|
fn quote(s : String) -> String { @json.to_json(s).stringify(escape_slash=false) }

///|
fn endpoint_json(e : @plan.Endpoint) -> String {
  let suffix = match e.member_name { Some(s) => ",\"member\":" + quote(s); None => "" }
  "{\"component\":" + quote(e.component) + ",\"port\":" + quote(e.port) + suffix + "}"
}

///|
fn encode(m : Manifest, p : @plan.Plan) -> String {
  let paths : Map[String, String] = Map([])
  for c in m.components { paths.set(c.name, c.path) }
  let instances : Array[String] = []
  for i in 0..<p.order.length() {
    let name = p.order[i]
    let incoming : Array[String] = []
    for j in 0..<p.bindings.length() {
      if p.bindings[j].binding.to.component == name { incoming.push("\{j}") }
    }
    instances.push("{\"name\":" + quote(name) + ",\"path\":" + quote(paths.get(name).unwrap()) + ",\"order\":\{i},\"imports\":[" + incoming.join(",") + "]}")
  }
  let bindings = p.bindings.map(checked => {
    let b = checked.binding
    let kind = match b.kind { @plan.Instance => "instance"; @plan.Function => "function" }
    "{\"kind\":" + quote(kind) + ",\"from\":" + endpoint_json(b.from) + ",\"to\":" + endpoint_json(b.to) + "}"
  })
  let operations = p.operations.map(op => match op {
    @plan.Instantiate(name) => "{\"op\":\"instantiate\",\"component\":" + quote(name) + "}"
    @plan.InstallImport(i) => "{\"op\":\"install-import\",\"binding\":\{i}}"
  })
  "{\"plan_version\":\"0.3.0\",\"profile\":\"instance-sync-v1\",\"instances\":[" + instances.join(",") + "],\"bindings\":[" + bindings.join(",") + "],\"operations\":[" + operations.join(",") + "]}"
}
