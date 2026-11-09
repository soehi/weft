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
  @plan.plan({ manifest: m, ifaces, }) catch {
    e => raise Failure(e.to_string())
  }
}

///|
test "trace: bind source exports before each consumer instantiation" {
  let steps = trace(chain_plan())
  inspect(
    render(steps),
    content="instantiate reader <- reader.wasm\nbind reader.read -> filter.in\ninstantiate filter <- filter.wasm\nbind filter.out -> sink.in\ninstantiate sink <- sink.wasm",
  )
}

///|
test "trace: every bind has a live source and an uninstantiated target" {
  let live : Map[String, Bool] = Map([])
  for step in trace(chain_plan()) {
    match step {
      Instantiate(name, _) => live.set(name, true)
      Bind(source, _, target, _) => {
        assert_true(live.contains(source))
        assert_false(live.contains(target))
      }
      Call(_, _) => ()
    }
  }
}

///|

///|
test "trace: render is line oriented and deterministic" {
  let p = chain_plan() catch { e => fail(e.to_string()) }
  let a = render(trace(p))
  let b = render(trace(p))
  inspect(a, content=b)
  debug_inspect(a.split("\n").count(), content="5")
}

///|
test "trace: call targets an explicitly selected instance" {
  let p = chain_plan() catch { e => fail(e.to_string()) }
  let steps = trace(p)
  append_call(steps, "reader", "read")
  inspect(steps[steps.length() - 1].to_string(), content="call reader.read")
}

///|
test "trace: empty plan yields no steps" {
  let m = @manifest.parse("{\"components\":[],\"wires\":[]}") catch {
    e => fail(e.to_string())
  }
  let p = @plan.plan({ manifest: m, ifaces: Map([]), }) catch {
    e => fail(e.to_string())
  }
  inspect(trace(p).length(), content="0")
}
