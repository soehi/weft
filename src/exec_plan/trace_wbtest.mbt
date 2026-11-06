// Trace tests. These run on native, wasm-gc and js: the sequencing logic that
// the native adapter executes is verified everywhere, even where the adapter
// itself cannot be built.

///|
fn s32_comp(exports : Array[String], imports : Array[String]) -> String {
  let sb = StringBuilder()
  sb.write_string("(component ")
  for n in imports {
    sb.write_string("(import \"\{n}\" (func (param \"x\" s32) (result s32))) ")
  }
  sb.write_string(
    "(core module $M (memory (export \"mem\") 1) " +
    "(func (export \"f\") (param i32) (result i32) (i32.const 0)) " +
    "(func (export \"realloc\") (param i32 i32 i32 i32) (result i32) (i32.const 0))) " +
    "(core instance $m (instantiate $M)) ",
  )
  for n in exports {
    sb.write_string(
      "(func (export \"\{n}\") (param \"x\" s32) (result s32) " +
      "(canon lift (core func $m \"f\") (memory $m \"mem\") " +
      "(realloc (core func $m \"realloc\")))) ",
    )
  }
  sb.write_string(")")
  sb.to_string()
}

///|
fn chain_plan() -> @plan.Plan raise {
  let m = @manifest.parse(
    (
      #|{"components":[
      #|  {"name":"reader","path":"reader.wasm"},
      #|  {"name":"filter","path":"filter.wasm"},
      #|  {"name":"sink","path":"sink.wasm"}],
      #| "wires":[
      #|  {"from":"reader.read","to":"filter.in"},
      #|  {"from":"filter.out","to":"sink.in"}]}
    ),
  ) catch {
    e => raise Failure(e.to_string())
  }
  let ifaces : Map[String, @ir.Iface] = Map([])
  let decode = fn(name : String, wat : String) -> Unit raise {
    let bytes = @text.parse_component_wat(wat) catch {
      e => raise Failure(e.to_string())
    }
    let i = @ir.decode_component(name, "\{name}.wasm", bytes) catch {
      e => raise Failure(e.to_string())
    }
    ifaces.set(name, i)
  }
  decode("reader", s32_comp(["read"], [])) catch {
    e => raise Failure(e.to_string())
  }
  decode("filter", s32_comp(["out"], ["in"])) catch {
    e => raise Failure(e.to_string())
  }
  decode("sink", s32_comp([], ["in"])) catch {
    e => raise Failure(e.to_string())
  }
  @plan.plan({ manifest: m, ifaces }) catch {
    e => raise Failure(e.to_string())
  }
}

///|
test "trace: instantiations then binds" {
  let p = chain_plan() catch {
    e => fail(e.to_string())
  }
  let steps = trace(p)
  inspect(steps.length(), content="5")
  inspect(steps[0].to_string(), content="instantiate reader <- reader.wasm")
  inspect(steps[1].to_string(), content="instantiate filter <- filter.wasm")
  inspect(steps[2].to_string(), content="instantiate sink <- sink.wasm")
  // Wires are sorted by from_component, so filter.out comes first.
  inspect(steps[3].to_string(), content="bind filter.out -> sink.in")
  inspect(steps[4].to_string(), content="bind reader.read -> filter.in")
}

///|
test "trace: every instantiation precedes every bind" {
  let p = chain_plan() catch {
    e => fail(e.to_string())
  }
  let steps = trace(p)
  let mut seen_bind = false
  for s in steps {
    match s {
      Instantiate(_, _) =>
        if seen_bind {
          fail("instantiation after a bind")
        }
      Bind(_, _, _, _) => seen_bind = true
      Call(_, _) => ()
    }
  }
  inspect(seen_bind, content="true")
}

///|
test "trace: render is line oriented and deterministic" {
  let p = chain_plan() catch {
    e => fail(e.to_string())
  }
  let a = render(trace(p))
  let b = render(trace(p))
  inspect(a, content=b)
  debug_inspect(a.split("\n").count(), content="5")
}

///|
test "trace: terminal call targets the last instance" {
  let p = chain_plan() catch {
    e => fail(e.to_string())
  }
  let steps = trace(p)
  append_terminal_call(steps, p, "in")
  inspect(
    steps[steps.length() - 1].to_string(),
    content="call sink.in",
  )
}

///|
test "trace: empty plan yields no steps" {
  let m = @manifest.parse("{\"components\":[],\"wires\":[]}") catch {
    e => fail(e.to_string())
  }
  let p = @plan.plan({ manifest: m, ifaces: Map([]) }) catch {
    e => fail(e.to_string())
  }
  inspect(trace(p).length(), content="0")
}