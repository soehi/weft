// Measurement harness only: production API and planning code are unchanged.

///|
fn profile() -> Unit raise {
  let args = @env.args()
  let start = offset()
  let filename = args[start]
  let destination = args[start + 1]
  let repeats = @strparse.parse_int(args[start + 2])
  if repeats < 1 || repeats > 20 {
    raise Failure("repeats must be 1..20")
  }
  let text = @utf8.decode(@fs.read_file_to_bytes(filename))
  let initial = @manifest.parse(text)
  let binaries : Map[String, Bytes] = Map([])
  for c in initial.components {
    let path = if @path.Path(c.path).is_absolute() {
      c.path
    } else {
      @path.Path::join(@path.Path(filename).dirname(), @path.Path(c.path)).to_string()
    }
    binaries.set(c.name, @fs.read_file_to_bytes(path))
  }
  // One full warmup, followed by samples in the same process. I/O is excluded.
  let mut golden : String? = None
  let keeper = @bench.Bench()
  for sample = 0; sample <= repeats; sample = sample + 1 {
    let timer = @bench.monotonic_clock_start()
    let m = @manifest.parse(text)
    let parse_ms = @bench.monotonic_clock_end(timer) / 1000.0
    let timer = @bench.monotonic_clock_start()
    let components = m.components.copy()
    components.sort_by((a, b) => @ir.cmp_str(a.name, b.name))
    let ifaces : Map[String, @ir.Iface] = Map([])
    for c in components {
      ifaces.set(
        c.name,
        @ir.decode_component(c.name, c.path, binaries.get(c.name).unwrap()),
      )
    }
    let decode_ms = @bench.monotonic_clock_end(timer) / 1000.0
    let timer = @bench.monotonic_clock_start()
    let p = @plan.plan({ manifest: m, ifaces, })
    let plan_ms = @bench.monotonic_clock_end(timer) / 1000.0
    let timer = @bench.monotonic_clock_start()
    let json = @plan.plan_json(p)
    let json_ms = @bench.monotonic_clock_end(timer) / 1000.0
    // Separate overlapping probe: graph build + cycle check + topological order.
    // Already part of plan_ms; do not add this to the pipeline total.
    let timer = @bench.monotonic_clock_start()
    let graph = @plan.build_graph(m)
    let build_ms = @bench.monotonic_clock_end(timer) / 1000.0
    let timer_cycle = @bench.monotonic_clock_start()
    @plan.check_acyclic(graph)
    let cycle_ms = @bench.monotonic_clock_end(timer_cycle) / 1000.0
    let timer_topo = @bench.monotonic_clock_start()
    let order = @plan.topo_order(graph)
    let topo_ms = @bench.monotonic_clock_end(timer_topo) / 1000.0
    let graph_ms = @bench.monotonic_clock_end(timer) / 1000.0
    // Separate overlapping probes. Resolve endpoints outside the timers, then
    // reproduce flatten_func's per-endpoint table conversion and ABI work.
    // Neither probe is a disjoint phase of plan_ms; do not add or subtract them.
    let endpoints : Array[(@ir.FuncSig, Array[@ir.TypeDef?])] = []
    let mut expected_entries = 0
    for w in m.wires {
      let source = ifaces.get(w.from_component).unwrap()
      let sink = ifaces.get(w.to_component).unwrap()
      endpoints.push((
        @plan.resolve_port(source, ExportSide, w.from_port),
        source.types,
      ))
      endpoints.push((
        @plan.resolve_port(sink, ImportSide, w.to_port),
        sink.types,
      ))
      expected_entries = expected_entries + source.types.length() + sink.types.length()
    }
    let timer_tables = @bench.monotonic_clock_start()
    let mut table_entries = 0
    for (_, types) in endpoints {
      let table = @ir.to_model_table(types)
      keeper.keep(table)
      table_entries = table_entries + table.length()
    }
    let type_table_ms = @bench.monotonic_clock_end(timer_tables) / 1000.0
    let timer_flatten = @bench.monotonic_clock_start()
    let mut flat_values = 0
    for (sig, types) in endpoints {
      let flat = @ir.flatten_func(sig, types)
      keeper.keep(flat)
      match flat {
        Some((params, results)) =>
          flat_values = flat_values + params.length() + results.length()
        None => raise Failure("flatten probe failed")
      }
    }
    let flatten_ms = @bench.monotonic_clock_end(timer_flatten) / 1000.0
    let mut expected_values = 0
    for w in p.wires {
      expected_values = expected_values +
        w.from_flat_params.length() + w.from_flat_results.length() +
        w.to_flat_params.length() + w.to_flat_results.length()
    }
    if table_entries != expected_entries || flat_values != expected_values {
      raise Failure("type probe work differs from planned endpoints")
    }
    match golden {
      None => golden = Some(json)
      Some(expected) =>
        if json != expected {
          raise Failure("profile sample differs")
        }
    }
    if order.length() != p.instances.length() {
      raise Failure("graph size mismatch")
    }
    if sample > 0 {
      println(
        "{\"parse_ms\":\{parse_ms},\"decode_ms\":\{decode_ms},\"plan_ms\":\{plan_ms},\"json_ms\":\{json_ms},\"graph_probe_ms\":\{graph_ms},\"graph_build_ms\":\{build_ms},\"cycle_check_ms\":\{cycle_ms},\"topo_ms\":\{topo_ms},\"type_table_probe_ms\":\{type_table_ms},\"flatten_probe_ms\":\{flatten_ms},\"endpoint_count\":\{endpoints.length()},\"type_table_entries\":\{table_entries},\"flat_value_count\":\{flat_values}}",
      )
    }
    if sample == repeats {
      @fs.write_bytes_to_file(destination, @utf8.encode(json, bom=false))
    }
  }
}

///|
fn main {
  profile() catch {
    error => {
      println("error: \{error}")
      @sys.exit(1)
    }
  }
}
