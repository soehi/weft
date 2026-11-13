///|
pub(all) struct Deployment {
  plan_text : String
  lock_text : String
}

///|
/// Only returned after all independent checks. Hosts must use the same bytes
/// they supplied to verify; no file paths are present in this protocol.
pub(all) struct VerifiedDeployment {
  canonical : Bool
  plan : @plan.Plan
}

///|
priv struct Artifact {
  id : String
  digest : String
  length : Int32
}

///|
priv struct LockedInput {
  artifacts : Array[Artifact]
  bindings : Array[@plan.Binding]
}

///|
priv struct DeploymentInstance {
  artifact : Artifact
  order : Int32
  imports : Array[Int32]
}

///|
priv struct DeploymentBinding {
  binding : @plan.Binding
  from_signature : String
  to_signature : String
}

///|
priv struct ParsedDeployment {
  lock_digest : String
  instances : Array[DeploymentInstance]
  bindings : Array[DeploymentBinding]
  operations : Array[@plan.Operation]
  digest : String
}
