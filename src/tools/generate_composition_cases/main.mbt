///|
fn quote(s : String) -> String { @json.to_json(s).stringify(escape_slash=false) }

///|
fn type_expression(seed : Int32) -> String {
  match seed % 9 {
    0 => "u32"
    1 => "(list u32)"
    2 => "(option u32)"
    3 => "(record (field \"value\" u32) (field \"ready\" bool))"
    4 => "(tuple u32 bool string)"
    5 => "(flags \"read\" \"write\")"
    6 => "(enum \"ready\" \"waiting\")"
    7 => "(variant (case \"some\" u32) (case \"empty\"))"
    _ => "(result u32 (error bool))"
  }
}

///|
fn component(imports : Array[String], value_type : String, missing : Bool) -> String {
  let declarations = imports.map(name => "(import " + quote(name) + " (instance (type $value " + value_type + ") (export \"value\" (type (eq $value)))))")
  let exports = if missing { "" } else { "(export \"value\" (type $local))" }
  "(component " + declarations.join(" ") + " (type $local " + value_type + ") (instance $ops " + exports + ") (export \"ops\" (instance $ops)))"
}

///|
fn write_component(dir : String, filename : String, source : String) -> Unit raise {
  @fs.write_bytes_to_file(dir + "/" + filename + ".wat", @utf8.encode(source, bom=false))
  @fs.write_bytes_to_file(dir + "/" + filename + ".wasm", @text.parse_component_wat(source))
}

///|
fn main {
  try {
    let args = @env.args()
    if args.length() != 2 { raise Failure("expected an existing output directory") }
    let dir = args[1]
    let names = ["delta", "alpha", "echo", "beta", "gamma"]
    for seed in 0..<27 {
      let count = 3 + seed % 3
      let state = Ref(seed.reinterpret_as_uint())
      let bindings : Array[String] = []
      let declarations : Array[String] = []
      let ty = type_expression(seed)
      for target in 0..<count {
        let imports : Array[String] = []
        for source in 0..<target {
          state.val = state.val * 1664525U + 1013904223U
          if (source == 0 && target == count - 1) || (state.val >> 16) % 3U == 0U {
            let port = "need-" + names[source]
            imports.push(port)
            bindings.push("{\"kind\":\"instance\",\"from\":{\"component\":" + quote(names[source]) + ",\"port\":\"ops\"},\"to\":{\"component\":" + quote(names[target]) + ",\"port\":" + quote(port) + "}}")
          }
        }
        let filename = "seed-\{seed}-" + names[target]
        write_component(dir, filename, component(imports, ty, false))
        declarations.push("{\"name\":" + quote(names[target]) + ",\"path\":" + quote(filename + ".wasm") + "}")
      }
      write_component(dir, "seed-\{seed}-wrong", component([], "(list bool)", false))
      write_component(dir, "seed-\{seed}-missing", component([], ty, true))
      let manifest = "{\"manifest_version\":\"0.3.0\",\"profile\":\"instance-sync-v1\",\"components\":[" + declarations.join(",") + "],\"bindings\":[" + bindings.join(",") + "]}"
      @fs.write_bytes_to_file(dir + "/seed-\{seed}.json", @utf8.encode(manifest, bom=false))
    }
  } catch {
    e => { println(e.to_string()); @sys.exit(1) }
  }
}
