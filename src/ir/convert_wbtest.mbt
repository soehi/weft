// IR decoding tests. Fixtures are built from WAT so no external tooling is
// needed, and they exercise: plain funcs, interfaces, rich value types, and
// flattening through the upstream canonical ABI.

///|
fn fixture_wat(wat : String) -> Bytes raise IrError {
  @text.parse_component_wat(wat) catch {
    e => raise DecodeFailed("fixture", "wat: \{e}")
  }
}

///|
fn decode_wat(name : String, wat : String) -> Iface raise IrError {
  decode_component(name, "\{name}.wasm", fixture_wat(wat))
}

///|
fn find_entry(entries : Array[PortEntry], name : String) -> PortEntry? {
  for e in entries {
    if e.name == name {
      return Some(e)
    }
  }
  None
}

///|
test "ir: plain function import and export" {
  let wat = "(component " +
    "(import \"host\" (func $h (param \"x\" s32) (result s32))) " +
    "(core module $M (memory (export \"mem\") 1) " +
    "(func (export \"f\") (param i32) (result i32) (i32.const 0)) " +
    "(func (export \"realloc\") (param i32 i32 i32 i32) (result i32) (i32.const 0))) " +
    "(core instance $m (instantiate $M)) " +
    "(func (export \"double\") (param \"v\" s32) (result s32) " +
    "(canon lift (core func $m \"f\") (memory $m \"mem\") (realloc (core func $m \"realloc\"))))" +
    ") "
  let iface = decode_wat("comp", wat) catch {
    e => fail(e.to_string())
  }
  inspect(iface.imports.length(), content="1")
  inspect(iface.exports.length(), content="1")
  match find_entry(iface.imports, "host") {
    Some(e) =>
      match e.port {
        Func(sig) => {
          inspect(sig.params.length(), content="1")
          inspect(sig.params[0].name, content="x")
          inspect(sig.params[0].ty, content="S32")
          debug_inspect(sig.result, content="Some(S32)")
        }
        Interface(_, _) => fail("host should be a func")
      }
    None => fail("missing import host")
  }
  match find_entry(iface.exports, "double") {
    Some(e) =>
      match e.port {
        Func(sig) => {
          inspect(sig.params[0].ty, content="S32")
          debug_inspect(sig.result, content="Some(S32)")
        }
        Interface(_, _) => fail("double should be a func")
      }
    None => fail("missing export double")
  }
}

///|
test "ir: interface import exposes nested functions" {
  let wat = "(component " +
    "(type $T (instance (export \"transform\" (func (param \"p\" s32) (result s32)))))" +
    "(import \"reader:io/transform@1.0.0\" (instance $io (type $T)))" +
    ") "
  let iface = decode_wat("comp", wat) catch {
    e => fail(e.to_string())
  }
  inspect(iface.imports.length(), content="1")
  match find_entry(iface.imports, "reader:io/transform@1.0.0") {
    Some(e) =>
      match e.port {
        Interface(name, funcs) => {
          let _ = name
          inspect(funcs.length(), content="1")
          inspect(funcs[0].name, content="transform")
          inspect(funcs[0].params[0].ty, content="S32")
        }
        Func(_) => fail("should be an interface")
      }
    None => fail("missing interface import")
  }
}

///|
test "ir: rich types survive the arena" {
  let wat = "(component " +
    "(core module $M (memory (export \"mem\") 1) " +
    "(func (export \"f\") (param i32 i32 i32) (result i32) (i32.const 0)) " +
    "(func (export \"realloc\") (param i32 i32 i32 i32) (result i32) (i32.const 0))) " +
    "(core instance $m (instantiate $M)) " +
    "(func (export \"rich\") (param \"xs\" (list u32)) (param \"flag\" bool) (result string) " +
    "(canon lift (core func $m \"f\") (memory $m \"mem\") (realloc (core func $m \"realloc\"))))" +
    ") "
  let iface = decode_wat("comp", wat) catch {
    e => fail(e.to_string())
  }
  match find_entry(iface.exports, "rich") {
    Some(e) =>
      match e.port {
        Func(sig) => {
          inspect(sig.params.length(), content="2")
          // list<u32> is an Index into the type table.
          match sig.params[0].ty {
            Index(i) =>
              match iface.types[i] {
                Some(List(_)) => ()
                _ => fail("expected list at index \{i}")
              }
            _ => fail("expected list<u32> to be indexed")
          }
          inspect(sig.params[1].ty, content="Bool")
          debug_inspect(sig.result, content="Some(String)")
        }
        Interface(_, _) => fail("rich should be a func")
      }
    None => fail("missing export rich")
  }
}

