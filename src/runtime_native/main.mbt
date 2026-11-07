// `weft-run <manifest.json> --call <port> [--arg <kind>:<value>]...`
//
// Thin driver: load the manifest, run the portable planner, then hand the plan
// to the wasmoon executor. All the interesting logic lives outside wasmoon, so
// the same plan can also be exported to WAC and run by external tooling.

///|
fn io_msg(e : @fs.IOError) -> String {
  match e {
    @fs.IOError(m) => m
  }
}

///|
fn read_text(path : String) -> String raise {
  @fs.read_file_to_string(path) catch {
    e => raise Failure("cannot read \{path}: " + io_msg(e))
  }
}

///|
fn resolve_beside(manifest_path : String, rel : String) -> String {
  if rel.has_prefix("/") || (rel.length() >= 2 && rel.get_char(1) == Some(':')) {
    return rel
  }
  let mut cut = -1
  let mut i = 0
  for c in manifest_path {
    if c == '/' || c == '\u{5c}' {
      cut = i
    }
    i = i + 1
  }
  if cut < 0 {
    return rel
  }
  manifest_path[:cut + 1].to_owned() + rel
}

///|
fn main {
  let args = @env.args()
  let mut manifest_path = ""
  let mut call_port = ""
  let arg_specs : Array[String] = []
  let mut i = 1
  while i < args.length() {
    let a = args[i]
    if a == "--call" && i + 1 < args.length() {
      call_port = args[i + 1]
      i = i + 2
    } else if a == "--arg" && i + 1 < args.length() {
      arg_specs.push(args[i + 1])
      i = i + 2
    } else if manifest_path == "" && !a.has_prefix("--") {
      manifest_path = a
      i = i + 1
    } else {
      i = i + 1
    }
  }
  if manifest_path == "" || call_port == "" {
    println(
      "usage: weft-run <manifest.json> --call <port> [--arg <kind>:<value>]...",
    )
    return
  }
  let text = read_text(manifest_path) catch {
    e => {
      println("error: \{e}")
      return
    }
  }
  let m = @manifest.parse(text) catch {
    e => {
      println("error: \{e.to_string()}")
      return
    }
  }
  let ifaces : Map[String, @ir.Iface] = Map([])
  let binaries : Map[String, Bytes] = Map([])
  for c in m.components {
    let full = resolve_beside(manifest_path, c.path)
    let bytes = @fs.read_file_to_bytes(full) catch {
      e => {
        println("error: cannot read \{full}: " + io_msg(e))
        return
      }
    }
    binaries.set(c.path, bytes)
    let iface = @ir.decode_component(c.name, c.path, bytes) catch {
      e => {
        println("error: \{e.to_string()}")
        return
      }
    }
    ifaces.set(c.name, iface)
  }
  let p = @plan.plan({ manifest: m, ifaces }) catch {
    e => {
      println("error: \{e.to_string()}")
      return
    }
  }
  println("plan hash: \{p.hash}")
  let argv : Array[@component.ComponentValue] = []
  for spec in arg_specs {
    // `<kind>:<value>`
    let mut colon = -1
    let mut j = 0
    for c in spec {
      if c == ':' {
        colon = j
        break
      }
      j = j + 1
    }
    if colon <= 0 {
      println("error: --arg expects <kind>:<value>, got `\{spec}`")
      return
    }
    let kind = spec[:colon].to_owned()
    let val = spec[colon + 1 :].to_owned()
    let v = parse_arg(kind, val) catch {
      e => {
        println("error: " + e.to_string())
        return
      }
    }
    argv.push(v)
  }
  let out = execute_chain(p, binaries, call_port, argv) catch {
    e => {
      println("error: \{e.to_string()}")
      return
    }
  }
  println("result: \{out}")
}
