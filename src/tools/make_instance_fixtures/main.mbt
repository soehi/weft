///|
fn main {
  try {
    let args = @env.args()
    if args.length() != 2 { raise Failure("expected an existing output directory") }
    let dir = args[1]
    for mode in ["source", "alternate", "missing", "wrong-type"] {
      @fs.write_bytes_to_file("\{dir}/\{mode}.wasm", @fixture.provider(mode))
    }
    @fs.write_bytes_to_file("\{dir}/consumer.wasm", @fixture.consumer())
    @fs.write_bytes_to_file("\{dir}/function-consumer.wasm", @fixture.function_consumer())
  } catch {
    error => {
      println(error.to_string())
      @sys.exit(1)
    }
  }
}
