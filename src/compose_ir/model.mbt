///|
pub(all) enum Item {
  Function(Int32)
  Instance(Int32)
  Type(Int32)
  Value(Int32)
  Component(Int32)
  Module(Int32)
}

///|
pub(all) struct NamedItem {
  name : String
  item : Item
}

///|
pub(all) struct Field {
  name : String
  ty : Int32
}

///|
pub(all) struct Case {
  name : String
  ty : Int32?
}

///|
/// Preserve use/alias provenance separately from the resolved value structure.
pub(all) struct Use {
  name : String
  original_name : String
  interface : Int32
  ty : Int32
}

///|
pub(all) enum Kind {
  Scalar(String)
  Alias(Int32)
  Record(Array[Field])
  Tuple(Array[Int32])
  List(Int32)
  Option(Int32)
  Result(Int32?, Int32?)
  Variant(Array[Case])
  Flags(Array[String])
  Enum(Array[String])
  Function(Array[Field], Int32?, Bool)
  Interface(String?, Array[Use], Array[NamedItem])
  World(String?, Array[Use], Array[NamedItem], Array[NamedItem])
  // Preserve unsupported constructs explicitly; never erase them to None.
  Resource(Int32?)
  Own(Int32)
  Borrow(Int32)
  Future(Int32?)
  Stream(Int32?)
  FixedList(Int32, Int32)
  Map(Int32, Int32)
  Module
}

///|
pub(all) struct Node {
  name : String?
  kind : Kind
}

///|
/// Binary-local index spaces mapped into this component's resolved arena.
pub(all) struct Scope {
  world : Int32
  parent : Int32?
  index : Int32
  types : Array[Int32]
  functions : Array[Int32]
  values : Array[Int32]
  instances : Array[Int32]
  components : Array[Int32]
  modules : Array[Int32]
}

///|
pub(all) struct Component {
  name : String
  world : Int32
  types : Array[Node]
  scopes : Array[Scope]
  imports : Array[NamedItem]
  exports : Array[NamedItem]
}

///|
pub(all) suberror DecodeError {
  InvalidComponent(String, String)
}
