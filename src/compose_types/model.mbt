///|
pub(all) struct Diagnostic {
  code : String
  component : String
  // Separate segments preserve names containing punctuation without guessing.
  path : Array[String]
  detail : String
}

///|
pub(all) suberror CompatibilityError {
  Rejected(Diagnostic)
}

///|
/// A structural correspondence relation, with consumer IDs first. Several
/// equivalent provider nodes may correspond to one shared consumer value type.
pub(all) struct Correspondence {
  consumer_component : String
  provider_component : String
  pairs : Array[(Int32, Int32)]
}

///|
priv struct Shape {
  tag : String
  edges : Array[(String, Int32?)]
}

///|
priv enum TypeRole { ValueType; FunctionType; InstanceType }
