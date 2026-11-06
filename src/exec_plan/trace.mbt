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
/// Build the ordered step list: all instantiations (plan order), then all binds
/// (plan's sorted wire order). This is deliberately two phases rather than
/// interleaved, because a bind can only succeed once both endpoints exist.
pub fn trace(p : @plan.Plan) -> Array[Step] {
  let steps : Array[Step] = []
  for inst in p.instances {
    steps.push(Instantiate(inst.name, inst.path))
  }
  for w in p.wires {
    steps.push(Bind(w.from_component, w.from_port, w.to_component, w.to_port))
  }
  steps
}

///|
/// Append a call step for the terminal component of a linear chain: the last
/// instance in plan order, on its first exported port. Used by the demo entry
/// point; a general executor would take the call target from the user.
pub fn append_terminal_call(steps : Array[Step], p : @plan.Plan, port : String) -> Unit {
  let last = p.instances[p.instances.length() - 1]
  steps.push(Call(last.name, port))
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