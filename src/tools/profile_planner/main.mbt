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
    @plan.check_acyclic(graph)
    let order = @plan.topo_order(graph)
    let graph_ms = @bench.monotonic_clock_end(timer) / 1000.0
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
        "{\"parse_ms\":\{parse_ms},\"decode_ms\":\{decode_ms},\"plan_ms\":\{plan_ms},\"json_ms\":\{json_ms},\"graph_probe_ms\":\{graph_ms}}",
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
