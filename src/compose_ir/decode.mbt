///|
fn members(items : ReadOnlyArray[@verifier.Extern]) -> Array[NamedItem] {
  items.map(e => {
    name: e.name,
    item: match e.kind {
      @verifier.Function(i) => Function(i)
      @verifier.Instance(i) => Instance(i)
      @verifier.Type(i) => Type(i)
      @verifier.Value(i) => Value(i)
      @verifier.Component(i) => Component(i)
      @verifier.Module(i) => Module(i)
    },
  }).iter().to_array()
}

///|
fn fields(items : ReadOnlyArray[@verifier.TypeMember]) -> Array[Field] {
  items.map(f => ({ name: f.name, ty: f.ty } : Field)).iter().to_array()
}

///|
fn uses(items : ReadOnlyArray[@verifier.UsedType]) -> Array[Use] {
  items.map(u => {
    name: u.name, original_name: u.original_name, interface: u.interface, ty: u.ty,
  }).iter().to_array()
}

///|
/// Decode once, preserving scope maps, type exports and alias edges. This does
/// not assert compatibility with another component or admit unsupported types.
pub fn decode(name : String, bytes : Bytes) -> Component raise DecodeError {
  let decoded = match @verifier.decode_component_package(bytes, source_id=name) {
    Ok(p) => p
    Err(ds) => raise InvalidComponent(name, ds.map(d => d.render()).join("; "))
  }
  let arena = decoded.types()
  let nodes : Array[Node] = []
  for node in arena {
    let kind : Kind = match node.kind {
      @verifier.Scalar(s) => Scalar(s)
      @verifier.Alias(i) => Alias(i)
      @verifier.Record(fs) => Record(fields(fs))
      @verifier.Tuple(ts) => Tuple(ts.iter().to_array())
      @verifier.List(i) => List(i)
      @verifier.Option(i) => Option(i)
      @verifier.Result(a, b) => Result(a, b)
      @verifier.Variant(cs) => Variant(cs.map(c => ({ name: c.name, ty: c.payload } : Case)).iter().to_array())
      @verifier.Flags(ns) => Flags(ns.iter().to_array())
      @verifier.Enum(ns) => Enum(ns.iter().to_array())
      @verifier.Function(ps, r, a) => Function(fields(ps), r, a)
      @verifier.Interface(n, us, es) => Interface(n, uses(us), members(es))
      @verifier.World(n, us, ins, outs) => World(n, uses(us), members(ins), members(outs))
      @verifier.Resource(i) => Resource(i)
      @verifier.Own(i) => Own(i)
      @verifier.Borrow(i) => Borrow(i)
      @verifier.Future(i) => Future(i)
      @verifier.Stream(i) => Stream(i)
      @verifier.FixedList(i, n) => FixedList(i, n)
      @verifier.Map(k, v) => Map(k, v)
      @verifier.Module(_) => Module
    }
    nodes.push({ name: node.name, kind })
  }
  let world = decoded.world()
  if world < 0 || world >= nodes.length() {
    raise InvalidComponent(name, "missing root world")
  }
  guard nodes[world].kind is World(_, _, imports, exports) else {
    raise InvalidComponent(name, "root is not a world")
  }
  let scopes : Array[Scope] = decoded.components().map(s => {
    world: s.world, parent: s.parent, index: s.index,
    types: s.types.iter().to_array(), functions: s.functions.iter().to_array(),
    values: s.values.iter().to_array(), instances: s.instances.iter().to_array(),
    components: s.components.iter().to_array(), modules: s.modules.iter().to_array(),
  }).iter().to_array()
  { name, world, types: nodes, scopes, imports, exports }
}
