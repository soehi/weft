///|
test "format: supplementary characters use codepoint ordering and full suffixes" {
  assert_true(@ir.cmp_str("🧵a", "🧵b") < 0)
  assert_true(@ir.cmp_str("🧵", "🧵b") < 0)
  assert_true(@ir.cmp_str("\u{e000}", "🧵") < 0)
  assert_eq(@ir.cmp_str("🧵", "🧵"), 0)
}

///|
test "format: Unicode wired plans survive component and wire permutations" {
  let m = manifest_of(
    "{\"components\":[{\"name\":\"🧵b\",\"path\":\"b\\\"\\n\\\\.wasm\"},{\"name\":\"🧵a\",\"path\":\"a.wasm\"},{\"name\":\"尾\",\"path\":\"c.wasm\"}],\"wires\":[{\"from\":\"🧵a.out\",\"to\":\"🧵b.in\"},{\"from\":\"🧵a.out\",\"to\":\"尾.in\"}],\"resources\":{\"quota\":2147483647}}",
  )
  let input = input_of(m, [
    ("🧵a", s32_comp(["out"], [])),
    ("🧵b", s32_comp([], ["in"])),
    ("尾", s32_comp([], ["in"])),
  ])
  let other : Input = {
    manifest: {
      ..m,
      components: m.components.copy().rev(),
      wires: m.wires.copy().rev(),
    },
    ifaces: input.ifaces,
  }
  let json = plan_json(plan(input))
  assert_eq(json, plan_json(plan(other)))
  assert_true(json.contains("2147483647"))
  let _ = @json.parse(json)
}

///|
test "format: v0.1 input migrates to v0.2 plan and hash covers the body only" {
  let p = plan(golden_chain())
  assert_eq(p.plan_version, "0.2.0")
  assert_eq(p.hash, "1a3640bcc99318d5")
  assert_eq(p.hash, fnv1a64_hex(plan_body(p)))
  assert_eq(plan_body({ ..p, hash: "ignored", }), plan_body(p))
  let legacy : Plan = { ..p, plan_version: "0.1.0", }
  assert_eq(fnv1a64_hex(plan_body(legacy)), "e96eb1e1a80fbdaa")
}
