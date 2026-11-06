// Emit the three example components plus the example manifest.
//
// Each component is a real, valid component binary built from WAT via
// `wasm_component/text`, so `edgeplan plan examples/chain.json` is an honest
// end-to-end run rather than a mock.

///|
fn io_msg(e : @fs.IOError) -> String {
  match e {
    @fs.IOError(m) => m
  }
}

///|
/// A component exporting `read: (s32) -> s32`, core `(i32) -> i32`.
fn reader_wat() -> String {
  "(component " +
  "(core module $M (memory (export \"mem\") 1) " +
  "(func (export \"f\") (param i32) (result i32) (i32.const 0)) " +
  "(func (export \"realloc\") (param i32 i32 i32 i32) (result i32) (i32.const 0))) " +
  "(core instance $m (instantiate $M)) " +
  "(func (export \"read\") (param \"x\" s32) (result s32) " +
  "(canon lift (core func $m \"f\") (memory $m \"mem\") " +
  "(realloc (core func $m \"realloc\"))))" +
  ")"
}

///|
/// A component importing `in` and exporting `out`, both `(s32) -> s32`.
fn filter_wat() -> String {
  "(component " +
  "(import \"in\" (func $in (param \"x\" s32) (result s32))) " +
  "(export \"out\" (func $in))" +
  ")"
}

///|
/// A component importing `in: (s32) -> s32`.
fn sink_wat() -> String {
  "(component " +
  "(import \"in\" (func (param \"x\" s32) (result s32)))" +
  ")"
}

///|
fn write_wat(dir : String, name : String, wat : String) -> Unit raise {
  let bytes = @text.parse_component_wat(wat) catch {
    e => raise Failure("cannot assemble \{name}: \{e}")
  }
  @fs.write_bytes_to_file("\{dir}/\{name}.wasm", bytes) catch {
    e => raise Failure("cannot write \{name}.wasm: " + io_msg(e) + "")
  }
  println("wrote \{dir}/\{name}.wasm (\{bytes.length()} bytes)")
}

///|
fn main {
  let args = @env.args()
  // First non-flag argument after the program name is the output directory.
  let mut dir = "examples"
  let mut i = 1
  while i < args.length() {
    if !args[i].has_prefix("-") {
      dir = args[i]
      break
    }
    i = i + 1
  }
  write_wat(dir, "reader", reader_wat()) catch {
    e => {
      println("error: \{e}")
      return
    }
  }
  write_wat(dir, "filter", filter_wat()) catch {
    e => {
      println("error: \{e}")
      return
    }
  }
  write_wat(dir, "sink", sink_wat()) catch {
    e => {
      println("error: \{e}")
      return
    }
  }
  let manifest =
    #|{
    #|  "version": "0.1.0",
    #|  "components": [
    #|    { "name": "reader", "path": "reader.wasm" },
    #|    { "name": "filter", "path": "filter.wasm" },
    #|    { "name": "sink",   "path": "sink.wasm" }
    #|  ],
    #|  "wires": [
    #|    { "from": "reader.read", "to": "filter.in" },
    #|    { "from": "filter.out", "to": "sink.in" }
    #|  ],
    #|  "resources": { "max_memory_pages": 256, "quota": 1000000 }
    #|}
  @fs.write_string_to_file("\{dir}/chain.json", manifest) catch {
    e => {
      println("error: cannot write chain.json: " + io_msg(e))
      return
    }
  }
  println("wrote \{dir}/chain.json")
}