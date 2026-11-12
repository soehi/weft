///|
fn reject(code : String, c : @ir.Component, path : Array[String], detail : String) -> Unit raise CompatibilityError {
  raise Rejected({ code, component: c.name, path, detail })
}

///|
fn node(c : @ir.Component, i : Int32, path : Array[String]) -> @ir.Kind raise CompatibilityError {
  if i < 0 || i >= c.types.length() {
    reject("INVALID_TYPE_REFERENCE", c, path, "type index \{i} outside component arena")
  }
  c.types[i].kind
}

///|
fn resolve(c : @ir.Component, start : Int32, path : Array[String]) -> Int32 raise CompatibilityError {
  let mut i = start
  for _ in 0..=c.types.length() {
    match node(c, i, path) {
      @ir.Alias(next) => i = next
      _ => return i
    }
  }
  reject("CYCLIC_TYPE", c, path, "cyclic alias chain")
  abort("unreachable")
}

///|
fn sorted_items(c : @ir.Component, items : Array[@ir.NamedItem], path : Array[String]) -> Array[@ir.NamedItem] raise CompatibilityError {
  let sorted = items.copy()
  sorted.sort_by((a, b) => @order.cmp_str(a.name, b.name))
  for i in 1..<sorted.length() {
    if sorted[i - 1].name == sorted[i].name {
      reject("DUPLICATE_MEMBER", c, path + [sorted[i].name], "duplicate interface member")
    }
  }
  sorted
}

///|
fn member_type(c : @ir.Component, e : @ir.NamedItem, path : Array[String]) -> Int32 raise CompatibilityError {
  let (i, expected) = match e.item {
    @ir.Function(i) => (i, "function")
    @ir.Instance(i) => (i, "instance")
    @ir.Type(i) => (i, "value type")
    _ => {
      reject("UNSUPPORTED_MEMBER", c, path, "only functions, value types and instances are supported")
      abort("unreachable")
    }
  }
  let actual = node(c, resolve(c, i, path), path)
  let correct = match (expected, actual) {
    ("function", @ir.Function(_, _, _)) => true
    ("instance", @ir.Interface(_, _, _)) => true
    ("value type", @ir.Function(_, _, _) | @ir.Interface(_, _, _) | @ir.World(_, _, _, _) | @ir.Module) => false
    ("value type", _) => true // Unsupported value constructors are rejected by shape.
    _ => false
  }
  if !correct { reject("INVALID_MEMBER_KIND", c, path, "member reference is not a " + expected) }
  i
}

