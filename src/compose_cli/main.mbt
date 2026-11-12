///|
let usage = "weft-instance <plan|emit-wac> <manifest.json> [--out <file>] (experimental instance-sync-v1)"

///|
fn command(args : Array[String]) -> Unit raise {
  if args == ["--help"] || args == ["-h"] { println(usage); return }
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
