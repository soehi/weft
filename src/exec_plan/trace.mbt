// Execution trace construction.
//
// The plan says "instantiate A, B, C; wire A.x -> B.y". An executor needs that
// as a flat, ordered list of primitive operations. Building that list is pure
// logic, so it is tested on every backend; the native module only has to carry
// out the ops.

///|
/// One primitive operation an executor performs.
pub(all) enum Step {
  /// Instantiate a component under an instance handle.
  Instantiate(String, String)
  /// Bind `from_handle.from_port` to `to_handle.to_port`'s import.
  Bind(String, String, String, String)
  /// Invoke `handle.port` with arguments; result is kept for later steps.
  Call(String, String)
}

///|
pub extend Step with Show::{output}

///|
pub impl Show for Step with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
pub fn Step::to_string(self : Step) -> String {
  match self {
    Instantiate(h, p) => "instantiate \{h} <- \{p}"
    Bind(fh, fp, th, tp) => "bind \{fh}.\{fp} -> \{th}.\{tp}"
    Call(h, p) => "call \{h}.\{p}"
  }
}

///|
/// Build each target's imports from live source exports before instantiation.
pub fn trace(p : @plan.Plan) -> Array[Step] {
  let steps : Array[Step] = []
  for inst in p.instances {
    for w in p.wires {
      if w.to_component == inst.name {
        steps.push(
          Bind(w.from_component, w.from_port, w.to_component, w.to_port),
        )
      }
    }
    steps.push(Instantiate(inst.name, inst.path))
  }
  steps
}

///|
/// Append an explicit call target, independent of topological tie ordering.
pub fn append_call(
  steps : Array[Step],
  component : String,
  port : String,
) -> Unit {
  steps.push(Call(component, port))
}

///|
/// Render a trace, one step per line. Deterministic, so it can be diffed across
/// backends exactly like the plan itself.
pub fn render(steps : Array[Step]) -> String {
  let lines : Array[String] = []
  for s in steps {
    lines.push(s.to_string())
  }
  lines.join("\n")
}
