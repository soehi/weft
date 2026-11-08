// Planner tests: happy path, determinism, and adversarial inputs.

///|
fn plan_of(input : Input) -> String raise PlanError {
  plan_json(plan(input))
}

///|
fn plan_err(input : Input) -> String {
  let _ = plan(input) catch {
    e => {
      return e.to_string()
    }
  }
  "<no error>"
}

///|
test "plan: linear chain orders provider before consumer" {
  let input = chain_input() catch {
    e => fail(e.to_string())
  }
  let p = plan(input) catch {
    e => fail(e.to_string())
  }
  inspect(p.instances.length(), content="3")
  inspect(p.instances[0].name, content="reader")
  inspect(p.instances[1].name, content="filter")
  inspect(p.instances[2].name, content="sink")
  inspect(p.instances[0].order, content="0")
  inspect(p.instances[1].order, content="1")
  inspect(p.instances[2].order, content="2")
  inspect(p.wires.length(), content="2")
}

///|
test "plan: wire signatures are recorded in plan output" {
  let input = chain_input() catch {
    e => fail(e.to_string())
  }
  let p = plan(input) catch {
    e => fail(e.to_string())
  }
  // Sorted: filter.out -> sink.in comes before reader.read -> filter.in.
  inspect(p.wires[0].from_component, content="filter")
  inspect(p.wires[0].from_port, content="out")
  inspect(p.wires[1].from_component, content="reader")
  inspect(p.wires[0].from_flat_params.join(","), content="i32")
  inspect(p.wires[0].from_flat_results.join(","), content="i32")
}

///|
test "plan: incoming wires are attached to the consumer" {
  let input = chain_input() catch {
    e => fail(e.to_string())
  }
  let p = plan(input) catch {
    e => fail(e.to_string())
  }
  match p.instances {
    [reader, filter, sink] => {
      inspect(reader.incoming.length(), content="0")
      inspect(filter.incoming.length(), content="1")
      inspect(sink.incoming.length(), content="1")
    }
    _ => fail("expected three instances")
  }
}

///|
test "plan: deterministic across repeated runs" {
  let a = chain_input() catch {
    e => fail(e.to_string())
  }
  let b = chain_input() catch {
    e => fail(e.to_string())
  }
  let ja = plan_of(a) catch {
    e => fail(e.to_string())
  }
  let jb = plan_of(b) catch {
    e => fail(e.to_string())
  }
  inspect(ja == jb, content="true")
}

///|
test "plan: hash is stable and 16 hex digits" {
  let input = chain_input() catch {
    e => fail(e.to_string())
  }
  let p = plan(input) catch {
    e => fail(e.to_string())
  }
  inspect(p.hash.length(), content="16")
  let again = plan(input) catch {
    e => fail(e.to_string())
  }
  inspect(p.hash, content=again.hash)
}

///|
test "plan: JSON body is byte-identical for identical input" {
  let a = chain_input() catch {
    e => fail(e.to_string())
  }
  let b = chain_input() catch {
    e => fail(e.to_string())
  }
  let pa = plan(a) catch {
    e => fail(e.to_string())
  }
  let pb = plan(b) catch {
    e => fail(e.to_string())
  }
  inspect(plan_body(pa) == plan_body(pb), content="true")
}

///|
test "plan: JSON has hash as last field" {
  let input = chain_input() catch {
    e => fail(e.to_string())
  }
  let p = plan(input) catch {
    e => fail(e.to_string())
  }
  let json = plan_json(p)
  inspect(json.has_prefix("{\"plan_version\":"), content="true")
  inspect(json.has_suffix("}"), content="true")
  inspect(json.contains(",\"plan_hash\":\""), content="true")
}

