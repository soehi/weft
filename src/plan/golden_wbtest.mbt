// Golden plan test: the exact bytes the planner produces for the example
// manifest. Because this test runs on native, wasm-gc and js in CI, a hardcoded
// golden string is the cross-backend consistency assertion: if any backend's
// ordering, number formatting or hash differed, this file's expectation would
// fail there.

///|
/// The chain fixture used by `examples/chain.json`.
fn golden_chain() -> Input raise PlanError {
  let reader = s32_comp(["read"], [])
  let filter = s32_comp(["out"], ["in"])
  let sink = s32_comp([], ["in"])
  let m = manifest_of(
    (
      #|{"version":"0.1.0",
      #| "components":[
      #|   {"name":"reader","path":"reader.wasm"},
      #|   {"name":"filter","path":"filter.wasm"},
      #|   {"name":"sink","path":"sink.wasm"}],
      #| "wires":[
      #|   {"from":"reader.read","to":"filter.in"},
      #|   {"from":"filter.out","to":"sink.in"}],
      #| "resources":{"max_memory_pages":256,"quota":1000000}}
    ),
  )
  input_of(m, [("reader", reader), ("filter", filter), ("sink", sink)])
}

///|
test "golden: example plan bytes are exactly as documented" {
  let input = golden_chain() catch { e => fail(e.to_string()) }
  let p = plan(input) catch { e => fail(e.to_string()) }
  let expected =
    #|{"plan_version":"0.2.0","instances":[{"name":"reader","path":"reader.wasm","order":0,"incoming":[]},{"name":"filter","path":"filter.wasm","order":1,"incoming":[1]},{"name":"sink","path":"sink.wasm","order":2,"incoming":[0]}],"wires":[{"from":"filter.out","to":"sink.in","from_signature":"(i32) -> (i32)","to_signature":"(i32) -> (i32)"},{"from":"reader.read","to":"filter.in","from_signature":"(i32) -> (i32)","to_signature":"(i32) -> (i32)"}],"resources":{"max_memory_pages":256,"quota":1000000},"plan_hash":"1a3640bcc99318d5"}
  inspect(plan_json(p), content=expected)
}
