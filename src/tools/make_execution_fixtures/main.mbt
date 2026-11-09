///|
fn source(delta : Int32) -> Bytes raise {
  @text.parse_component_wat(
    (
      $|(component
      $| (core module $m
      $|  (func (export "inc") (param i32) (result i32)
      $|   local.get 0 i32.const \{delta} i32.add))
      $| (core instance $i (instantiate $m))
      $| (func (export "inc") (param "x" u32) (result u32)
      $|  (canon lift (core func $i "inc"))))
    ),
  )
}

///|
fn consumer() -> Bytes raise {
  @text.parse_component_wat(
    (
      #|(component
      #| (import "inc" (func $inc (param "x" u32) (result u32)))
      #| (core func $lower (canon lower (func $inc)))
      #| (core module $m
      #|  (import "env" "inc" (func $inc (param i32) (result i32)))
      #|  (func (export "run") (param i32) (result i32)
      #|   local.get 0 call $inc i32.const 2 i32.mul))
      #| (core instance $i (instantiate $m
      #|  (with "env" (instance (export "inc" (func $lower))))))
      #| (func (export "run") (param "x" u32) (result u32)
      #|  (canon lift (core func $i "run"))))
    ),
  )
}

///|
fn main {
  let args = @env.args()
  let dir = args[1]
  try {
    @fs.write_bytes_to_file("\{dir}/source.wasm", source(1))
    @fs.write_bytes_to_file("\{dir}/alternate.wasm", source(2))
    @fs.write_bytes_to_file("\{dir}/consumer.wasm", consumer())
    let trap = @text.parse_component_wat(
      "(component (core module $m (func (export \"run\") unreachable)) (core instance $i (instantiate $m)) (func (export \"run\") (canon lift (core func $i \"run\"))))",
    )
    @fs.write_bytes_to_file("\{dir}/trap.wasm", trap)
  } catch {
    error => {
      println(error.to_string())
      @sys.exit(1)
    }
  }
}
