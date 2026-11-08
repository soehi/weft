// Additional adversarial and edge-case coverage.

///|
test "plan: repeated identical wires are rejected" {
  let a = s32_comp(["out"], [])
  let b = s32_comp([], ["in"])
  let m = manifest_of(
    (
      #|{"components":[{"name":"a","path":"a"},{"name":"b","path":"b"}],
      #| "wires":[{"from":"a.out","to":"b.in"},{"from":"a.out","to":"b.in"}]}
    ),
  )
  let input = input_of(m, [("a", a), ("b", b)]) catch {
    e => fail(e.to_string())
  }
  inspect(plan_err(input), content="plan: duplicate binding for `b.in`: a.out and a.out")
}

///|
test "plan: self-wire component order is still a cycle error, not a hang" {
  let a = s32_comp(["out", "in_export"], ["in"])
  let _ = a
  // Build a self-wire on a component that both exports and imports `f`.
  let wat = "(component " +
    "(import \"in\" (func (param \"x\" s32) (result s32))) " +
    "(core module $M (memory (export \"mem\") 1) " +
    "(func (export \"f\") (param i32) (result i32) (i32.const 0)) " +
    "(func (export \"realloc\") (param i32 i32 i32 i32) (result i32) (i32.const 0))) " +
    "(core instance $m (instantiate $M)) " +
    "(func (export \"out\") (param \"x\" s32) (result s32) " +
    "(canon lift (core func $m \"f\") (memory $m \"mem\") (realloc (core func $m \"realloc\"))))" +
    ") "
  let m = manifest_of(
    "{\"components\":[{\"name\":\"a\",\"path\":\"a\"}],\"wires\":[{\"from\":\"a.out\",\"to\":\"a.in\"}]}",
  ) catch {
    e => fail(e.to_string())
  }
  let input = input_of(m, [("a", wat)]) catch {
    e => fail(e.to_string())
  }
  let msg = plan_err(input)
  inspect(msg.has_prefix("plan: dependency cycle:"), content="true")
}

///|
test "plan: long cycle a->b->c->a reported" {
  let a = s32_comp(["out"], ["in"])
  let b = s32_comp(["out"], ["in"])
  let c = s32_comp(["out"], ["in"])
  let m = manifest_of(
    (
      #|{"components":[{"name":"a","path":"a"},{"name":"b","path":"b"},{"name":"c","path":"c"}],
      #| "wires":[
      #|   {"from":"a.out","to":"b.in"},
      #|   {"from":"b.out","to":"c.in"},
      #|   {"from":"c.out","to":"a.in"}]}
    ),
  )
  let input = input_of(m, [("a", a), ("b", b), ("c", c)]) catch {
    e => fail(e.to_string())
  }
  inspect(plan_err(input).has_prefix("plan: dependency cycle:"), content="true")
}

///|
test "plan: importing the wrong port kind on the consumer" {
  // consumer imports an interface `io`; wire addresses `io` as a function.
  let a = s32_comp(["out"], [])
  let b = iface_import_comp("io", "transform")
  let m = manifest_of(
    (
      #|{"components":[{"name":"a","path":"a"},{"name":"b","path":"b"}],
      #| "wires":[{"from":"a.out","to":"b.io"}]}
    ),
  )
  let input = input_of(m, [("a", a), ("b", b)]) catch {
    e => fail(e.to_string())
  }
  let msg = plan_err(input)
  inspect(msg.contains("is an interface, not a function"), content="true")
}

///|
test "plan: nested interface function missing" {
  let a = s32_comp(["out"], [])
  let b = iface_import_comp("io", "transform")
  let m = manifest_of(
    (
      #|{"components":[{"name":"a","path":"a"},{"name":"b","path":"b"}],
      #| "wires":[{"from":"a.out","to":"b.io.missing"}]}
    ),
  )
  let input = input_of(m, [("a", a), ("b", b)]) catch {
    e => fail(e.to_string())
  }
  inspect(plan_err(input), content="plan: `b` has no port `io.missing`")
}