///|
test "ir: flatten list<u32> to two i32" {
  let wat = "(component " +
    "(core module $M (memory (export \"mem\") 1) " +
    "(func (export \"f\") (param i32 i32) (result i32) (i32.const 0)) " +
    "(func (export \"realloc\") (param i32 i32 i32 i32) (result i32) (i32.const 0))) " +
    "(core instance $m (instantiate $M)) " +
    "(func (export \"sum\") (param \"xs\" (list u32)) (result u32) " +
    "(canon lift (core func $m \"f\") (memory $m \"mem\") (realloc (core func $m \"realloc\"))))" +
    ") "
  let iface = decode_wat("comp", wat) catch {
    e => fail(e.to_string())
  }
  let sig = match find_entry(iface.exports, "sum") {
    Some({ port: Func(sig), name: _ }) => sig
    _ => fail("missing sum")
  }
  match flatten_func(sig, iface.types) {
    Some((params, results)) => {
      inspect(params.length(), content="2")
      inspect(params[0] == @core.I32, content="true")
      inspect(params[1] == @core.I32, content="true")
      inspect(results.length(), content="1")
      inspect(results[0] == @core.I32, content="true")
    }
    None => fail("sum should flatten")
  }
}

///|
test "ir: flatten string is ptr+len" {
  let wat = "(component " +
    "(core module $M (memory (export \"mem\") 1) " +
    "(func (export \"f\") (param i32 i32) (result i32) (i32.const 0)) " +
    "(func (export \"realloc\") (param i32 i32 i32 i32) (result i32) (i32.const 0))) " +
    "(core instance $m (instantiate $M)) " +
    "(func (export \"echo\") (param \"s\" string) (result string) " +
    "(canon lift (core func $m \"f\") (memory $m \"mem\") (realloc (core func $m \"realloc\"))))" +
    ") "
  let iface = decode_wat("comp", wat) catch {
    e => fail(e.to_string())
  }
  match flatten(String, iface.types) {
    Some(flat) => inspect(flat.length(), content="2")
    None => fail("string should flatten")
  }
}

///|
test "ir: decode failure names the component" {
  let bytes : Bytes = [0xFF, 0x00, 0x01, 0x02]
  let _ = decode_component("broken", "broken.wasm", bytes) catch {
    e => {
      inspect(e.to_string().has_prefix("ir: cannot decode `broken`:"), content="true")
      return
    }
  }
  fail("expected a decode failure")
}

///|
test "ir: exports are sorted by name" {
  let wat = "(component " +
    "(core module $M (memory (export \"mem\") 1) " +
    "(func (export \"f\") (param i32) (result i32) (i32.const 0)) " +
    "(func (export \"realloc\") (param i32 i32 i32 i32) (result i32) (i32.const 0))) " +
    "(core instance $m (instantiate $M)) " +
    "(func (export \"zeta\") (param \"v\" s32) (result s32) " +
    "(canon lift (core func $m \"f\") (memory $m \"mem\") (realloc (core func $m \"realloc\")))) " +
    "(func (export \"alpha\") (param \"v\" s32) (result s32) " +
    "(canon lift (core func $m \"f\") (memory $m \"mem\") (realloc (core func $m \"realloc\"))))" +
    ") "
  let iface = decode_wat("comp", wat) catch {
    e => fail(e.to_string())
  }
  inspect(iface.exports.length(), content="2")
  inspect(iface.exports[0].name, content="alpha")
  inspect(iface.exports[1].name, content="zeta")
}