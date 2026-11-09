// Experimental native execution from validated manifests. CLI entry stays disabled.

///|
pub(all) suberror ExecError {
  Invalid(String)
  Runtime(String)
  UnsupportedValue(String)
}

///|
pub fn ExecError::to_string(self : ExecError) -> String {
  match self {
    Invalid(s) => "exec input: \{s}"
    Runtime(s) => "exec runtime: \{s}"
    UnsupportedValue(s) => "exec unsupported: \{s}"
  }
}

///|
/// Binaries are indexed by component name, exactly as api.compile requires.
/// Target must be explicit. Only scalar call values are accepted.
pub fn execute(
  manifest : String,
  binaries : Map[String, Bytes],
  target : String,
  port : String,
  args : Array[@linker.ComponentValue],
) -> String raise ExecError {
  let output = match @api.compile(manifest, binaries) {
    Ok(output) => output
    Err(diagnostic) => raise Invalid(diagnostic.message)
  }
  let p = output.plan
  if p.resources.max_memory_pages != None || p.resources.quota != None {
    raise Invalid("execution resource limits are unsupported")
  }
  if !p.instances.any(i => i.name == target) || port == "" {
    raise Invalid(
      "explicit call target must name an existing component and export",
    )
  }
  for value in args {
    let _ = show_value(value)
  }
  let linker = @linker.ComponentLinker::with_core_execution_engine(
    @native.open_native_component_session(),
  ) catch {
    e => raise Runtime(e.to_string())
  }
  defer linker.close()
  let instances : Map[String, @linker.ComponentInstance] = Map([])
  // Each consumer gets all its validated imports explicitly overwritten before
  // instantiation. Earlier imports with the same name cannot supply a missing wire:
  // api.compile has already rejected every unbound function import.
  for step in @exec.trace(p) {
    match step {
      @exec.Bind(source, from_port, consumer, to_port) => {
        let src = match instances.get(source) {
          Some(src) => src
          None => raise Invalid("source not instantiated: \{source}")
        }
        let exported = match src.get_export(from_port) {
          Some(exported) => exported
          None => raise Invalid("missing export: \{source}.\{from_port}")
        }
        linker.add_import(to_port, exported) catch {
          e =>
            raise Runtime(
              "\{source}.\{from_port} -> \{consumer}.\{to_port}: \{e}",
            )
        }
      }
      @exec.Instantiate(name, _) => {
        let bytes = binaries.get(name).unwrap()
        let validated = linker.validate_input(bytes) catch {
          e => raise Invalid(e.to_string())
        }
        let inst = linker.instantiate(name, validated) catch {
          e => raise Runtime("\{name}: \{e}")
        }
        instances.set(name, inst)
      }
      @exec.Call(_, _) => ()
    }
  }
  let results = instances.get(target).unwrap().call_exported_func(port, args) catch {
      e => raise Runtime("\{target}.\{port}: \{e}")
    }
  let parts : Array[String] = []
  for result in results {
    parts.push(show_value(result))
  }
  parts.join(", ")
}

///|
/// Render one component-model value. Only scalars are in scope here.
fn show_value(v : @linker.ComponentValue) -> String raise ExecError {
  match v {
    @linker.Bool(b) => b.to_string()
    @linker.S8(n) => n.to_string()
    @linker.U8(n) => n.to_string()
    @linker.S16(n) => n.to_string()
    @linker.U16(n) => n.to_string()
    @linker.S32(n) => n.to_string()
    @linker.U32(n) => n.reinterpret_as_uint().to_string()
    @linker.S64(n) => n.to_string()
    @linker.U64(n) => n.reinterpret_as_uint64().to_string()
    @linker.F32(f) => f.to_string()
    @linker.F64(d) => d.to_string()
    @linker.Char(c) => c.to_string()
    _ => raise UnsupportedValue("non-scalar component value")
  }
}

///|
/// Parse a CLI argument into a component value of the requested scalar kind.
/// `kind` is one of `s32`, `u32`, `s64`, `u64`, `f32`, `f64`, `bool`, `char`.
pub fn parse_arg(
  kind : String,
  text : String,
) -> @linker.ComponentValue raise ExecError {
  match kind {
    "s32" =>
      @linker.S32(
        @strparse.parse_int(text) catch {
          _ => raise UnsupportedValue("s32 from `\{text}`")
        },
      )
    "u32" =>
      @linker.U32(
        @strparse.parse_uint(text).reinterpret_as_int() catch {
          _ => raise UnsupportedValue("u32 from `\{text}`")
        },
      )
    "s64" =>
      @linker.S64(
        @strparse.parse_int64(text) catch {
          _ => raise UnsupportedValue("s64 from `\{text}`")
        },
      )
    "u64" =>
      @linker.U64(
        @strparse.parse_uint64(text).reinterpret_as_int64() catch {
          _ => raise UnsupportedValue("u64 from `\{text}`")
        },
      )
    "f64" =>
      @linker.F64(
        @strparse.parse_double(text) catch {
          _ => raise UnsupportedValue("f64 from `\{text}`")
        },
      )
    "f32" =>
      @linker.F32(
        Float::from_double(
          @strparse.parse_double(text) catch {
            _ => raise UnsupportedValue("f32 from `\{text}`")
          },
        ),
      )
    "bool" => @linker.Bool(text == "true")
    "char" =>
      match text.get_char(0) {
        Some(c) => {
          if text.iter().count() != 1 {
            raise UnsupportedValue("char requires one Unicode scalar")
          }
          @linker.Char(c)
        }
        None => raise UnsupportedValue("char from `\{text}`")
      }
    _ => raise UnsupportedValue("unknown argument kind `\{kind}`")
  }
}
