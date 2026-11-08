///|
fn emit_fixture() -> @manifest.Manifest raise {
  @manifest.parse(
    "{\"components\":[{\"name\":\"filter\",\"path\":\"filter.wasm\"},{\"name\":\"reader\",\"path\":\"reader.wasm\"}],\"wires\":[{\"from\":\"reader.read\",\"to\":\"filter.in\"}]}",
  )
}

///|
test "emit: reverse declaration order verifies and round-trips" {
  let m = emit_fixture()
  let source = manifest_to_wac(m)
  let deps : Array[WacDep] = [
    {
      name: "weft:reader",
      version: None,
      path: "reader.wasm",
      bytes: wasm_of(s32_component("read")),
    },
    {
      name: "weft:filter",
      version: None,
      path: "filter.wasm",
      bytes: wasm_of(import_export_component()),
    },
  ]
  let back = wac_to_manifest(source, deps)
  assert_eq(back.components.length(), 2)
  assert_eq(back.wires[0].from_component, "reader")
  assert_eq(back.wires[0].to_component, "filter")
}

///|
test "emit: component permutations produce identical WAC" {
  let m = emit_fixture()
  let other : @manifest.Manifest = {
    ..m,
    components: m.components.copy().rev(),
  }
  assert_eq(manifest_to_wac(m), manifest_to_wac(other))
}

///|
test "convert: explicit exported instance names survive" {
  let deps : Array[WacDep] = [
    {
      name: "n:reader",
      version: None,
      path: "x.wasm",
      bytes: wasm_of(s32_component("read")),
    },
  ]
  let m = wac_to_manifest(
    "package app:main; let x = new n:reader {}; export x as \"renamed\";", deps,
  )
  assert_eq(m.components[0].name, "renamed")
}

///|
fn emit_error(m : @manifest.Manifest) -> String {
  let _ = manifest_to_wac(m) catch { e => return e.to_string() }
  "<no error>"
}

///|
test "emit: resource metadata cannot be silently dropped" {
  let m = emit_fixture()
  let cases : Array[@manifest.ResourceLimits] = [
    { max_memory_pages: Some(0), quota: None, },
    { max_memory_pages: None, quota: Some(12), },
  ]
  for limits in cases {
    assert_true(
      emit_error({ ..m, resources: limits, }).contains(
        "cannot preserve resource limits",
      ),
    )
  }
}

///|
test "emit: cycles and duplicate bindings fail explicitly" {
  let m = emit_fixture()
  let duplicate : @manifest.Manifest = { ..m, wires: [m.wires[0], m.wires[0]], }
  assert_true(emit_error(duplicate).contains("duplicate binding"))
  let cycle : @manifest.Manifest = {
    ..m,
    wires: [
      m.wires[0],
      {
        from_component: "filter",
        from_port: "out",
        to_component: "reader",
        to_port: "in",
      },
    ],
  }
  assert_true(emit_error(cycle).contains("dependency cycle"))
}

///|
test "emit: unsafe names and interface paths fail instead of colliding or injecting text" {
  let m = emit_fixture()
  for
    name in [
      "a:b", "a/b", "a_b", "a\"b", "a\nb", "a\\b", "组件", "1start", "a--b",
    ] {
    let input : @manifest.Manifest = {
      ..m,
      components: [{ name, path: "x", }],
      wires: [],
    }
    assert_true(emit_error(input).contains("not a lowercase kebab name"))
  }
  let input : @manifest.Manifest = {
    ..m,
    wires: [{ ..m.wires[0], from_port: "io.read", }],
  }
  assert_true(emit_error(input).contains("interface paths"))
  let input : @manifest.Manifest = {
    ..m,
    wires: [{ ..m.wires[0], to_port: "in\njected", }],
  }
  assert_true(emit_error(input).contains("target port"))
}

///|
test "emit: keywords use safe identifiers and artifact paths cannot inject comments" {
  let m : @manifest.Manifest = {
    version: "0.1.0",
    components: [{ name: "let", path: "file\nexport hacked;", }],
    wires: [],
    resources: { max_memory_pages: None, quota: None, },
  }
  let source = manifest_to_wac(m)
  assert_true(source.contains("let c-let = new weft:let {}"))
  assert_false(source.contains("hacked"))
  let back = wac_to_manifest(source, [
    {
      name: "weft:let",
      version: None,
      path: m.components[0].path,
      bytes: wasm_of("(component)"),
    },
  ])
  assert_eq(back.components[0].name, "let")
  assert_eq(back.components[0].path, m.components[0].path)
}

///|
test "convert: hidden instances and multiple aliases are rejected" {
  let deps : Array[WacDep] = [
    {
      name: "n:reader",
      version: None,
      path: "x",
      bytes: wasm_of(s32_component("read")),
    },
  ]
  assert_true(
    wac_err("package app:main; let x = new n:reader {};", deps).contains(
      "not exported exactly once",
    ),
  )
  assert_true(
    wac_err(
      "package app:main; let x = new n:reader {}; export x as \"one\"; export x as \"two\";",
      deps,
    ).contains("more than once"),
  )
  assert_true(
    wac_err(
      "package app:main; let x = new n:reader {}; export x.read as \"read\";", deps,
    ).contains("not a whole component instance"),
  )
}

///|
test "convert: two versions retain the matching artifact paths" {
  let bytes = wasm_of("(component)")
  let deps : Array[WacDep] = [
    { name: "n:part", version: Some("1.0.0"), path: "v1.wasm", bytes, },
    { name: "n:part", version: Some("2.0.0"), path: "v2.wasm", bytes, },
  ]
  let m = wac_to_manifest(
    "package app:main; let a = new n:part@1.0.0 {}; let b = new n:part@2.0.0 {}; export a as \"first\"; export b as \"second\";",
    deps,
  )
  assert_eq(m.components[0].path, "v1.wasm")
  assert_eq(m.components[1].path, "v2.wasm")
}
