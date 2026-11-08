// Independent module: no filesystem or runtime imports.
///|
fn main {
  let component : Bytes = [0x00, 0x61, 0x73, 0x6d, 0x0d, 0x00, 0x01, 0x00]
  let text = "{\"components\":[{\"name\":\"empty\",\"path\":\"logical/path.wasm\"}]}"
  match @api.compile(text, Map([("empty", component)])) {
    Ok(output) => println(output.json)
    Err(d) => abort(d.code + ": " + d.message)
  }
}
