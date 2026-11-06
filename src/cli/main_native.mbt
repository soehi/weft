// Native entry point: reads files from disk and writes the plan out.
//
// The `run` subcommand is delegated to `runtime_native`, which is the only
// place `wasmoon` is imported.

///|
/// Render any of the errors the CLI can surface, without relying on `Show`.
fn msg_of(e : Error) -> String {
  match e {
    @fs.IOError(m) => m
    @manifest.InvalidJson(m) => m
    Failure(m) => m
    m => m.to_string()
  }
}

///|
/// Resolve a manifest-relative path against the manifest's own directory, so
/// `edgeplan plan examples/chain.json` works from any working directory.
fn resolve_beside(manifest_path : String, rel : String) -> String {
  // Absolute paths (POSIX or Windows drive) are used as-is.
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
fn die(msg : String) -> Unit {
  println("error: \{msg}")
  // A failed command must be observable to a script; printing an error and
  // exiting 0 would let `set -e` pipelines continue.
  @sys.exit(1)
}

///|
fn emit(text : String, out : String?) -> Unit {
  match out {
    Some(path) =>
      @fs.write_string_to_file(path, text) catch {
        e => die("cannot write \{path}: " + msg_of(e))
      }
    None => println(text)
  }
}

///|
fn read_text(path : String) -> String raise {
  @fs.read_file_to_string(path) catch {
    e => raise Failure("cannot read \{path}: " + msg_of(e))
  }
}

///|
fn read_component_binaries(manifest_path : String, m : @manifest.Manifest) -> Map[String, Bytes] raise {
  let out : Map[String, Bytes] = Map([])
  for c in m.components {
    let full = resolve_beside(manifest_path, c.path)
    let bytes = @fs.read_file_to_bytes(full) catch {
      e => raise Failure("cannot read component `" + c.name + "` from " + full + ": " + msg_of(e))
    }
    out.set(c.name, bytes)
  }
  out
}

///|
fn run_command(cmd : Command) -> Unit {
  match cmd {
    Help => println(help_text)
    Unknown(msg) => {
      // `Unknown` is overloaded as a diagnostic holder.
      if msg.has_prefix("unknown command") {
        die(msg)
        println(help_text)
      } else {
        die(msg)
      }
    }
    Plan(manifest_path, out) => {
      let text = read_text(manifest_path) catch {
        e => {
          die(msg_of(e))
          return
        }
      }
      let m = @manifest.parse(text) catch {
        e => {
          die(msg_of(e))
          return
        }
      }
      let bins = read_component_binaries(manifest_path, m) catch {
        e => {
          die(msg_of(e))
          return
        }
      }
      let r = cmd_plan(text, bins)
      if r.ok {
        emit(r.text, out)
      } else {
        die(r.text)
      }
    }
    EmitWac(manifest_path, out) => {
      let text = read_text(manifest_path) catch {
        e => {
          die(msg_of(e))
          return
        }
      }
      let r = cmd_emit_wac(text)
      if r.ok {
        emit(r.text, out)
      } else {
        die(r.text)
      }
    }
    Convert(wac_path, deps, out) => {
      let wac_text = read_text(wac_path) catch {
        e => {
          die(msg_of(e))
          return
        }
      }
      let dep_bytes : Array[(String, Bytes)] = []
      for (name, path) in deps {
        let bytes = @fs.read_file_to_bytes(path) catch {
          e => {
            die("cannot read dependency " + name + " from " + path + ": " + msg_of(e))
            return
          }
        }
        dep_bytes.push((name, bytes))
      }
      let r = cmd_convert(wac_text, dep_bytes)
      if r.ok {
        emit(r.text, out)
      } else {
        die(r.text)
      }
    }
    Run(manifest_path) => {
      let text = read_text(manifest_path) catch {
        e => {
          die(msg_of(e))
          return
        }
      }
      let m = @manifest.parse(text) catch {
        e => {
          die(msg_of(e))
          return
        }
      }
      let bins = read_component_binaries(manifest_path, m) catch {
        e => {
          die(msg_of(e))
          return
        }
      }
      match run_plan(text, bins) {
        Ok(summary) => println(summary)
        Err(msg) => die(msg)
      }
    }
  }
}

///|
fn main {
  let args = @env.args()
  // Drop the executable path (native) or node + script (js under `moon run`);
  // the CLI consumes only flags and paths after the subcommand name.
  let mut start = 1
  while start < args.length() && args[start].has_prefix("--") {
    start = start + 1
  }
  // `@env.args()` on native is [exe, sub, ...]; on `moon run` for js it is
  // [node, script, sub, ...]. Locating the first known subcommand handles both
  // without guessing the offset.
  let known = ["plan", "emit-wac", "convert", "run", "help", "--help", "-h"]
  let mut si = -1
  let mut i = 1
  while i < args.length() {
    let mut hit = false
    for k in known {
      if args[i] == k {
        hit = true
      }
    }
    if hit {
      si = i
      break
    }
    i = i + 1
  }
  let sub_args = if si < 0 {
    []
  } else {
    let out : Array[String] = []
    let mut j = si
    while j < args.length() {
      out.push(args[j])
      j = j + 1
    }
    out
  }
  let _ = start
  run_command(parse_args(sub_args))
}