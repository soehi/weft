// Public compatibility wrappers over the shared dependency graph package.

///|
pub type Graph = @graph.Graph

///|
pub fn build_graph(m : @manifest.Manifest) -> Graph raise PlanError {
  @graph.build_graph(m) catch {
    @graph.UnknownComponent(n) => raise UnknownComponent(n)
    @graph.InvalidManifest(msg) => raise InvalidManifest(msg)
    @graph.Cycle(names) => raise Cycle(names)
  }
}

///|
pub fn check_acyclic(g : Graph) -> Unit raise PlanError {
  @graph.check_acyclic(g) catch {
    @graph.UnknownComponent(n) => raise UnknownComponent(n)
    @graph.InvalidManifest(msg) => raise InvalidManifest(msg)
    @graph.Cycle(names) => raise Cycle(names)
  }
}

///|
pub fn topo_order(g : Graph) -> Array[Int32] {
  @graph.topo_order(g)
}
