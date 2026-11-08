// Plan data model. The emitted JSON is a direct serialization of these types,
// so field order and index order here *are* the plan's byte layout. Keep them
// stable.

///|
/// A resolved wire: both endpoints are concrete ports found during planning.
pub(all) struct PlannedWire {
  from_component : String
  from_port : String
  to_component : String
  to_port : String
  /// Canonical flat core signature of the source export, e.g. `["i32","i32"]`.
  from_flat_params : Array[String]
  from_flat_results : Array[String]
  /// Canonical flat core signature of the destination import.
  to_flat_params : Array[String]
  to_flat_results : Array[String]
}

///|
/// One instance in instantiation order.
pub(all) struct PlannedInstance {
  name : String
  path : String
  /// 0-based position in the topological order.
  order : Int32
  /// Wire indices (into `Plan::wires`) whose destination is this instance.
  incoming : Array[Int32]
}

///|
/// Resource limits, mirroring the manifest but resolved (absent = unconstrained).
pub(all) struct PlannedResources {
  max_memory_pages : Int32?
  quota : Int32?
}

///|
/// The plan proper. `hash` is computed over the normalized plan body, so any
/// change in ordering, wiring or limits changes it.
pub(all) struct Plan {
  plan_version : String
  instances : Array[PlannedInstance]
  wires : Array[PlannedWire]
  resources : PlannedResources
  hash : String
}

///|
/// Planning failures. Every variant names what failed, so a CLI can print a
/// useful message instead of "plan failed".
pub(all) suberror PlanError {
  /// Manifest references a component that is absent from the supplied binaries.
  UnknownComponent(String)
  /// A wire endpoint's component exists but the named port does not.
  UnknownPort(String, String)
  /// A port exists but is an interface, and the wire addressed it as a function
  /// (or vice versa).
  PortKindMismatch(String, String, String)
  /// The dependency graph has a cycle; `members` lists the cycle in order.
  Cycle(Array[String])
  /// Component-value semantics or canonical ABI signatures do not match.
  SignatureMismatch(String, String, String, String, String)
  /// Connected function or value semantics are outside the supported subset.
  Unsupported(String, String, String)
  /// Destination import has more than one wire, including repeated wires.
  DuplicateBinding(String, String, String, String)
  /// A complete deployment plan must cover every function import.
  UnboundImport(String, String)
  /// A type could not be flattened to core value types.
  Unflattenable(String, String)
  /// The same binary was supplied twice under one name; internal consistency.
  InvalidManifest(String)
}

///|
pub extend PlanError with Show::{output}

///|
pub impl Show for PlanError with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
fn flat_list(xs : Array[String]) -> String {
  "[" + xs.join(",") + "]"
}

///|
pub fn PlanError::to_string(self : PlanError) -> String {
  match self {
    UnknownComponent(name) =>
      "plan: wire references unknown component `\{name}`"
    UnknownPort(comp, port) => "plan: `\{comp}` has no port `\{port}`"
    PortKindMismatch(comp, port, want) => "plan: `\{comp}.\{port}` is \{want}"
    Cycle(members) => "plan: dependency cycle: \{members.join(" -> ")}"
    SignatureMismatch(fc, fp, tc, tp, detail) =>
      "plan: signature mismatch on wire \{fc}.\{fp} -> \{tc}.\{tp}: \{detail}"
    Unsupported(comp, port, detail) =>
      "plan: unsupported `\{comp}.\{port}`: \{detail}"
    DuplicateBinding(comp, port, first, second) =>
      "plan: duplicate binding for `\{comp}.\{port}`: \{first} and \{second}"
    UnboundImport(comp, port) => "plan: unbound import `\{comp}.\{port}`"
    Unflattenable(comp, port) =>
      "plan: `\{comp}.\{port}` cannot be flattened by the canonical ABI"
    InvalidManifest(msg) => "plan: \{msg}"
  }
}

///|
/// Render a flat type list for error messages.
pub fn show_flat(xs : Array[String]) -> String {
  flat_list(xs)
}
