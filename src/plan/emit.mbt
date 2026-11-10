// Plan emission: deterministic JSON plus a content hash.
//
// The JSON is built by hand rather than by reflection so that key order, array
// order and number formatting are all explicit and cannot drift with a library
// upgrade. That is what makes "byte-identical across backends" checkable.

///|
fn q(s : String) -> String {
  // Delegate escaping to the core library's stringifier so we do not hand-roll
  // JSON escapes (quotes, backslashes, control chars).
  @json.to_json(s).stringify()
}

///|
fn opt_int(v : Int32?) -> String {
  match v {
    Some(n) => n.to_string()
    None => "null"
  }
}

///|
/// Serialize the plan body *without* the hash field. The hash is computed over
/// exactly this string, so it covers every other field by construction.
pub fn plan_body(p : Plan) -> String {
  let inst_parts : Array[String] = []
  for inst in p.instances {
    inst_parts.push(
      "{\"name\":" +
      q(inst.name) +
      ",\"path\":" +
      q(inst.path) +
      ",\"order\":" +
      inst.order.to_string() +
      ",\"incoming\":" +
      q_int_list(inst.incoming) +
      "}",
    )
  }
  let wire_parts : Array[String] = []
  for w in p.wires {
    wire_parts.push(
      "{\"from\":" +
      q("\{w.from_component}.\{w.from_port}") +
      ",\"to\":" +
      q("\{w.to_component}.\{w.to_port}") +
      ",\"from_signature\":" +
      q(
        "(" +
        w.from_flat_params.join(", ") +
        ") -> (" +
        w.from_flat_results.join(", ") +
        ")",
      ) +
      ",\"to_signature\":" +
      q(
        "(" +
        w.to_flat_params.join(", ") +
        ") -> (" +
        w.to_flat_results.join(", ") +
        ")",
      ) +
      "}",
    )
  }
  let res = "{\"max_memory_pages\":" +
    opt_int(p.resources.max_memory_pages) +
    ",\"quota\":" +
    opt_int(p.resources.quota) +
    "}"
  "{\"plan_version\":" +
  q(p.plan_version) +
  ",\"instances\":[" +
  inst_parts.join(",") +
  "],\"wires\":[" +
  wire_parts.join(",") +
  "],\"resources\":" +
  res +
  "}"
}

///|
fn q_int_list(xs : Array[Int32]) -> String {
  let parts : Array[String] = []
  for x in xs {
    parts.push(x.to_string())
  }
  "[" + parts.join(",") + "]"
}

///|
/// Full plan JSON, including the hash.
pub fn plan_json(p : Plan) -> String {
  let body = plan_body(p)
  // Insert the hash as the last field, inside the same object.
  let trimmed = body[:body.length() - 1].to_owned() // drop trailing '}'
  trimmed + ",\"plan_hash\":" + q(p.hash) + "}"
}