///|
test "plan: wire order independent of manifest order" {
  let reader = s32_comp(["read"], [])
  let sink = s32_comp([], ["in"])
  // Reverse the manifest ordering of components and wires.
  let m1 = manifest_of(
    (
      #|{"components":[{"name":"reader","path":"r"},{"name":"sink","path":"s"}],
      #| "wires":[{"from":"reader.read","to":"sink.in"}]}
    ),
  )
  let m2 = manifest_of(
    (
      #|{"components":[{"name":"sink","path":"s"},{"name":"reader","path":"r"}],
      #| "wires":[{"from":"reader.read","to":"sink.in"}]}
    ),
  )
  let i1 = input_of(m1, [("reader", reader), ("sink", sink)]) catch {
    e => fail(e.to_string())
  }
  let i2 = input_of(m2, [("reader", reader), ("sink", sink)]) catch {
    e => fail(e.to_string())
  }
  let p1 = plan(i1) catch {
    e => fail(e.to_string())
  }
  let p2 = plan(i2) catch {
    e => fail(e.to_string())
  }
  inspect(p1.hash, content=p2.hash)
  inspect(plan_body(p1) == plan_body(p2), content="true")
}

///|
test "plan: cycle is reported with its members" {
  let a = s32_comp(["out"], ["in"])
  let b = s32_comp(["out"], ["in"])
  let m = manifest_of(
    (
      #|{"components":[{"name":"a","path":"a"},{"name":"b","path":"b"}],
      #| "wires":[{"from":"a.out","to":"b.in"},{"from":"b.out","to":"a.in"}]}
    ),
  )
  let input = input_of(m, [("a", a), ("b", b)]) catch {
    e => fail(e.to_string())
  }
  let msg = plan_err(input)
  inspect(msg.has_prefix("plan: dependency cycle:"), content="true")
  inspect(msg.contains("a"), content="true")
  inspect(msg.contains("b"), content="true")
}

///|
test "plan: self-wire is a cycle" {
  let a = s32_comp(["out"], ["in"])
  let m = manifest_of(
    (
      #|{"components":[{"name":"a","path":"a"}],
      #| "wires":[{"from":"a.out","to":"a.in"}]}
    ),
  )
  let input = input_of(m, [("a", a)]) catch {
    e => fail(e.to_string())
  }
  inspect(plan_err(input).has_prefix("plan: dependency cycle:"), content="true")
}

///|
test "plan: unknown component in a wire" {
  let a = s32_comp(["out"], [])
  let m = manifest_of(
    (
      #|{"components":[{"name":"a","path":"a"}],
      #| "wires":[{"from":"a.out","to":"ghost.in"}]}
    ),
  )
  let input = input_of(m, [("a", a)]) catch {
    e => fail(e.to_string())
  }
  inspect(
    plan_err(input),
    content="plan: wire references unknown component `ghost`",
  )
}

///|
test "plan: unknown export port" {
  let a = s32_comp(["out"], [])
  let b = s32_comp([], ["in"])
  let m = manifest_of(
    (
      #|{"components":[{"name":"a","path":"a"},{"name":"b","path":"b"}],
      #| "wires":[{"from":"a.missing","to":"b.in"}]}
    ),
  )
  let input = input_of(m, [("a", a), ("b", b)]) catch {
    e => fail(e.to_string())
  }
  inspect(plan_err(input), content="plan: `a` has no port `missing`")
}

///|
test "plan: signature mismatch is reported with both sides" {
  let a = s32_comp(["out"], [])
  let b = func_comp([], [("in", "(param \"x\" s64) (result s64)", "(param i64) (result i64)")])
  let m = manifest_of(
    (
      #|{"components":[{"name":"a","path":"a"},{"name":"b","path":"b"}],
      #| "wires":[{"from":"a.out","to":"b.in"}]}
    ),
  )
  let input = input_of(m, [("a", a), ("b", b)]) catch {
    e => fail(e.to_string())
  }
  let msg = plan_err(input)
  inspect(msg.contains("signature mismatch"), content="true")
  inspect(msg.contains("parameter 0: s32 vs s64"), content="true")
}

///|
test "plan: result arity mismatch" {
  let a = s32_comp(["out"], [])
  let b = func_comp([], [("in", "(param \"x\" s32)", "(param i32)")])
  let m = manifest_of(
    (
      #|{"components":[{"name":"a","path":"a"},{"name":"b","path":"b"}],
      #| "wires":[{"from":"a.out","to":"b.in"}]}
    ),
  )
  let input = input_of(m, [("a", a), ("b", b)]) catch {
    e => fail(e.to_string())
  }
  let msg = plan_err(input)
  inspect(msg.contains("result arity 1 vs 0"), content="true")
}