///|
fn shape(c : @ir.Component, i : Int32, path : Array[String]) -> Shape raise CompatibilityError {
  let edges : Array[(String, Int32?)] = []
  let tag = match node(c, i, path) {
    @ir.Scalar(s) => {
      if !["bool", "s8", "u8", "s16", "u16", "s32", "u32", "s64", "u64", "f32", "f64", "char", "string"].contains(s) {
        reject("UNSUPPORTED_TYPE", c, path, s)
      }
      "scalar:" + s
    }
    @ir.Alias(t) => { edges.push(("alias", Some(t))); "alias" }
    @ir.Record(fs) => {
      let names : Map[String, Unit] = Map([])
      for f in fs {
        if names.contains(f.name) { reject("DUPLICATE_MEMBER", c, path + [f.name], "duplicate record field") }
        names.set(f.name, ())
        edges.push(("field:" + f.name, Some(f.ty)))
      }
      "record"
    }
    @ir.Tuple(ts) => {
      for j in 0..<ts.length() { edges.push(("tuple:\{j}", Some(ts[j]))) }
      "tuple"
    }
    @ir.List(t) => { edges.push(("element", Some(t))); "list" }
    @ir.Option(t) => { edges.push(("some", Some(t))); "option" }
    @ir.Result(a, b) => { edges.push(("ok", a)); edges.push(("err", b)); "result" }
    @ir.Variant(cs) => {
      let names : Map[String, Unit] = Map([])
      for entry in cs {
        if names.contains(entry.name) { reject("DUPLICATE_MEMBER", c, path + [entry.name], "duplicate variant case") }
        names.set(entry.name, ())
        edges.push(("case:" + entry.name, entry.ty))
      }
      "variant"
    }
    @ir.Flags(ns) | @ir.Enum(ns) => {
      let names : Map[String, Unit] = Map([])
      for n in ns {
        if names.contains(n) { reject("DUPLICATE_MEMBER", c, path + [n], "duplicate name") }
        names.set(n, ())
        edges.push((n, None))
      }
      if node(c, i, path) is @ir.Flags(_) { "flags" } else { "enum" }
    }
    @ir.Function(ps, result, is_async) => {
      if is_async { reject("UNSUPPORTED_TYPE", c, path, "async function") }
      for j in 0..<ps.length() { edges.push(("parameter:\{j}", Some(ps[j].ty))) }
      edges.push(("result", result))
      "function"
    }
    @ir.Interface(_, used, items) => {
      for u in used {
        let _ = node(c, u.ty, path + ["use:" + u.name])
        if !(node(c, resolve(c, u.interface, path), path) is @ir.Interface(_, _, _)) {
          reject("INVALID_TYPE_REFERENCE", c, path + ["use:" + u.name], "use source is not an interface")
        }
      }
      for entry in sorted_items(c, items, path) {
        let suffix = match entry.item {
          @ir.Function(_) => "function:"
          @ir.Instance(_) => "instance:"
          @ir.Type(_) => "type:"
          _ => "unsupported:"
        }
        edges.push((suffix + entry.name, Some(member_type(c, entry, path + [entry.name]))))
      }
      "instance"
    }
    _ => {
      reject("UNSUPPORTED_TYPE", c, path, "resource, handle, async, fixed-list, map, module or world type")
      abort("unreachable")
    }
  }
  { tag, edges }
}

///|
// Validate each side independently before memoizing pairs. A visiting node is
// a cycle, while a completed node may be shared. This is not coinductive matching.
fn supported(c : @ir.Component, start : Int32, path : Array[String]) -> Unit raise CompatibilityError {
  let states : Map[Int32, Bool] = Map([])
  let work : Array[(Int32, Array[String], Bool)] = [(start, path, false)]
  while work.pop() is Some((i, at, exiting)) {
    if exiting { states.set(i, false); continue }
    match states.get(i) {
      Some(true) => reject("CYCLIC_TYPE", c, at, "recursive type graph")
      Some(false) => continue
      None => ()
    }
    states.set(i, true)
    work.push((i, at, true))
    let s = shape(c, i, at)
    if node(c, i, at) is @ir.Interface(_, used, _) {
      for u in used { work.push((u.ty, at + ["use:" + u.name], false)) }
    }
    for j = s.edges.length() - 1; j >= 0; j = j - 1 {
      let (label, child) = s.edges[j]
      if child is Some(t) { work.push((t, at + [label], false)) }
    }
  }
}

///|
fn root(c : @ir.Component, items : Array[@ir.NamedItem], name : String, path : Array[String]) -> Int32 raise CompatibilityError {
  let sorted = sorted_items(c, items, path)
  for e in sorted {
    if e.name == name {
      guard e.item is @ir.Instance(i) else {
        reject("INVALID_MEMBER_KIND", c, path + [name], "expected whole instance")
        abort("unreachable")
      }
      let _ = member_type(c, e, path + [name])
      return i
    }
  }
  reject("MISSING_MEMBER", c, path + [name], "instance does not exist")
  abort("unreachable")
}

///|
/// Conservative synchronous non-resource profile. The provider may export more
/// supported members. Function labels are ignored; value-field/case order is not.
pub fn check_instance(
  provider : @ir.Component, export_name : String,
  consumer : @ir.Component, import_name : String,
) -> Correspondence raise CompatibilityError {
  let pi = root(provider, provider.exports, export_name, ["exports"])
  let ci = root(consumer, consumer.imports, import_name, ["imports"])
  compare(provider, pi, ["exports", export_name], consumer, ci, ["imports", import_name])
}

///|
fn named(c : @ir.Component, entries : Array[@ir.NamedItem], name : String, at : Array[String]) -> @ir.NamedItem raise CompatibilityError {
  for e in sorted_items(c, entries, at) { if e.name == name { return e } }
  reject("MISSING_MEMBER", c, at + [name], "member does not exist")
  abort("unreachable")
}

