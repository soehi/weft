///|
/// Structural Merkle SHA-256 for instance-sync-v1. Aliases are transparent;
/// ordered value fields matter, parameter labels and arena numbering do not.
/// Validate first, then use iterative postorder and local DAG memoization.
pub fn fingerprint(c : @ir.Component, index : Int32) -> String raise CompatibilityError {
  supported(c, index, ["signature"])
  let digests : Map[Int32, String] = Map([])
  let work : Array[(Int32, Bool)] = [(index, false)]
  while work.pop() is Some((i, exiting)) {
    if digests.contains(i) { continue }
    let kind = node(c, i, ["signature"])
    let s = shape(c, i, ["signature"])
    if !exiting {
      work.push((i, true))
      for (_, child) in s.edges {
        if child is Some(t) && !digests.contains(t) { work.push((t, false)) }
      }
      continue
    }
    if kind is @ir.Alias(t) {
      digests.set(i, digests.get(t).unwrap())
      continue
    }
    let members = s.edges.map(edge => {
      let value = match edge.1 {
        Some(t) => @json.to_json(digests.get(t).unwrap()).stringify(escape_slash=false)
        None => "null"
      }
      "{\"label\":" + @json.to_json(edge.0).stringify(escape_slash=false) + ",\"digest\":" + value + "}"
    })
    let payload = "weft:type-signature:instance-sync-v1:v1\n{\"tag\":" + @json.to_json(s.tag).stringify(escape_slash=false) + ",\"members\":[" + members.join(",") + "]}"
    digests.set(i, @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(payload, bom=false))))
  }
  digests.get(index).unwrap()
}