///|
test "plan: interface path wire resolves nested function" {
  // Exported interface functions may provide a plain function import.
  let a = iface_export_comp("io", "transform")
  let b = s32_comp([], ["in"])
  let m = manifest_of(
    (
      #|{"components":[{"name":"a","path":"a"},{"name":"b","path":"b"}],
      #| "wires":[{"from":"a.io.transform","to":"b.in"}]}
    ),
  )
  let input = input_of(m, [("a", a), ("b", b)]) catch {
    e => fail(e.to_string())
  }
  let p = plan(input) catch {
    e => fail(e.to_string())
  }
  inspect(p.wires.length(), content="1")
  inspect(p.wires[0].from_port, content="io.transform")
  inspect(p.wires[0].from_flat_params.join(","), content="i32")
}

///|
test "plan: interface addressed as function is a kind mismatch" {
  let a = iface_export_comp("io", "transform")
  let b = s32_comp([], ["in"])
  let m = manifest_of(
    (
      #|{"components":[{"name":"a","path":"a"},{"name":"b","path":"b"}],
      #| "wires":[{"from":"a.io","to":"b.in"}]}
    ),
  )
  let input = input_of(m, [("a", a), ("b", b)]) catch {
    e => fail(e.to_string())
  }
  let msg = plan_err(input)
  inspect(msg.contains("is an interface, not a function"), content="true")
}

///|
test "plan: diamond keeps provider first" {
  // src -> left, src -> right, left -> join, right -> join
  let src = s32_comp(["out"], [])
  let left = s32_comp(["out"], ["in"])
  let right = s32_comp(["out"], ["in"])
  let join = func_comp([], [("a", "(param \"x\" s32) (result s32)", "(param i32) (result i32)"), ("b", "(param \"x\" s32) (result s32)", "(param i32) (result i32)")])
  let m = manifest_of(
    (
      #|{"components":[
      #|  {"name":"src","path":"s"},{"name":"left","path":"l"},
      #|  {"name":"right","path":"r"},{"name":"join","path":"j"}],
      #| "wires":[
      #|  {"from":"src.out","to":"left.in"},
      #|  {"from":"src.out","to":"right.in"},
      #|  {"from":"left.out","to":"join.a"},
      #|  {"from":"right.out","to":"join.b"}]}
    ),
  )
  let input = input_of(m, [("src", src), ("left", left), ("right", right), ("join", join)]) catch {
    e => fail(e.to_string())
  }
  let p = plan(input) catch {
    e => fail(e.to_string())
  }
  // Both left and right must come after src and before join. Among ready nodes
  // lexicographic wins, so after src we pick `left`, then `right`, then `join`.
  inspect(p.instances[0].name, content="src")
  inspect(p.instances[1].name, content="left")
  inspect(p.instances[2].name, content="right")
  inspect(p.instances[3].name, content="join")
}

///|
test "plan: resources are carried through, absent means null" {
  let input = chain_input() catch {
    e => fail(e.to_string())
  }
  let p = plan(input) catch {
    e => fail(e.to_string())
  }
  debug_inspect(p.resources.max_memory_pages, content="None")
  inspect(plan_json(p).contains("\"max_memory_pages\":null"), content="true")
}

///|
test "plan: resources set are emitted" {
  let a = s32_comp(["out"], [])
  let m = manifest_of(
    (
      #|{"components":[{"name":"a","path":"a"}],
      #| "resources":{"max_memory_pages":256,"quota":1000000}}
    ),
  )
  let input = input_of(m, [("a", a)]) catch {
    e => fail(e.to_string())
  }
  let p = plan(input) catch {
    e => fail(e.to_string())
  }
  let json = plan_json(p)
  inspect(json.contains("\"max_memory_pages\":256"), content="true")
  inspect(json.contains("\"quota\":1000000"), content="true")
}

