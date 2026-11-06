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
  /// `run <manifest.json>` — native only in substance.
  Run(String)
  /// Anything we could not interpret, with a message.
  Unknown(String)
}

///|
/// Parse argv (already stripped of the program name).
pub fn parse_args(args : Array[String]) -> Command {
  if args.length() == 0 {
    return Help
  }
  let cmd = args[0]
  let rest : Array[String] = []
  let mut i = 1
  while i < args.length() {
    rest.push(args[i])
    i = i + 1
  }
  match cmd {
    "plan" => {
      match positional(rest) {
        Some(m) => Plan(m, option_value(rest, "--out"))
        None => Unknown("plan needs a manifest path")
      }
    }
    "convert" => {
      match positional(rest) {
        Some(w) => Convert(w, dep_pairs(rest), option_value(rest, "--out"))
        None => Unknown("convert needs a WAC file path")
      }
    }
    "emit-wac" => {
      match positional(rest) {
        Some(m) => EmitWac(m, option_value(rest, "--out"))
        None => Unknown("emit-wac needs a manifest path")
      }
    }
    "run" =>
      match positional(rest) {
        Some(m) => Run(m)
        None => Unknown("run needs a manifest path")
      }
    "help" | "--help" | "-h" => Help
    _ => Unknown("unknown command `\{cmd}`")
  }
}

///|
/// First non-flag, non-option-value argument.
fn positional(args : Array[String]) -> String? {
  let mut i = 0
  while i < args.length() {
    let a = args[i]
    if a == "--out" {
      i = i + 2
      continue
    }
    if a == "--dep" {
      i = i + 2
      continue
    }
    if !a.has_prefix("--") {
      return Some(a)
    }
    i = i + 1
  }
  None
}

///|
fn option_value(args : Array[String], name : String) -> String? {
  let mut i = 0
  while i < args.length() {
    if args[i] == name && i + 1 < args.length() {
      return Some(args[i + 1])
    }
    i = i + 1
  }
  None
}

///|
/// Collect `--dep name=path` pairs.
fn dep_pairs(args : Array[String]) -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  let mut i = 0
  while i < args.length() {
    if args[i] == "--dep" && i + 1 < args.length() {
      let spec = args[i + 1]
      let mut eq = -1
      let mut j = 0
      for c in spec {
        if c == '=' {
          eq = j
          break
        }
        j = j + 1
      }
      if eq > 0 && eq + 1 < spec.length() {
        out.push((spec[:eq].to_owned(), spec[eq + 1 :].to_owned()))
      }
      i = i + 2
    } else {
      i = i + 1
    }
  }
  out
}

///|
pub let help_text : String =
  #|edgeplan — a backend-portable planner for WebAssembly Component deployment.
  #|
  #|Usage:
  #|  edgeplan plan <manifest.json> [--out <file>]
  #|      Validate the manifest and its component binaries, then print the
  #|      deterministic instantiation plan as JSON.
  #|
  #|  edgeplan emit-wac <manifest.json> [--out <file>]
  #|      Render the manifest as WAC, for composition with external tooling.
  #|
  #|  edgeplan convert <file.wac> --dep <ns:name>=<path> [--dep ...] [--out <file>]
  #|      Convert a WAC composition into this tool's manifest format. Every
  #|      instantiated package must be supplied with --dep.
  #|
  #|  edgeplan run <manifest.json>
  #|      Execute a planned linear chain. Requires the native runtime adapter;
  #|      on wasm-gc/js this prints a diagnostic instead.
  #|
  #|Notes:
  #|  * Plans are byte-identical across native, wasm-gc and js.
  #|  * The planner checks function-level canonical signatures only; resource
  #|    and async semantics are out of scope.
  #|