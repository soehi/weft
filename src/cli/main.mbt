// Shared CLI I/O entry point for native, wasm-gc and js.

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
/// `weft plan examples/chain.json` works from any working directory.
fn resolve_beside(manifest_path : String, rel : String) -> String {
  if @path.Path(rel).is_absolute() {
    rel
  } else {
    @path.Path::join(@path.Path(manifest_path).dirname(), @path.Path(rel)).to_string()
  }
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
fn read_component_binaries(
  manifest_path : String,
  m : @manifest.Manifest,
) -> Map[String, Bytes] raise {
  let out : Map[String, Bytes] = Map([])
  for c in m.components {
    let full = resolve_beside(manifest_path, c.path)
    let bytes = @fs.read_file_to_bytes(full) catch {
      e =>
        raise Failure(
          "cannot read component `" +
          c.name +
          "` from " +
          full +
          ": " +
          msg_of(e),
        )
    }
    out.set(c.name, bytes)
  }
  out
}

///|
fn run_command(cmd : Command) -> Unit {
  match cmd {
    Help => println(help_text)
    Unknown(msg) =>
      // `Unknown` is overloaded as a diagnostic holder.
      if msg.has_prefix("unknown command") {
        die(msg)
        println(help_text)
      } else {
        die(msg)
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
      let dep_bytes : Array[@wac.WacDep] = []
      for (key, path) in deps {
        let full = @path.Path::resolve(@path.Path(path)).to_string()
        let bytes = @fs.read_file_to_bytes(full) catch {
          e => {
            die(
              "cannot read dependency " +
              key +
              " from " +
              full +
              ": " +
              msg_of(e),
            )
            return
          }
        }
        let (name, version) = dependency_name(key)
        dep_bytes.push({ name, version, path: full, bytes, })
      }
      let r = cmd_convert(wac_text, dep_bytes)
      if r.ok {
        emit(r.text, out)
      } else {
        die(r.text)
      }
    }
    Run(_) =>
      die(
        "run is unsupported: real cross-instance wiring has not been verified. Use `weft plan` to generate a plan.",
      )
  }
}

///|
fn main {
  let args = @env.args()
  let sub_args : Array[String] = []
  for i = argv_offset(); i < args.length(); i = i + 1 {
    sub_args.push(args[i])
  }
  run_command(parse_args(sub_args))
}
