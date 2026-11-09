// A real component with N-1 independent scalar function imports.

///|
fn main {
  let dir = @env.args()[1]
  try {
    for size in [100, 1000] {
      let wat = StringBuilder()
      wat.write_string("(component ")
      for i in 0..<(size - 1) {
        wat.write_string(
          "(import \"in-\{i}\" (func (param \"x\" u32) (result u32))) ",
        )
      }
      wat.write_string(")")
      let bytes = @text.parse_component_wat(wat.to_string())
      @fs.write_bytes_to_file("\{dir}/fanin-\{size}.wasm", bytes)
    }
  } catch {
    error => {
      println(error.to_string())
      @sys.exit(1)
    }
  }
}
