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
  let la = a.char_length()
  let lb = b.char_length()
  let n = if la < lb {
    la
  } else {
    lb
  }
  let mut i = 0
  while i < n {
    let ca = a.get_char(i).unwrap_or('\u{0}').to_int()
    let cb = b.get_char(i).unwrap_or('\u{0}').to_int()
    if ca != cb {
      return ca - cb
    }
    i = i + 1
  }
  la - lb
}