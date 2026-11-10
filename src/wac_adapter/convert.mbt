// Verified WAC composition -> our declarative manifest.
//
// The supported, lossless subset is documented in docs/WAC-SUBSET.md.
// Preserve instance export names and direct function arguments; reject shapes
// the manifest cannot represent instead of silently dropping their semantics.

///|
/// A component binary supplied alongside a WAC file, keyed by its WAC package
/// reference (`ns:name`).
pub(all) struct WacDep {
  /// Package name without version, e.g. `components:reader`.
  name : String
  version : String?
  /// Opaque path used in the emitted manifest.
  path : String
  bytes : Bytes
}

///|
pub(all) suberror WacError {
  ParseFailed(Array[String])
  VerifyFailed(Array[String])
  /// A `new` referenced a package that was not supplied in `deps`.
  UnknownDependency(String)
  /// The composition uses a feature outside the adapter's scope.
  Unsupported(String)
  /// Two instantiations share a short name.
  DuplicateInstance(String)
}

///|
pub extend WacError with Show::{output}

///|
pub impl Show for WacError with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
pub fn WacError::to_string(self : WacError) -> String {
  match self {
    ParseFailed(ds) => "wac: parse failed: \{ds.join("; ")}"
    VerifyFailed(ds) => "wac: verification failed: \{ds.join("; ")}"
    UnknownDependency(name) =>
      "wac: instantiation references `\{name}`, which was not supplied as a dependency"
    Unsupported(msg) => "wac: unsupported composition: \{msg}"
    DuplicateInstance(name) => "wac: duplicate instance name `\{name}`"
  }
}

///|
/// Short display name for a package reference: `components:reader@1.0.0` ->
/// `reader`. Falls back to the full reference when there is no `:`.
pub fn short_name(pkg : String) -> String {
  let mut colon = -1
  let mut i = 0
  for c in pkg {
    if c == ':' {
      colon = i
    }
    i = i + 1
  }
  if colon >= 0 && colon + 1 < pkg.length() {
    pkg[colon + 1:].to_owned()
  } else {
    pkg
  }
}

///|
/// Collect verifier diagnostics into renderable `[code] message` strings.
fn render_diags(diags : ReadOnlyArray[@verifier.Diagnostic]) -> Array[String] {
  let out : Array[String] = []
  for d in diags {
    out.push("[\{d.code}] \{d.message}")
  }
  out
}

