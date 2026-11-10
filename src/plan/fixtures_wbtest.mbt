// Test fixtures: build components from WAT and manifests from JSON, so planner
// tests stay self-contained and run on every backend without external tools.
//
// The core `lift`ed functions must have exactly the canonical flat signature of
// the component-level function, so callers pass that core signature explicitly.

///|
/// Build a component with plain function imports/exports.
/// `exports`/`imports` are `(name, component-sig-wat, core-sig-wat)` triples.
fn func_comp(
  exports : Array[(String, String, String)],
  imports : Array[(String, String, String)],
) -> String {
  let sb = StringBuilder()
  sb.write_string("(component ")
  for (name, sig, _) in imports {
    sb.write_string("(import \"\{name}\" (func \{sig})) ")
  }
  sb.write_string("(core module $M (memory (export \"mem\") 1) ")
  for (_, _, core) in exports {
    sb.write_string("(func (export \"f\") \{core} (i32.const 0)) ")
  }
  sb.write_string(
    "(func (export \"realloc\") (param i32 i32 i32 i32) (result i32) (i32.const 0)) " +
    ")",
  )
  sb.write_string("(core instance $m (instantiate $M)) ")
  let mut i = 0
  for (name, sig, _) in exports {
    sb.write_string(
      "(func (export \"\{name}\") \{sig} " +
      "(canon lift (core func $m \"f\") (memory $m \"mem\") " +
      "(realloc (core func $m \"realloc\")))) ",
    )
    i = i + 1
  }
  let _ = i
  sb.write_string(")")
  sb.to_string()
}

///|
/// A single-function component: `f: (s32) -> s32`, core `(i32) -> i32`.
fn s32_comp(exports : Array[String], imports : Array[String]) -> String {
  let e : Array[(String, String, String)] = []
  for n in exports {
    e.push((n, "(param \"x\" s32) (result s32)", "(param i32) (result i32)"))
  }
  let i : Array[(String, String, String)] = []
  for n in imports {
    i.push((n, "(param \"x\" s32) (result s32)", "(param i32) (result i32)"))
  }
  func_comp(e, i)
}

///|
fn decode(name : String, wat : String) -> @ir.Iface raise PlanError {
  let bytes = @text.parse_component_wat(wat) catch {
    e => raise InvalidManifest("fixture \{name}: \{e}")
  }
  @ir.decode_component(name, "\{name}.wasm", bytes) catch {
    e => raise InvalidManifest("fixture \{name}: \{e.to_string()}")
  }
}

///|
fn input_of(
  m : @manifest.Manifest,
  pairs : Array[(String, String)],
) -> Input raise PlanError {
  let ifaces : Map[String, @ir.Iface] = Map([])
  for (name, wat) in pairs {
    ifaces.set(name, decode(name, wat))
  }
  { manifest: m, ifaces, }
}

///|
fn manifest_of(json : String) -> @manifest.Manifest raise PlanError {
  @manifest.parse(json) catch {
    e => raise InvalidManifest(e.to_string())
  }
}

///|
/// A three-component linear chain: reader -> filter -> sink.
fn chain_input() -> Input raise PlanError {
  let reader = s32_comp(["read"], [])
  let filter = s32_comp(["out"], ["in"])
  let sink = s32_comp([], ["in"])
  let m = manifest_of(
    (
      #|{"version":"0.1.0",
      #| "components":[
      #|   {"name":"reader","path":"reader.wasm"},
      #|   {"name":"filter","path":"filter.wasm"},
      #|   {"name":"sink","path":"sink.wasm"}],
      #| "wires":[
      #|   {"from":"reader.read","to":"filter.in"},
      #|   {"from":"filter.out","to":"sink.in"}]}
    ),
  )
  input_of(m, [("reader", reader), ("filter", filter), ("sink", sink)])
}

///|
/// A component that exports an interface `io` with `transform: (s32)->s32`,
/// built by instantiating a nested sub-component and re-exporting its instance.
/// This is the shape the binary decoder supports (inline instance exports are
/// not).
fn iface_export_comp(iface : String, func : String) -> String {
  "(component " +
  "(component $sub " +
  "(core module $M (memory (export \"mem\") 1) " +
  "(func (export \"f\") (param i32) (result i32) (i32.const 0)) " +
  "(func (export \"realloc\") (param i32 i32 i32 i32) (result i32) (i32.const 0))) " +
  "(core instance $m (instantiate $M)) " +
  "(func $t (param \"x\" s32) (result s32) " +
  "(canon lift (core func $m \"f\") (memory $m \"mem\") (realloc (core func $m \"realloc\")))) " +
  "(export \"\{func}\" (func $t))) " +
  "(instance $i (instantiate $sub)) " +
  "(export \"\{iface}\" (instance $i))" +
  ")"
}

///|
/// A component that imports an interface `io` with `transform: (s32)->s32`.
fn iface_import_comp(iface : String, func : String) -> String {
  "(component " +
  "(type $T (instance (export \"\{func}\" (func (param \"x\" s32) (result s32))))) " +
  "(import \"\{iface}\" (instance $i (type $T)))" +
  ")"
}
