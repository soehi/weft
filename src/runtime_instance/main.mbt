///|
let usage = "weft-instance-native run <manifest.json> --component <name> --export <name> --arg u32:<value> | run-locked <plan.json> --lock <lock.json> --inputs <manifest.json> --component <name> --export <name> --arg u32:<value>"

///|
fn command(args : Array[String]) -> UInt32 raise {
  if args.length() < 2 { raise Failure(usage) }
  let locked = args[0] == "run-locked"
  if (if locked { args.length() != 12 } else { args[0] != "run" || args.length() != 8 }) || args[1] == "" || args[1].has_prefix("-") { raise Failure(usage) }
  let flags = if locked { ["--component", "--export", "--arg", "--lock", "--inputs"] } else { ["--component", "--export", "--arg"] }
  let values : Map[String, String] = Map([])
  for i = 2; i < args.length(); i = i + 2 {
    let flag = args[i]
    let value = args[i + 1]
    if !flags.contains(flag) || values.contains(flag) || value == "" {
      raise Failure("unknown, duplicate or empty option: " + flag)
    }
    values.set(flag, value)
  }
  let target = values.get("--component").unwrap()
  let port = values.get("--export").unwrap()
  let arg = values.get("--arg").unwrap()
  if !arg.has_prefix("u32:") { raise Failure("only --arg u32:<value> is supported") }
  let value = @strparse.parse_uint(arg[4:])
  if locked {
    let (_, binaries) = @host.read(values.get("--inputs").unwrap())
    let plan_text = @utf8.decode(@fs.read_file_to_bytes(args[1]), ignore_bom=false)
    let lock_text = @utf8.decode(@fs.read_file_to_bytes(values.get("--lock").unwrap()), ignore_bom=false)
    execute_deployment(plan_text, lock_text, binaries, target, port, value)
  } else {
    let (text, binaries) = @host.read(args[1])
    execute(text, binaries, target, port, value)
  }
}

///|
fn main {
  let raw = @env.args()
  let args : Array[String] = []
  for i = 1; i < raw.length(); i = i + 1 { args.push(raw[i]) }
  if args == ["--help"] || args == ["-h"] { println(usage); return }
  let result = command(args) catch {
    error => {
      let message = match error { Invalid(s) | Runtime(s) | Failure(s) => s; _ => error.to_string() }
      println("error: " + message)
      @sys.exit(1)
      return
    }
  }
  println(result.to_string())
}
