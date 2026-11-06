///|
fn err_of(s : String) -> String? {
  let _ = parse(s) catch {
    e => {
      return Some(e.to_string())
    }
  }
  None
}

// Manifest parser tests. Mix of happy paths and adversarial inputs.

///|
test "parse: minimal manifest" {
  let m = parse(
    (
      #|{"version":"0.1.0","components":[{"name":"a","path":"a.wasm"}],"wires":[]}
    ),
  ) catch {
    e => fail("unexpected: \{e.to_string()}")
  }
  inspect(m.version, content="0.1.0")
  inspect(m.components.length(), content="1")
  inspect(m.components[0].name, content="a")
  inspect(m.components[0].path, content="a.wasm")
  inspect(m.wires.length(), content="0")
  debug_inspect(m.resources.max_memory_pages, content="None")
  debug_inspect(m.resources.quota, content="None")
}

///|
test "parse: version defaults to 0.1.0 when absent" {
  let m = parse("{\"components\":[]}") catch {
    e => fail("unexpected: \{e.to_string()}")
  }
  inspect(m.version, content="0.1.0")
}

///|
test "parse: unsupported version rejected" {
  debug_inspect(
    err_of("{\"version\":\"2.0.0\",\"components\":[]}"),
    content=(
      #|Some("manifest: unsupported version `2.0.0` (expected 0.1.x)")
    ),
  )
}

///|
test "parse: wire port may be an interface path" {
  let m = parse(
    (
      #|{"version":"0.1.0","components":[{"name":"a","path":"x"}],"wires":[{"from":"a.io.transform","to":"a.plain"}]}
    ),
  ) catch {
    e => fail("unexpected: \{e.to_string()}")
  }
  inspect(m.wires.length(), content="1")
  inspect(m.wires[0].from_component, content="a")
  inspect(m.wires[0].from_port, content="io.transform")
  inspect(m.wires[0].to_component, content="a")
  inspect(m.wires[0].to_port, content="plain")
}

///|
test "parse: port path with adjacent dots rejected" {
  debug_inspect(
    err_of("{\"components\":[],\"wires\":[{\"from\":\"a..b\",\"to\":\"x.y\"}]}"),
    content=(
      #|Some("manifest: wires[0].from must be `<component>.<port>`, got `a..b`")
    ),
  )
}

///|
test "parse: duplicate component rejected" {
  debug_inspect(
    err_of(
      (
        #|{"components":[{"name":"a","path":"1"},{"name":"a","path":"2"}]}
      ),
    ),
    content=(
      #|Some("manifest: duplicate component name `a`")
    ),
  )
}

///|
test "parse: missing field names the location" {
  debug_inspect(
    err_of("{\"components\":[{\"name\":\"a\"}]}"),
    content=(
      #|Some("manifest: components[0] is missing field `path`")
    ),
  )
}

///|
test "parse: wire without a dot is rejected" {
  debug_inspect(
    err_of("{\"components\":[],\"wires\":[{\"from\":\"abc\",\"to\":\"x.y\"}]}"),
    content=(
      #|Some("manifest: wires[0].from must be `<component>.<port>`, got `abc`")
    ),
  )
}

///|
test "parse: empty port half is rejected" {
  debug_inspect(
    err_of("{\"components\":[],\"wires\":[{\"from\":\"a.\",\"to\":\"x.y\"}]}"),
    content=(
      #|Some("manifest: wires[0].from must be `<component>.<port>`, got `a.`")
    ),
  )
}

///|
test "parse: invalid JSON reported, not panicked" {
  let msg = err_of("{not json").unwrap_or("")
  inspect(msg.has_prefix("manifest: invalid JSON:"), content="true")
}

///|
test "parse: components must be an array" {
  debug_inspect(
    err_of("{\"components\":{}}"),
    content=(
      #|Some("manifest: manifest.components must be an array, got object")
    ),
  )
}

///|
test "parse: component name must be a string" {
  debug_inspect(
    err_of("{\"components\":[{\"name\":1,\"path\":\"p\"}]}"),
    content=(
      #|Some("manifest: components[0].name must be a string, got number")
    ),
  )
}

///|
test "parse: fractional resource limit rejected" {
  debug_inspect(
    err_of("{\"components\":[],\"resources\":{\"quota\":1.5}}"),
    content=(
      #|Some("manifest: manifest.resources field `quota` must be an integer")
    ),
  )
}

///|
test "parse: negative resource limit rejected" {
  debug_inspect(
    err_of("{\"components\":[],\"resources\":{\"max_memory_pages\":-1}}"),
    content=(
      #|Some("manifest: manifest.resources field `max_memory_pages` must not be negative")
    ),
  )
}

///|
test "parse: resource limits are captured" {
  let m = parse(
    (
      #|{"components":[],"resources":{"max_memory_pages":256,"quota":1000000}}
    ),
  ) catch {
    e => fail("unexpected: \{e.to_string()}")
  }
  debug_inspect(m.resources.max_memory_pages, content="Some(256)")
  debug_inspect(m.resources.quota, content="Some(1000000)")
}

///|
test "parse: resource limit as string rejected" {
  debug_inspect(
    err_of("{\"components\":[],\"resources\":{\"quota\":\"1e6\"}}"),
    content=(
      #|Some("manifest: manifest.resources field `quota` must be an integer")
    ),
  )
}

///|
test "parse_port_ref: rejects empty component" {
  debug_inspect(parse_port_ref(".x"), content="None")
}

///|
test "parse_port_ref: rejects empty port" {
  debug_inspect(parse_port_ref("x."), content="None")
}

///|
test "parse: empty component name rejected" {
  debug_inspect(
    err_of("{\"components\":[{\"name\":\"\",\"path\":\"p\"}]}"),
    content=(
      #|Some("manifest: components[0] is missing field `name`")
    ),
  )
}