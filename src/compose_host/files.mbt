///|
pub fn diagnostic(d : @types.Diagnostic) -> String {
  d.code + " " + d.component + " " + d.path.join(" / ") + ": " + d.detail
}

///|
pub fn read(filename : String) -> (String, Map[String, Bytes]) raise {
  let text = @utf8.decode(@fs.read_file_to_bytes(filename), ignore_bom=false)
  let m = @compose.parse(text) catch {
    @compose.Rejected(d) => raise Failure(diagnostic(d))
  }
  let binaries : Map[String, Bytes] = Map([])
  for c in m.components {
    let full = if @path.Path(c.path).is_absolute() { c.path } else {
      @path.Path::join(@path.Path(filename).dirname(), @path.Path(c.path)).to_string()
    }
    let bytes = @fs.read_file_to_bytes(full) catch {
      @fs.IOError(message) => raise Failure("cannot read " + c.name + " at " + full + ": " + message)
    }
    binaries.set(c.name, bytes)
  }
  (text, binaries)
}
