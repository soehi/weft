// Deterministic string ordering.
//
// The toolchain's `String::compare` orders by length first, then content. That
// is a stable total order, but it is not the lexicographic order a reader
// expects from a plan file, and leaning on it would make plan determinism a
// property of a core-library implementation detail. We define our own plain
// codepoint-wise lexicographic order and use it everywhere a plan's bytes
// depend on ordering.

///|
/// Lexicographic comparison by Unicode codepoint, shorter prefix first.
/// Returns a negative number if `a < b`, positive if `a > b`, 0 if equal.
pub fn cmp_str(a : String, b : String) -> Int {
  let ai = a.iter()
  let bi = b.iter()
  while true {
    match (ai.next(), bi.next()) {
      (Some(x), Some(y)) => if x != y { return x.to_int() - y.to_int() }
      (None, Some(_)) => return -1
      (Some(_), None) => return 1
      (None, None) => return 0
    }
  } nobreak { 0 }
}
