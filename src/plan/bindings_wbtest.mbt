///|
fn binding_input(
  wires : Array[@manifest.WireDecl],
  imports : Array[String],
) -> Input raise {
  let m : @manifest.Manifest = {
    version: "0.1.0",
    components: [
      { name: "a", path: "a", },
      { name: "b", path: "b", },
      { name: "sink", path: "sink", },
    ],
    wires,
    resources: { max_memory_pages: None, quota: None, },
  }
  input_of(m, [
    ("a", s32_comp(["out"], [])),
    ("b", s32_comp(["out"], [])),
    ("sink", s32_comp([], imports)),
  ])
}

///|
fn binding_wire(source : String, target : String) -> @manifest.WireDecl {
  {
    from_component: source,
    from_port: "out",
    to_component: "sink",
    to_port: target,
  }
}

///|
test "bindings: two providers of one import are rejected deterministically" {
  let a = binding_wire("a", "in")
  let b = binding_wire("b", "in")
  let first = plan_err(binding_input([a, b], ["in"]))
  assert_eq(first, "plan: duplicate binding for `sink.in`: a.out and b.out")
  assert_eq(plan_err(binding_input([b, a], ["in"])), first)
}

///|
test "bindings: a component with no wires still requires every import" {
  assert_eq(
    plan_err(binding_input([], ["in"])),
    "plan: unbound import `sink.in`",
  )
}

///|
test "bindings: partial coverage names the missing import" {
  assert_eq(
    plan_err(binding_input([binding_wire("a", "left")], ["left", "right"])),
    "plan: unbound import `sink.right`",
  )
}

///|
test "bindings: fan-out and two different imports are allowed" {
  let p = plan(
    binding_input([binding_wire("a", "left"), binding_wire("a", "right")], [
      "left", "right",
    ]),
  )
  assert_eq(p.wires.length(), 2)
}

///|
test "bindings: function wires cannot satisfy an interface instance" {
  let m = manifest_of(
    "{\"components\":[{\"name\":\"a\",\"path\":\"a\"},{\"name\":\"b\",\"path\":\"b\"}],\"wires\":[{\"from\":\"a.io.transform\",\"to\":\"b.io.transform\"}]}",
  )
  let input = input_of(m, [
    ("a", iface_export_comp("io", "transform")),
    ("b", iface_import_comp("io", "transform")),
  ])
  assert_eq(
    plan_err(input),
    "plan: unsupported `b.io`: interface instance imports require whole-instance binding",
  )
}

///|
test "bindings: non-function imports are retained and rejected" {
  let m = manifest_of(
    "{\"components\":[{\"name\":\"b\",\"path\":\"b\"}],\"wires\":[]}",
  )
  let input = input_of(m, [
    ("b", "(component (import \"r\" (type (sub resource))))"),
  ])
  assert_eq(
    plan_err(input),
    "plan: unsupported `b.r`: non-function import cannot be bound by function wires",
  )
}

///|
test "bindings: empty imported instances still require whole-instance binding" {
  let m = manifest_of("{\"components\":[{\"name\":\"b\",\"path\":\"b\"}]}")
  let input = input_of(m, [
    (
      "b", "(component (type $i (instance)) (import \"io\" (instance (type $i))))",
    ),
  ])
  assert_eq(
    plan_err(input),
    "plan: unsupported `b.io`: interface instance imports require whole-instance binding",
  )
}

///|
test "bindings: missing import selection ignores declaration order" {
  let first = binding_input([], ["z", "alpha"])
  assert_eq(plan_err(first), "plan: unbound import `sink.alpha`")
  let second : Input = {
    manifest: {
      ..first.manifest,
      components: first.manifest.components.copy().rev(),
    },
    ifaces: first.ifaces,
  }
  assert_eq(plan_err(second), plan_err(first))
  assert_eq(plan_err(binding_input([], ["alpha", "z"])), plan_err(first))
}

///|
test "bindings: isolated manifest components also require an interface" {
  let input = binding_input([], [])
  input.ifaces.remove("b") |> ignore
  assert_eq(plan_err(input), "plan: wire references unknown component `b`")
}
