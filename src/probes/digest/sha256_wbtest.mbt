///|
fn digest(bytes : Bytes) -> String {
  @crypto.bytes_to_hex_string(@crypto.sha256(bytes))
}

///|
test "D0 SHA-256 standard byte vectors and multi-block input" {
  for (text, expected) in [
    ("", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
    ("abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
    ("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq", "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"),
    ("abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu", "cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1"),
  ] {
    assert_eq(digest(@utf8.encode(text, bom=false)), expected)
  }
}

///|
test "D0 SHA-256 binary bytes and streaming agree at block boundaries" {
  let bytes = Bytes::makei(256, i => i.to_byte())
  assert_eq(digest(bytes), "40aff2e9d2d8922e47afd4648e6967497158785fbd1da870e7110266bf944880")
  for split in [0, 1, 55, 56, 63, 64, 65, 255, 256] {
    let h = @crypto.SHA256::new()
    h.update(bytes[0:split])
    h.update(bytes[split:])
    assert_eq(@crypto.bytes_to_hex_string(h.finalize()), digest(bytes))
  }
  assert_eq(digest(Bytes::make(1000000, b'a')), "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
}