///|
test "plan: empty manifest yields empty plan with valid hash" {
  let m = manifest_of("{\"components\":[],\"wires\":[]}") catch {
    e => fail(e.to_string())
  }
  let input = { manifest: m, ifaces: Map([]) }
  let p = plan(input) catch {
    e => fail(e.to_string())
  }
  inspect(p.instances.length(), content="0")
  inspect(p.wires.length(), content="0")
  inspect(p.hash.length(), content="16")
}

///|
test "plan: hash changes when resources change" {
  let a = s32_comp(["out"], [])
  let m1 = manifest_of(
    "{\"components\":[{\"name\":\"a\",\"path\":\"a\"}]}",
  ) catch {
    e => fail(e.to_string())
  }
  let m2 = manifest_of(
    "{\"components\":[{\"name\":\"a\",\"path\":\"a\"}],\"resources\":{\"quota\":5}}",
  ) catch {
    e => fail(e.to_string())
  }
  let p1 = plan(input_of(m1, [("a", a)]) catch {
    e => fail(e.to_string())
  }) catch {
    e => fail(e.to_string())
  }
  let p2 = plan(input_of(m2, [("a", a)]) catch {
    e => fail(e.to_string())
  }) catch {
    e => fail(e.to_string())
  }
  inspect(p1.hash == p2.hash, content="false")
}

///|
test "plan: hash changes when wiring changes" {
  let a = s32_comp(["out"], [])
  let b = s32_comp([], ["in"])
  let c = s32_comp(["out"], [])
  let m1 = manifest_of(
    (
      #|{"components":[{"name":"a","path":"a"},{"name":"b","path":"b"},{"name":"c","path":"c"}],
      #| "wires":[{"from":"a.out","to":"b.in"}]}
    ),
  )
  let m2 = manifest_of(
    (
      #|{"components":[{"name":"a","path":"a"},{"name":"b","path":"b"},{"name":"c","path":"c"}],
      #| "wires":[{"from":"c.out","to":"b.in"}]}
    ),
  )
  let pairs = [("a", a), ("b", b), ("c", c)]
  let p1 = plan(input_of(m1, pairs) catch {
    e => fail(e.to_string())
  }) catch {
    e => fail(e.to_string())
  }
  let p2 = plan(input_of(m2, pairs) catch {
    e => fail(e.to_string())
  }) catch {
    e => fail(e.to_string())
  }
  inspect(p1.hash == p2.hash, content="false")
}

///|
test "plan: large fan-in graph stays deterministic" {
  // 20 producers into one join.
  let prods : Array[(String, String)] = []
  let comps : Array[String] = []
  let wires : Array[String] = []
  let imports : Array[(String, String, String)] = []
  let mut i = 0
  while i < 20 {
    let name = "p\{i}"
    prods.push((name, s32_comp(["out"], [])))
    comps.push("{\"name\":\"\{name}\",\"path\":\"\{name}\"}")
    wires.push("{\"from\":\"\{name}.out\",\"to\":\"join.in\{i}\"}")
    imports.push(("in\{i}", "(param \"x\" s32) (result s32)", "(param i32) (result i32)"))
    i = i + 1
  }
  let join = func_comp([], imports)
  comps.push("{\"name\":\"join\",\"path\":\"join\"}")
  let json = "{\"components\":[" + comps.join(",") + "],\"wires\":[" + wires.join(",") + "]}"
  let m = manifest_of(json) catch {
    e => fail(e.to_string())
  }
  let pairs = prods.copy()
  pairs.push(("join", join))
  let input = input_of(m, pairs) catch {
    e => fail(e.to_string())
  }
  let p = plan(input) catch {
    e => fail(e.to_string())
  }
  inspect(p.instances.length(), content="21")
  // join must be last.
  inspect(p.instances[20].name, content="join")
  inspect(p.wires.length(), content="20")
  // Same input again -> same bytes.
  let input2 = input_of(m, pairs) catch {
    e => fail(e.to_string())
  }
  let p2 = plan(input2) catch {
    e => fail(e.to_string())
  }
  inspect(plan_body(p) == plan_body(p2), content="true")
}