///|
/// Function binding in the new profile. A source may be one explicitly named
/// member of an exported interface; a consumer import must be a root function.
pub fn check_function(
  provider : @ir.Component, export_name : String, member_name : String?,
  consumer : @ir.Component, import_name : String,
) -> Correspondence raise CompatibilityError {
  let mut entry = named(provider, provider.exports, export_name, ["exports"])
  let mut at = ["exports", export_name]
  if member_name is Some(name) {
    guard entry.item is @ir.Instance(i) else {
      reject("INVALID_MEMBER_KIND", provider, at, "function member requires an instance")
      abort("unreachable")
    }
    guard node(provider, resolve(provider, i, at), at) is @ir.Interface(_, _, es) else {
      reject("INVALID_MEMBER_KIND", provider, at, "invalid source instance")
      abort("unreachable")
    }
    entry = named(provider, es, name, at)
    at = at + [name]
  }
  guard entry.item is @ir.Function(pi) else {
    reject("INVALID_MEMBER_KIND", provider, at, "expected source function")
    abort("unreachable")
  }
  let _ = member_type(provider, entry, at)
  let target = named(consumer, consumer.imports, import_name, ["imports"])
  guard target.item is @ir.Function(ci) else {
    reject("INVALID_MEMBER_KIND", consumer, ["imports", import_name], "expected root function import")
    abort("unreachable")
  }
  let _ = member_type(consumer, target, ["imports", import_name])
  compare(provider, pi, at, consumer, ci, ["imports", import_name])
}

///|
fn compare(
  provider : @ir.Component, pi : Int32, provider_path : Array[String],
  consumer : @ir.Component, ci : Int32, consumer_path : Array[String],
) -> Correspondence raise CompatibilityError {
  supported(provider, pi, provider_path)
  supported(consumer, ci, consumer_path)
  let work : Array[(Int32?, Int32?, Array[String])] = [(Some(ci), Some(pi), consumer_path)]
  let seen : Map[(Int32, Int32), Unit] = Map([])
  let pairs : Array[(Int32, Int32)] = []
  while work.pop() is Some((ct, pt, at)) {
    match (ct, pt) {
      (None, None) => continue
      (Some(c), Some(p)) => {
        let c = resolve(consumer, c, at)
        let p = resolve(provider, p, provider_path)
        if seen.contains((c, p)) { continue }
        seen.set((c, p), ())
        pairs.push((c, p))
        let cs = shape(consumer, c, at)
        let ps = shape(provider, p, provider_path)
        if cs.tag != ps.tag {
          reject("TYPE_MISMATCH", consumer, at, "expected " + cs.tag + ", provider has " + ps.tag)
        }
        if cs.tag == "instance" {
          let provider_members : Map[String, Int32?] = Map([])
          for (label, value) in ps.edges { provider_members.set(label, value) }
          for (label, _) in cs.edges {
            if !provider_members.contains(label) {
              reject("MISSING_MEMBER", consumer, at + [label], "provider lacks required member")
            }
          }
          for j = cs.edges.length() - 1; j >= 0; j = j - 1 {
            let (label, value) = cs.edges[j]
            work.push((value, provider_members.get(label).unwrap(), at + [label]))
          }
        } else {
          if cs.edges.length() != ps.edges.length() {
            reject("TYPE_MISMATCH", consumer, at, "member or parameter arity differs")
          }
          for j in 0..<cs.edges.length() {
            if cs.edges[j].0 != ps.edges[j].0 {
              reject("TYPE_MISMATCH", consumer, at + [cs.edges[j].0], "ordered member name differs")
            }
          }
          for j = cs.edges.length() - 1; j >= 0; j = j - 1 {
            work.push((cs.edges[j].1, ps.edges[j].1, at + [cs.edges[j].0]))
          }
        }
      }
      _ => reject("TYPE_MISMATCH", consumer, at, "payload or result presence differs")
    }
  }
  pairs.sort_by((a, b) => if a.0 == b.0 { a.1 - b.1 } else { a.0 - b.0 })
  { consumer_component: consumer.name, provider_component: provider.name, pairs }
}
