// WAC adapter tests: WAC -> manifest from a verified composition, and
// manifest -> WAC rendering.

///|
fn s32_component(func : String) -> String {
  "(component " +
  "(core module $M (memory (export \"mem\") 1) " +
  "(func (export \"f\") (param i32) (result i32) (i32.const 0)) " +
  "(func (export \"realloc\") (param i32 i32 i32 i32) (result i32) (i32.const 0))) " +
  "(core instance $m (instantiate $M)) " +
  "(func (export \"\{func}\") (param \"x\" s32) (result s32) " +
  "(canon lift (core func $m \"f\") (memory $m \"mem\") " +
  "(realloc (core func $m \"realloc\"))))" +
  ")"
}

///|
fn import_export_component() -> String {
  "(component " +
  "(import \"in\" (func $in (param \"x\" s32) (result s32))) " +
  "(export \"out\" (func $in))" +
  ")"
}

///|
fn wasm_of(wat : String) -> Bytes raise {
  @text.parse_component_wat(wat) catch {
    e => raise Failure("wat: \{e}")
  }
}

///|
fn wac_err(source : String, deps : Array[WacDep]) -> String {
  let _ = wac_to_manifest(source, deps) catch {
    e => {
      return e.to_string()
    }
  }
  "<no error>"
}

///|
test "wac: single instantiation becomes one manifest component" {
  let source = "package app:main; " +
    "let r = new components:reader@1.0.0 {}; export r as \"reader\";"
  let deps = [
    { name: "components:reader", version: Some("1.0.0"), path: "reader.wasm", bytes: wasm_of(s32_component("read")) catch {
      e => fail(e.to_string())
    } },
  ]
  let m = wac_to_manifest(source, deps) catch {
    e => fail(e.to_string())
  }
  inspect(m.components.length(), content="1")
  inspect(m.components[0].name, content="reader")
  inspect(m.components[0].path, content="reader.wasm")
  inspect(m.wires.length(), content="0")
}

///|
test "wac: access argument becomes a wire" {
  let source = "package app:main; " +
    "let r = new components:reader@1.0.0 {}; " +
    "let f = new components:filter@1.0.0 { in: r.read }; " +
    "export r as \"reader\"; export f as \"filter\";"
  let deps = [
    { name: "components:reader", version: Some("1.0.0"), path: "reader.wasm", bytes: wasm_of(s32_component("read")) catch {
      e => fail(e.to_string())
    } },
    { name: "components:filter", version: Some("1.0.0"), path: "filter.wasm", bytes: wasm_of(import_export_component()) catch {
      e => fail(e.to_string())
    } },
  ]
  let m = wac_to_manifest(source, deps) catch {
    e => fail(e.to_string())
  }
  inspect(m.components.length(), content="2")
  inspect(m.wires.length(), content="1")
  inspect(m.wires[0].from_component, content="reader")
  inspect(m.wires[0].from_port, content="read")
  inspect(m.wires[0].to_component, content="filter")
  inspect(m.wires[0].to_port, content="in")
}

///|
test "wac: missing dependency is named" {
  let source = "package app:main; let r = new components:ghost {}; export r as \"g\";"
  // The upstream verifier rejects the unresolved package first; the diagnostic
  // still names it.
  let msg = wac_err(source, [])
  inspect(msg.has_prefix("wac: verification failed:"), content="true")
  inspect(msg.contains("components:ghost"), content="true")
}

///|
test "wac: syntax error is reported as parse failure" {
  let msg = wac_err("package ;", [])
  inspect(msg.has_prefix("wac: parse failed:"), content="true")
}

///|
test "wac: version listed in source must match the supplied version" {
  let source = "package app:main; let r = new components:reader@1.0.0 {}; export r as \"reader\";"
  let deps = [
    { name: "components:reader", version: Some("1.0.0"), path: "reader.wasm", bytes: wasm_of(s32_component("read")) catch {
      e => fail(e.to_string())
    } },
  ]
  let m = wac_to_manifest(source, deps) catch {
    e => fail(e.to_string())
  }
  inspect(m.components[0].name, content="reader")
}

///|
test "emit-wac: renders wiring in instantiation order" {
  let m = @manifest.parse(
    (
      #|{"components":[
      #|  {"name":"reader","path":"reader.wasm"},
      #|  {"name":"filter","path":"filter.wasm"}],
      #| "wires":[{"from":"reader.read","to":"filter.in"}]}
    ),
  ) catch {
    e => fail(e.to_string())
  }
  let wac = manifest_to_wac(m)
  inspect(wac.has_prefix("package weft:generated;"), content="true")
  inspect(wac.contains("let reader = new weft:reader {};"), content="true")
  inspect(
    wac.contains("let filter = new weft:filter { in: reader.read };"),
    content="true",
  )
  inspect(wac.contains("export reader as \"reader\";"), content="true")
}

///|
test "emit-wac: instance names are sanitized" {
  inspect(instance_name("a.b:c/d@1"), content="a_b_c_d_1")
  inspect(instance_name("plain"), content="plain")
}

///|
test "short_name strips the namespace" {
  inspect(short_name("components:reader"), content="reader")
  inspect(short_name("bare"), content="bare")
}

///|
test "wac round trip: manifest -> wac -> plan works" {
  let m = @manifest.parse(
    (
      #|{"components":[
      #|  {"name":"reader","path":"reader.wasm"},
      #|  {"name":"filter","path":"filter.wasm"}],
      #| "wires":[{"from":"reader.read","to":"filter.in"}]}
    ),
  ) catch {
    e => fail(e.to_string())
  }
  let wac_text = manifest_to_wac(m)
  // The generated WAC must itself parse and verify against the same binaries.
  let deps = [
    { name: "weft:reader", version: None, path: "reader.wasm", bytes: wasm_of(s32_component("read")) catch {
      e => fail(e.to_string())
    } },
    { name: "weft:filter", version: None, path: "filter.wasm", bytes: wasm_of(import_export_component()) catch {
      e => fail(e.to_string())
    } },
  ]
  let back = wac_to_manifest(wac_text, deps) catch {
    e => fail("generated WAC should verify: " + e.to_string())
  }
  inspect(back.components.length(), content="2")
  inspect(back.wires.length(), content="1")
  inspect(back.wires[0].from_component, content="reader")
  inspect(back.wires[0].to_port, content="in")
}