///|
/// Convert a WAC composition into a manifest.
///
/// `deps` must cover every package the WAC file instantiates. The returned
/// manifest's `path` fields are taken from the matching `WacDep::path`.
pub fn wac_to_manifest(
  source : String,
  deps : Array[WacDep],
) -> @manifest.Manifest raise WacError {
  let parsed = @parser.parse(source)
  if !parsed.is_valid() {
    let ds : Array[String] = []
    for d in parsed.diagnostics {
      ds.push("[\{d.code}] \{d.message}")
    }
    raise ParseFailed(ds)
  }
  // WAC verification is where component signatures get checked; every
  // instantiated package must be supplied so the verifier can resolve it.
  let list : Array[@verifier.PackageSource] = []
  for d in deps {
    list.push({
      name: d.name,
      version: d.version,
      source: d.path,
      bytes: d.bytes,
    })
  }
  let verifier_deps : ReadOnlyArray[@verifier.PackageSource] = ReadOnlyArray::from_array(
    list,
  )
  let model = match
    @verifier.verify(
      parsed,
      source_id="input.wac",
      source~,
      dependencies=verifier_deps,
    ) {
    Ok(m) => m
    Err(diags) => raise VerifyFailed(render_diags(diags))
  }
  // Index deps by `name` and by `name@version` for both lookup styles.
  let by_full : Map[String, WacDep] = Map([])
  for d in deps {
    by_full.set(d.name, d)
    match d.version {
      Some(v) => by_full.set("\{d.name}@\{v}", d)
      None => ()
    }
  }
  // Walk composition nodes. Each `Instantiate(pkg, ver, args)` becomes one
  // component; each argument whose value is an `Access(node, port)` becomes a
  // wire from that node's component to this one.
  let nodes = model.composition()
  // Preserve exactly one whole-instance export per instantiation. Other output
  // shapes and hidden instances have no faithful representation in a manifest.
  let exported : Map[Int32, String] = Map([])
  let used_names : Map[String, Unit] = Map([])
  for e in model.composition_exports() {
    if e.value < 0 || e.value >= nodes.length() {
      raise Unsupported("invalid export node")
    }
    match nodes[e.value].operation {
      @verifier.Instantiate(_, _, _) => ()
      _ =>
        raise Unsupported(
          "export `\{e.name}` is not a whole component instance",
        )
    }
    require_name(e.name, "exported instance")
    if exported.contains(e.value) {
      raise Unsupported("instance exported more than once")
    }
    if used_names.contains(e.name) {
      raise DuplicateInstance(e.name)
    }
    used_names.set(e.name, ())
    exported.set(e.value, e.name)
  }
  // Map composition node id -> component name, filled as we go. WAC orders
  // declarations so a referenced node always precedes its use.
  let node_name : Map[Int32, String] = Map([])
  let components : Array[@manifest.ComponentDecl] = []
  let wires : Array[@manifest.WireDecl] = []
  for n in nodes {
    match n.operation {
      @verifier.Instantiate(pkg, ver, args) => {
        let key = match ver {
          Some(v) => "\{pkg}@\{v}"
          None => pkg
        }
        let dep = match by_full.get(key) {
          Some(d) => d
          None => raise UnknownDependency(key)
        }
        let unique = match exported.get(n.id) {
          Some(name) => name
          None =>
            raise Unsupported(
              "instance from `\{pkg}` is not exported exactly once",
            )
        }
        let name = unique
        components.push({ name: unique, path: dep.path, })
        node_name.set(n.id, unique)
        for a in args {
          if a.value < 0 || a.value >= nodes.length() {
            raise Unsupported("invalid argument node")
          }
          match nodes[a.value].kind {
            @verifier.Function(_) => ()
            _ =>
              raise Unsupported(
                "argument `\{a.name}` on `\{name}` is not a function",
              )
          }
          // The argument's value is usually an `Access(source_node, export)`
          // node, not the instantiation itself. Follow it back to the producing
          // instance before looking up the component name.
          let (src_node, port) = match resolve_access(nodes, a.value) {
            Some(x) => x
            None =>
              raise Unsupported(
                "argument `\{a.name}` on `\{name}` is not a direct port access (node \{a.value})",
              )
          }
          let src_name = match node_name.get(src_node) {
            Some(s) => s
            None =>
              raise Unsupported(
                "argument `\{a.name}` on `\{name}` reads from node \{src_node}, which is not a component instantiation",
              )
          }
          wires.push({
            from_component: src_name,
            from_port: port,
            to_component: unique,
            to_port: a.name,
          })
        }
      }
      @verifier.Import(name) =>
        raise Unsupported("host import `\{name}` is not representable")
      @verifier.Definition =>
        raise Unsupported("local WAC definitions are not representable")
      @verifier.Access(_, _) => ()
    }
  }
  {
    version: "0.2.0",
    components,
    wires,
    resources: { max_memory_pages: None, quota: None, },
  }
}

///|
/// Find the port name a node denotes. A node is either an `Access(_, name)`
/// (an exported function of an instance) or a plain `Definition`.
fn resolve_access(
  nodes : ReadOnlyArray[@verifier.CompositionNode],
  id : Int32,
) -> (Int32, String)? {
  if id < 0 || id >= nodes.length() {
    return None
  }
  // Only `Access(instance_node, export)` can become a wire. A bare instance
  // reference (whole-instance wiring) is legal WAC but outside the manifest's
  // port-to-port model, so it is reported rather than approximated.
  match nodes[id].operation {
    @verifier.Access(instance_node, name) => Some((instance_node, name))
    _ => None
  }
}
