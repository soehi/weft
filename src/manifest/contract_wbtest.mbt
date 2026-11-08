///|
test "format: only explicit supported versions are accepted" {
  for v in ["0.1.", "0.1.bad", "0.1.1", "0.2.1", "0.2.0-beta", " 0.2.0"] {
    assert_true(err_of("{\"version\":\"\{v}\",\"components\":[]}") is Some(_))
  }
}

///|
test "format: duplicate keys and unknown fields fail at every object level" {
  for
    input in [
      "{\"components\":[],\"components\":[]}", "{\"components\":[],\"extension\":1}",
      "{\"components\":[{\"name\":\"a\",\"path\":\"a\",\"extra\":0}]}", "{\"components\":[],\"wires\":[{\"from\":\"a.f\",\"to\":\"b.f\",\"extra\":0}]}",
      "{\"components\":[],\"resources\":{\"qouta\":1}}", "{\"components\":[],\"resources\":{\"quota\":0,\"qu\\u006fta\":1}}",
    ] {
    assert_true(err_of(input) is Some(_))
  }
}

///|
test "format: supplementary Unicode component names split without truncation" {
  assert_eq(parse_port_ref("🧵源.read"), Some(("🧵源", "read")))
  assert_eq(parse_port_ref("a.io..read"), None)
}

///|
test "format: dotted names and empty artifact paths cannot be serialized losslessly" {
  for
    input in [
      "{\"components\":[{\"name\":\"a.b\",\"path\":\"x\"}]}", "{\"components\":[{\"name\":\"a\",\"path\":\"\"}]}",
    ] {
    assert_true(err_of(input) is Some(_))
  }
}

///|
test "format: resource limits use bounded decimal integer tokens" {
  let m = parse(
    "{\"components\":[],\"resources\":{\"quota\":2147483647,\"max_memory_pages\":0}}",
  )
  assert_eq(m.resources.quota, Some(2147483647))
  for
    token in [
      "2147483648", "9007199254740993", "1e30", "1e0", "1.0", "1.00000000000000000000001",
      "-0.0000000000000000000001",
    ] {
    assert_true(
      err_of("{\"components\":[],\"resources\":{\"quota\":\{token}}}")
      is Some(_),
    )
  }
}

///|
test "format: legacy and current inputs are accepted and omission selects current" {
  for v in ["0.1.0", "0.2.0"] {
    assert_eq(parse("{\"version\":\"\{v}\",\"components\":[]}").version, v)
  }
  assert_eq(parse("{\"components\":[]}").version, "0.2.0")
}