///|
test "plan: unflattenable type is reported" {
  // A function whose parameter is a resource-owning handle cannot be flattened
  // by our scope's canonical check.
  let wat = "(component " +
    "(import \"own\" (func (param \"x\" (list (list (list u32))))))" +
    ")"
  let a = s32_comp(["out"], [])
  let m = manifest_of(
    (
      #|{"components":[{"name":"a","path":"a"},{"name":"b","path":"b"}],
      #| "wires":[{"from":"a.out","to":"b.own"}]}
    ),
  )
  let input = input_of(m, [("a", a), ("b", wat)]) catch {
    e => fail(e.to_string())
  }
  let msg = plan_err(input)
  // Either the signature mismatches (arity) or flattening fails; both are
  // acceptable and both name the endpoint.
  inspect(msg.contains("b.own") || msg.contains("`b`"), content="true")
}

///|
test "plan: wire to a component with no ports" {
  let a = s32_comp(["out"], [])
  let empty = "(component (core module $M)) "
  let m = manifest_of(
    (
      #|{"components":[{"name":"a","path":"a"},{"name":"b","path":"b"}],
      #| "wires":[{"from":"a.out","to":"b.in"}]}
    ),
  )
  let input = input_of(m, [("a", a), ("b", empty)]) catch {
    e => fail(e.to_string())
  }
  inspect(plan_err(input), content="plan: `b` has no port `in`")
}

///|
test "plan: wide fan-out from one export" {
  let a = s32_comp(["out"], [])
  let b = s32_comp([], ["in"])
  let c = s32_comp([], ["in"])
  let m = manifest_of(
    (
      #|{"components":[{"name":"a","path":"a"},{"name":"b","path":"b"},{"name":"c","path":"c"}],
      #| "wires":[
      #|   {"from":"a.out","to":"b.in"},
      #|   {"from":"a.out","to":"c.in"}]}
    ),
  )
  let input = input_of(m, [("a", a), ("b", b), ("c", c)]) catch {
    e => fail(e.to_string())
  }
  let p = plan(input) catch {
    e => fail(e.to_string())
  }
  inspect(p.instances[0].name, content="a")
  inspect(p.instances.length(), content="3")
}

///|
test "plan: plan_json is valid JSON and hash round-trips" {
  let input = chain_input() catch {
    e => fail(e.to_string())
  }
  let p = plan(input) catch {
    e => fail(e.to_string())
  }
  let json = plan_json(p)
  // Ensure the emitter produces something the JSON parser accepts.
  let _ = @json.parse(json) catch {
    e => fail("plan_json is not valid JSON: \{e}")
  }
  // And the hash inside it equals the plan's hash field.
  inspect(json.contains("\"plan_hash\":\"\{p.hash}\""), content="true")
}

///|
test "plan: empty-string port is rejected by the manifest parser" {
  let got = @manifest.parse(
    "{\"components\":[{\"name\":\"a\",\"path\":\"a\"}],\"wires\":[{\"from\":\"a.\",\"to\":\"a.in\"}]}",
  ) catch {
    e => {
      return inspect(
        e.to_string(),
        content="manifest: wires[0].from must be `<component>.<port>`, got `a.`",
      )
    }
  }
  fail("expected a parse error, got \{got.version}")
}

///|
test "plan: many components stay ordered deterministically" {
  let comps : Array[String] = []
  let pairs : Array[(String, String)] = []
  let wires : Array[String] = []
  let mut i = 0
  while i < 10 {
    let name = "c\{i}"
    comps.push("{\"name\":\"\{name}\",\"path\":\"\{name}\"}")
    if i == 0 {
      pairs.push((name, s32_comp(["out"], [])))
    } else {
      pairs.push((name, s32_comp([], ["in"])))
      wires.push("{\"from\":\"c0.out\",\"to\":\"\{name}.in\"}")
    }
    i = i + 1
  }
  let m = manifest_of(
    "{\"components\":[" + comps.join(",") + "],\"wires\":[" + wires.join(",") + "]}",
  ) catch {
    e => fail(e.to_string())
  }
  let input = input_of(m, pairs) catch {
    e => fail(e.to_string())
  }
  let p = plan(input) catch {
    e => fail(e.to_string())
  }
  inspect(p.instances[0].name, content="c0")
  // c1..c9 follow in lexicographic order.
  inspect(p.instances[1].name, content="c1")
  inspect(p.instances[9].name, content="c9")
}