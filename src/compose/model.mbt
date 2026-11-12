///|
pub(all) struct ComponentDecl { name : String; path : String }

///|
pub(all) struct Manifest {
  components : Array[ComponentDecl]
  bindings : Array[@plan.Binding]
}

///|
pub(all) struct Output {
  manifest : Manifest
  plan : @plan.Plan
  json : String
}

///|
pub(all) suberror InputError { Rejected(@types.Diagnostic) }
