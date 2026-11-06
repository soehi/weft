// Dependency graph construction, cycle detection and deterministic topological
// ordering.
//
// Edges point from provider to consumer: `from_component -> to_component`,
// because the provider must be instantiated before the consumer that receives
// its export. Self-wires are rejected as trivial cycles.

///|
/// A component's out-edges, kept as sorted-by-target unique names so traversal
/// order is independent of manifest wire order.
pub(all) struct Graph {
  /// All component names, in lexicographic order.
  nodes : Array[String]
  /// Adjacency: node index -> sorted target indices (unique).
  edges : Array[Array[Int]]
}

///|
/// Find the index of `name` in the lexicographically sorted node list.
fn node_index(nodes : Array[String], name : String) -> Int? {
  let mut lo = 0
  let mut hi = nodes.length() - 1
  while lo <= hi {
    let mid = (lo + hi) / 2
    let c = @ir.cmp_str(nodes[mid], name)
    if c == 0 {
      return Some(mid)
    } else if c < 0 {
      lo = mid + 1
    } else {
      hi = mid - 1
    }
  }
  None
}

///|
/// Build the graph from the manifest. Validates that every wire endpoint names a
/// known component; port existence is checked later by the planner.
pub fn build_graph(m : @manifest.Manifest) -> Graph raise PlanError {
  let names : Array[String] = []
  for c in m.components {
    names.push(c.name)
  }
  names.sort_by(fn(a, b) { @ir.cmp_str(a, b) })
  // Duplicate detection happens in the manifest parser, but keep the invariant
  // here too in case a caller constructs a Manifest by hand.
  let mut i = 1
  while i < names.length() {
    if @ir.cmp_str(names[i - 1], names[i]) == 0 {
      raise InvalidManifest("duplicate component name `\{names[i]}`")
    }
    i = i + 1
  }
  let edges : Array[Array[Int]] = []
  for _ in names {
    edges.push([])
  }
  for w in m.wires {
    let from = match node_index(names, w.from_component) {
      Some(x) => x
      None => raise UnknownComponent(w.from_component)
    }
    let to = match node_index(names, w.to_component) {
      Some(x) => x
      None => raise UnknownComponent(w.to_component)
    }
    edges[from].push(to)
  }
  // Sort and dedupe each adjacency list.
  for i in 0..<edges.length() {
    edges[i].sort_by(fn(a, b) {
      let x = names[a]
      let y = names[b]
      @ir.cmp_str(x, y)
    })
    let out : Array[Int] = []
    for e in edges[i] {
      if out.length() == 0 || out[out.length() - 1] != e {
        out.push(e)
      }
    }
    edges[i] = out
  }
  { nodes: names, edges }
}

///|
/// Depth-first search for a cycle. Returns the cycle's component names in
/// traversal order starting and ending at the same node, or `None`.
fn find_cycle(g : Graph) -> Array[String]? {
  let n = g.nodes.length()
  // 0 = unvisited, 1 = on stack, 2 = done.
  let state : Array[Int] = []
  for _ in 0..<n {
    state.push(0)
  }
  // Explicit DFS stack to avoid deep recursion on large graphs.
  let stack : Array[Int] = []
  let path : Array[Int] = []
  let next_edge : Array[Int] = []
  for _ in 0..<n {
    next_edge.push(0)
  }

  fn dfs_from(start : Int, g : Graph, state : Array[Int], stack : Array[Int], path : Array[Int], next_edge : Array[Int]) -> Array[String]? {
    if state[start] != 0 {
      return None
    }
    state[start] = 1
    stack.push(start)
    path.push(start)
    while stack.length() > 0 {
      let v = stack[stack.length() - 1]
      let eidx = next_edge[v]
      if eidx < g.edges[v].length() {
        next_edge[v] = eidx + 1
        let w = g.edges[v][eidx]
        if state[w] == 0 {
          state[w] = 1
          stack.push(w)
          path.push(w)
        } else if state[w] == 1 {
          // Found a back edge: extract the cycle from `path`.
          let mut at = -1
          let mut i = 0
          while i < path.length() {
            if path[i] == w {
              at = i
              break
            }
            i = i + 1
          }
          let cyc : Array[String] = []
          if at >= 0 {
            let mut j = at
            while j < path.length() {
              cyc.push(g.nodes[path[j]])
              j = j + 1
            }
          }
          cyc.push(g.nodes[w])
          return Some(cyc)
        }
      } else {
        state[v] = 2
        let _ = stack.pop()
        let _ = path.pop()
      }
    }
    None
  }

  for s in 0..<n {
    match dfs_from(s, g, state, stack, path, next_edge) {
      Some(c) => return Some(c)
      None => ()
    }
  }
  None
}

///|
/// Detect cycles. On success the graph is guaranteed a DAG.
pub fn check_acyclic(g : Graph) -> Unit raise PlanError {
  match find_cycle(g) {
    Some(c) => raise Cycle(c)
    None => ()
  }
}

///|
/// Kahn's algorithm with a lexicographic tie-break: among all ready nodes, always
/// take the one whose name sorts first. This makes the order a deterministic
/// function of the graph alone, never of manifest wire order.
pub fn topo_order(g : Graph) -> Array[Int] {
  let n = g.nodes.length()
  let indeg : Array[Int] = []
  for _ in 0..<n {
    indeg.push(0)
  }
  for v in 0..<n {
    for w in g.edges[v] {
      indeg[w] = indeg[w] + 1
    }
  }
  // Ready set kept as a sorted array; we pop the smallest each round. With the
  // scale this planner targets (tens to hundreds of components) this is fine and
  // avoids depending on a priority queue's tie-break semantics.
  let ready : Array[Int] = []
  for v in 0..<n {
    if indeg[v] == 0 {
      ready.push(v)
    }
  }
  let order : Array[Int] = []
  while ready.length() > 0 {
    // `ready` is maintained in name order; take the first.
    let v = ready[0]
    let _ = ready.remove(0)
    order.push(v)
    for w in g.edges[v] {
      indeg[w] = indeg[w] - 1
      if indeg[w] == 0 {
        // Insert keeping `ready` sorted by node name.
        let mut pos = ready.length()
        let mut i = 0
        while i < ready.length() {
          if @ir.cmp_str(g.nodes[w], g.nodes[ready[i]]) < 0 {
            pos = i
            break
          }
          i = i + 1
        }
        ready.insert(pos, w)
      }
    }
  }
  order
}