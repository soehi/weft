// Independent oracle: scan every node for the smallest eligible one.

///|
fn scan_order(g : Graph) -> Array[Int32] {
  let degree = Array::make(g.nodes.length(), 0)
  let used = Array::make(g.nodes.length(), false)
  for edges in g.edges {
    for target in edges {
      degree[target] += 1
    }
  }
  let result : Array[Int32] = []
  while result.length() < g.nodes.length() {
    let mut candidate : Int32? = None
    for v in 0..<g.nodes.length() {
      if !used[v] && degree[v] == 0 {
        candidate = Some(v)
        break
      }
    }
    match candidate {
      None => break
      Some(v) => {
        result.push(v)
        used[v] = true
        for target in g.edges[v] {
          degree[target] -= 1
        }
      }
    }
  }
  result
}

///|
test "topo: exhaustive five-node DAG families agree with scan oracle" {
  let nodes = ["a", "aa", "b", "尾", "🧵"]
  nodes.sort_by(@ir.cmp_str)
  for rank in [[0, 1, 2, 3, 4], [3, 1, 4, 0, 2]] {
    for mask in 0..<1024 {
      let edges : Array[Array[Int32]] = [[], [], [], [], []]
      let mut bits = mask
      for i in 0..<5 {
        for j in (i + 1)..<5 {
          if bits % 2 == 1 {
            edges[rank[i]].push(rank[j])
          }
          bits = bits / 2
        }
      }
      for row in edges {
        row.sort_by((a, b) => a - b)
      }
      let g = { nodes, edges, }
      assert_eq(topo_order(g), scan_order(g))
    }
  }
}

///|
test "topo: wide ready set releases low-ranked nodes before later roots" {
  let nodes = Array::makei(1000, i => i.to_string())
  nodes.sort_by(@ir.cmp_str)
  let edges : Array[Array[Int32]] = Array::makei(1000, _ => [])
  for i in 0..<999 {
    edges[999].push(i)
  }
  let order = topo_order({ nodes, edges, })
  assert_eq(order[0], 999)
  for i in 0..<999 {
    assert_eq(order[i + 1], i)
  }
}

///|
test "topo: empty graph and cyclic partial progress preserve behavior" {
  assert_eq(topo_order({ nodes: [], edges: [], }), [])
  let g = { nodes: ["a", "b", "c"], edges: [[1], [0], []], }
  assert_eq(topo_order(g), [2])
}
