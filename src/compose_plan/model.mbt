///|
pub(all) enum BindingKind { Function; Instance }

///|
pub(all) struct Endpoint {
  component : String
  port : String
  // Explicit function-member access; never split punctuation in a port name.
  member_name : String?
}

///|
pub(all) struct Binding {
  kind : BindingKind
  from : Endpoint
  to : Endpoint
}

///|
pub(all) struct CheckedBinding {
  binding : Binding
  correspondence : @types.Correspondence
}

///|
pub(all) enum Operation {
  InstallImport(Int32)
  Instantiate(String)
}

///|
pub(all) struct Plan {
  order : Array[String]
  bindings : Array[CheckedBinding]
  operations : Array[Operation]
}

///|
pub(all) suberror PlanError {
  Rejected(@types.Diagnostic)
}
