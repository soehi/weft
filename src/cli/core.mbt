// CLI core: argument parsing and the pure subcommands. Shared by the native and
// wasm/js entry points so both exercise the same planner code.

///|
/// Parsed command line.
pub(all) enum Command {
  Help
  /// `plan <manifest.json> [--out <file>]`
  Plan(String, String?)
  /// `convert <file.wac> --dep <name>=<path>... [--out <file>]`
  Convert(String, Array[(String, String)], String?)
  /// `emit-wac <manifest.json> [--out <file>]`
  EmitWac(String, String?)
  /// `run <manifest.json>` — reserved until real wiring is supported.
  Run(String)
  /// Anything we could not interpret, with a message.
  Unknown(String)
}

///|
/// Parse every argument once; malformed input must never fall through to I/O.
pub fn parse_args(args : Array[String]) -> Command {
  if args.length() == 0 {
    return Help
  }
  let cmd = args[0]
  if cmd == "help" || cmd == "--help" || cmd == "-h" {
    return if args.length() == 1 {
      Help
    } else {
      Unknown("help takes no arguments")
    }
  }
  if cmd != "plan" && cmd != "emit-wac" && cmd != "convert" && cmd != "run" {
    return Unknown("unknown command `\{cmd}`")
  }
  let mut input : String? = None
  let mut out : String? = None
  let deps : Array[(String, String)] = []
  let seen : Map[String, Unit] = Map([])
  let mut i = 1
  while i < args.length() {
    let a = args[i]
    if a == "--out" || a == "--dep" {
      if (a == "--dep" && cmd != "convert") || (a == "--out" && cmd == "run") {
        return Unknown("option `\{a}` is not supported by \{cmd}")
      }
      if i + 1 >= args.length() ||
        args[i + 1].has_prefix("-") ||
        args[i + 1] == "" {
        return Unknown("\{a} needs a value")
      }
      let value = args[i + 1]
      if a == "--out" {
        if out is Some(_) {
          return Unknown("duplicate --out")
        }
        out = Some(value)
      } else {
        let parts = value.split("=").to_array()
        if parts.length() < 2 || parts[0] == "" {
          return Unknown("--dep expects <ns:name>[@version]=<path>")
        }
        let key = parts[0].to_owned()
        let path = value[key.length() + 1:].to_owned()
        let (name, version) = dependency_name(key)
        let names = name.split(":").to_array()
        if names.length() != 2 ||
          names[0] == "" ||
          names[1] == "" ||
          path == "" ||
          version == Some("") ||
          key.split("@").count() > 2 ||
          key.contains(" ") ||
          key.contains("\n") {
          return Unknown(
            "invalid --dep `\{value}`; expected <ns:name>[@version]=<path>",
          )
        }
        if seen.contains(key) {
          return Unknown("duplicate dependency `\{key}`")
        }
        seen.set(key, ())
        deps.push((key, path))
      }
      i = i + 2
    } else if a.has_prefix("-") {
      return Unknown("unknown option `\{a}`")
    } else {
      if input is Some(_) {
        return Unknown("unexpected positional argument `\{a}`")
      }
      input = Some(a)
      i = i + 1
    }
  }
  let path = match input {
    Some(p) => p
    None => return Unknown("\{cmd} needs an input path")
  }
  match cmd {
    "plan" => Plan(path, out)
    "emit-wac" => EmitWac(path, out)
    "convert" => Convert(path, deps, out)
    _ => Run(path)
  }
}

///|
fn dependency_name(key : String) -> (String, String?) {
  let parts = key.split("@").to_array()
  if parts.length() == 1 {
    (key, None)
  } else {
    (parts[0].to_owned(), Some(key[parts[0].length() + 1:].to_owned()))
  }
}

///|
pub let help_text : String =
  #|weft — a backend-portable planner for WebAssembly Component deployment.
  #|
  #|Usage:
  #|  weft plan <manifest.json> [--out <file>]
  #|      Validate the manifest and its component binaries, then print the
  #|      deterministic instantiation plan as JSON.
  #|
  #|  weft emit-wac <manifest.json> [--out <file>]
  #|      Render a DAG as WAC; names/ports must be lowercase kebab names.
  #|      Resource policies and interface paths cannot be preserved and are rejected.
  #|
  #|  weft convert <file.wac> --dep <ns:name>[@version]=<path> [--dep ...] [--out <file>]
  #|      Convert a WAC composition into this tool's manifest format. Every
  #|      instantiated package must be supplied with --dep. Paths are relative
  #|      to the invocation directory; emitted component paths are absolute.
  #|      Default output is stdout; --out is relative to the invocation directory.
  #|
  #|  weft run <manifest.json>
  #|      Unsupported on every backend until real cross-instance wiring is verified.
  #|
  #|Notes:
  #|  * Plans are byte-identical across native, wasm-gc and js.
  #|  * Wires require matching synchronous component-value types and canonical ABI.
  #|    Async, resources and other unsupported value semantics are rejected.
  #|  * Every function import needs exactly one wire; implicit host imports,
  #|    interface instance imports and other non-function imports are rejected.
  #|
