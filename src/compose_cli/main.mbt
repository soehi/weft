///|
let usage = "weft-instance <plan|emit-wac> <manifest.json> [--out <file>] | seal <manifest.json> --out <plan.json> --lock <lock.json> | verify <plan.json> --lock <lock.json> --inputs <manifest.json> (experimental instance-sync-v1)"

///|
fn protocol_command(args : Array[String]) -> Unit raise {
  if args.length() != 6 || args[1] == "" || args[1].has_prefix("-") { raise Failure(usage) }
  let flags = if args[0] == "seal" { ["--out", "--lock"] } else { ["--lock", "--inputs"] }
  let values : Map[String, String] = Map([])
  for i = 2; i < args.length(); i = i + 2 {
    if !flags.contains(args[i]) || values.contains(args[i]) || args[i + 1] == "" || args[i + 1].has_prefix("-") {
      raise Failure("unknown, duplicate or empty option: " + args[i])
    }
    values.set(args[i], args[i + 1])
  }
  let lock_file = values.get("--lock").unwrap()
  if args[0] == "seal" {
    let out = values.get("--out").unwrap()
    if out == lock_file || out == args[1] || lock_file == args[1] { raise Failure("plan, lock and manifest filenames must differ") }
    let (source, binaries) = @host.read(args[1])
    let bundle = match @compose.seal(source, binaries) {
      Ok(bundle) => bundle
      Err(d) => raise Failure(@host.diagnostic(d))
    }
    @fs.write_bytes_to_file(out, @utf8.encode(bundle.plan_text, bom=false))
    @fs.write_bytes_to_file(lock_file, @utf8.encode(bundle.lock_text, bom=false))
  } else {
    let (_, binaries) = @host.read(values.get("--inputs").unwrap())
    let plan_text = @utf8.decode(@fs.read_file_to_bytes(args[1]), ignore_bom=false)
    let lock_text = @utf8.decode(@fs.read_file_to_bytes(lock_file), ignore_bom=false)
    match @compose.verify(plan_text, lock_text, binaries) {
      Ok(v) => {
        if v.canonical { println("valid canonical deployment") } else {
          println("valid noncanonical deployment")
          @sys.exit(2)
        }
      }
      Err(d) => raise Failure(@host.diagnostic(d))
    }
  }
}

///|
fn command(args : Array[String]) -> Unit raise {
  if args == ["--help"] || args == ["-h"] { println(usage); return }
  if !args.is_empty() && ["seal", "verify"].contains(args[0]) { protocol_command(args); return }
  if (args.length() != 2 && args.length() != 4) ||
     !["plan", "emit-wac"].contains(args[0]) || args[1].has_prefix("-") {
    raise Failure(usage)
  }
  let out = if args.length() == 4 {
    if args[2] != "--out" || args[3] == "" || args[3].has_prefix("-") { raise Failure("invalid --out") }
    Some(args[3])
  } else { None }
  let (text, binaries) = @host.read(args[1])
  let result = if args[0] == "plan" {
    match @compose.compile(text, binaries) {
      Ok(output) => output.json
      Err(d) => raise Failure(@host.diagnostic(d))
    }
  } else {
    match @compose.emit_wac(text, binaries) {
      Ok(wac) => wac
      Err(d) => raise Failure(@host.diagnostic(d))
    }
  }
  match out {
    Some(file) => @fs.write_bytes_to_file(file, @utf8.encode(result, bom=false))
    None => println(result)
  }
}

///|
fn main {
  let raw = @env.args()
  let args : Array[String] = []
  for i = offset(); i < raw.length(); i = i + 1 { args.push(raw[i]) }
  command(args) catch {
    error => {
      let message = match error { Failure(s) => s; _ => error.to_string() }
      println("error: " + message)
      @sys.exit(1)
    }
  }
}
