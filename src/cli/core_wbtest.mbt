///|
test "CLI rejects malformed arguments before doing I/O" {
  let cases = [
    ["oops"],
    ["oops", "plan", "x"],
    ["plan"],
    ["plan", "x", "y"],
    ["plan", "x", "--wat"],
    ["plan", "x", "--out"],
    ["plan", "x", "--out", "--out"],
    ["plan", "x", "--out", "a", "--out", "b"],
    ["plan", "x", "--dep", "n:p=a"],
    ["run", "x", "--out", "a"],
    ["convert", "x", "--dep"],
    ["convert", "x", "--dep", "broken"],
    ["convert", "x", "--dep", "p=a"],
    ["convert", "x", "--dep", "n:p="],
    ["convert", "x", "--dep", "n:p@=a"],
    ["convert", "x", "--dep", "n:p@1@2=a"],
    ["convert", "x", "--dep", "n:p=a", "--dep", "n:p=b"],
    ["help", "extra"],
  ]
  for args in cases {
    match parse_args(args) {
      Unknown(_) => ()
      _ => fail("unexpected acceptance")
    }
  }
}

///|
test "CLI preserves paths with spaces and equals and dependency versions" {
  match
    parse_args([
      "convert", "--dep", "n:p@1.0.0=dir with spaces/a=b.wasm", "x.wac", "--out",
      "a b.json",
    ]) {
    Convert(path, deps, out) => {
      assert_eq(path, "x.wac")
      assert_eq(deps[0], ("n:p@1.0.0", "dir with spaces/a=b.wasm"))
      assert_eq(out, Some("a b.json"))
      assert_eq(dependency_name(deps[0].0), ("n:p", Some("1.0.0")))
    }
    _ => fail("expected convert")
  }
}

///|
test "convert preserves explicit dependency metadata" {
  let bytes = @text.parse_component_wat("(component)") catch {
    e => fail(e.to_string())
  }
  let r = cmd_convert(
    "package app:main; let p = new ns:part@1.0.0 {}; export p as \"part\";",
    [
      {
        name: "ns:part",
        version: Some("1.0.0"),
        path: "a directory/non-default.wasm",
        bytes,
      },
    ],
  )
  assert_true(r.ok, msg=r.text)
  let m = @manifest.parse(r.text) catch { e => fail(e.to_string()) }
  assert_eq(m.components[0].path, "a directory/non-default.wasm")
}

///|
test "CLI and public API return identical canonical bytes and errors" {
  let text = "{\"components\":[{\"name\":\"x\",\"path\":\"logical\"}]}"
  let bins = Map([("x", @text.parse_component_wat("(component)"))])
  let api = match @api.compile(text, bins) {
    Ok(o) => o
    Err(d) => fail(d.message)
  }
  assert_eq(cmd_plan(text, bins).text, api.json)
  let d = match @api.compile(text, Map([])) {
    Err(d) => d
    Ok(_) => fail("expected missing binary")
  }
  assert_eq(cmd_plan(text, Map([])).text, d.message)
  assert_false(cmd_plan(text, Map([])).ok)
}

///|
test "CLI version is explicit and rejects extra arguments" {
  for flag in ["--version", "version", "-V"] {
    match parse_args([flag]) { Version => (); _ => fail("expected version") }
    match parse_args([flag, "extra"]) { Unknown(_) => (); _ => fail("expected rejection") }
  }
  assert_eq(version_text, "weft 0.3.1 (plan 0.2.0)")
}
