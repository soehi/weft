// Experimental native command, independently built from the portable planner CLI.

///|
let usage = "weft-native run <manifest.json> --component <name> --export <name> [--arg <kind>:<value>]..."

///|
fn command(args : Array[String]) -> String raise {
  if args.length() < 2 || args[0] != "run" || args[1].has_prefix("-") {
    raise Invalid(usage)
  }
  let manifest_path = args[1]
  let mut target : String? = None
  let mut port : String? = None
  let values : Array[@linker.ComponentValue] = []
  let mut i = 2
  while i < args.length() {
    let flag = args[i]
    if i + 1 >= args.length() {
      raise Invalid("missing value for \{flag}")
    }
    let value = args[i + 1]
    match flag {
      "--component" => {
        if target != None || value == "" || value.has_prefix("-") {
          raise Invalid("invalid or repeated --component")
        }
        target = Some(value)
      }
      "--export" => {
        if port != None || value == "" || value.has_prefix("-") {
          raise Invalid("invalid or repeated --export")
        }
        port = Some(value)
      }
      "--arg" => {
        let parts = value.split(":").map(v => v.to_string()).to_array()
        if parts.length() < 2 {
          raise Invalid("--arg requires kind:value")
        }
        let text = parts[1:].to_array().join(":")
        values.push(parse_arg(parts[0], text))
      }
      _ => raise Invalid("unknown option \{flag}")
    }
    i += 2
  }
  let target = match target {
    Some(v) => v
    None => raise Invalid("missing --component")
  }
  let port = match port {
    Some(v) => v
    None => raise Invalid("missing --export")
  }
  let text = @utf8.decode(
    @fs.read_file_to_bytes(manifest_path),
    ignore_bom=false,
  )
  let m = @manifest.parse(text)
  let binaries : Map[String, Bytes] = Map([])
  for c in m.components {
    let path = if @path.Path(c.path).is_absolute() {
      c.path
    } else {
      @path.Path::join(@path.Path(manifest_path).dirname(), @path.Path(c.path)).to_string()
    }
    let bytes = @fs.read_file_to_bytes(path) catch {
      @fs.IOError(s) => raise Invalid("cannot read \{c.name} at \{path}: \{s}")
    }
    binaries.set(c.name, bytes)
  }
  execute(text, binaries, target, port, values)
}

///|
fn main {
  let raw = @env.args()
  let args : Array[String] = []
  for i = 1; i < raw.length(); i = i + 1 {
    args.push(raw[i])
  }
  if args == ["--help"] || args == ["-h"] {
    println(usage)
  } else {
    let result = command(args) catch {
      error => {
        let message = match error {
          @fs.IOError(s) => s
          @manifest.InvalidJson(s) => s
          _ => error.to_string()
        }
        println("error: \{message}")
        @sys.exit(1)
        return
      }
    }
    println(result)
  }
}
