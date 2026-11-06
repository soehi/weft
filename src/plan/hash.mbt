// A tiny, deterministic, dependency-free content hash.
//
// We deliberately avoid pulling in a crypto dependency: the plan hash exists to
// detect accidental divergence (same input must give the same plan), not to be
// a security primitive. This is FNV-1a 64-bit over the UTF-8 bytes of the plan
// body, rendered as 16 lowercase hex digits.

///|
/// FNV-1a 64-bit over a string, as 16 hex digits.
pub fn fnv1a64_hex(s : String) -> String {
  let mut h : UInt64 = 0xCBF29CE484222325UL
  for c in s {
    for b in utf8_bytes(c.to_int()) {
      h = h ^ b.to_uint64()
      h = h * 0x100000001B3UL
    }
  }
  hex64(h)
}

///|
fn utf8_bytes(cp : Int) -> Array[Int] {
  let out : Array[Int] = []
  if cp < 0x80 {
    out.push(cp)
  } else if cp < 0x800 {
    out.push(0xC0 | (cp >> 6))
    out.push(0x80 | (cp & 0x3F))
  } else if cp < 0x10000 {
    out.push(0xE0 | (cp >> 12))
    out.push(0x80 | ((cp >> 6) & 0x3F))
    out.push(0x80 | (cp & 0x3F))
  } else {
    out.push(0xF0 | (cp >> 18))
    out.push(0x80 | ((cp >> 12) & 0x3F))
    out.push(0x80 | ((cp >> 6) & 0x3F))
    out.push(0x80 | (cp & 0x3F))
  }
  out
}

///|
fn hex64(v : UInt64) -> String {
  let digits = "0123456789abcdef"
  let mut out = ""
  let mut shift = 60
  while shift >= 0 {
    let nib = ((v >> shift) & 0xFUL).to_int()
    out = out + digits.get_char(nib).unwrap_or('0').to_string()
    shift = shift - 4
  }
  out
}