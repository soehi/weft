// Carry out an execution trace with wasmoon.
//
// Scope, deliberately narrow: linear chains of component-model functions whose
// parameters and results are component-model *scalar* values (ints, floats,
// bool, char). No resources, no async, no streams/futures, no interface
// wiring beyond a single named port. Anything outside that is reported, not
// approximated.
//
// This file exists to prove the plan is executable. It is not a general
// component runner; `wasmoon` already is one.

///|
pub(all) suberror ExecError {
  /// A step referenced an instance that was never instantiated.
  MissingInstance(String)
  /// The component binary could not be read.
  BinaryMissing(String)
  /// wasmoon rejected the component.
  Runtime(String)
  /// A value coming back was not a scalar we can pass on.
  UnsupportedValue(String)
}

///|
pub extend ExecError with Show::{output}

///|
pub impl Show for ExecError with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
pub fn ExecError::to_string(self : ExecError) -> String {
  match self {
    MissingInstance(name) => "exec: no instance named `\{name}`"
    BinaryMissing(path) => "exec: cannot read component `\{path}`"
    Runtime(msg) => "exec: \{msg}"
    UnsupportedValue(kind) => "exec: only component-model scalars are supported, got \{kind}"
  }
}

///|
/// Run a linear chain and return the terminal call's result as a display
/// string.
///
/// `binaries` maps a component's manifest `path` to its bytes; `call_port` is
/// the port on the final instance to invoke; `args` are the scalar arguments.
pub fn execute_chain(
  p : @plan.Plan,
  binaries : Map[String, Bytes],
  call_port : String,
  args : Array[@component.ComponentValue],
) -> String raise ExecError {
  let runtime = @component.ComponentRuntime::ComponentRuntime() catch {
    e => raise Runtime(@component.ComponentRuntimeError::to_string(e))
  }
  defer runtime.close()
  let instances : Map[String, @component.ComponentInstance] = Map([])
  let steps = @exec.trace(p)
  // Two phases, matching `@exec.trace`'s guarantee: instantiate everything,
  // then bind. Instantiation must happen first because a bind resolves an
  // export on a live instance.
  for step in steps {
    match step {
      @exec.Instantiate(handle, path) => {
        let bytes = match binaries.get(path) {
          Some(b) => b
          None => raise BinaryMissing(path)
        }
        let inst = runtime.instantiate(path, bytes) catch {
          e => raise Runtime(@component.ComponentRuntimeError::to_string(e))
        }
        instances.set(handle, inst)
      }
      _ => ()
    }
  }
  for step in steps {
    match step {
      @exec.Bind(from_handle, from_port, to_handle, to_port) => {
        // Resolve the source export so a wiring mistake fails with the port
        // name rather than an opaque runtime error.
        let src = match instances.get(from_handle) {
          Some(i) => i
          None => raise MissingInstance(from_handle)
        }
        let _ = src.bind(from_port) catch {
          e => raise Runtime("cannot bind \{from_handle}.\{from_port}: \{@component.ComponentRuntimeError::to_string(e)}")
        }
        // wasmoon wires imports from host installers at instantiation time, so
        // cross-instance wiring is expressed by the component's own imports.
        // We still verify the consumer side exists, which catches a plan whose
        // target component does not actually declare that import.
        let dst = match instances.get(to_handle) {
          Some(i) => i
          None => raise MissingInstance(to_handle)
        }
        let _ = dst.bind(to_port) catch {
          e => raise Runtime("cannot bind \{to_handle}.\{to_port}: \{@component.ComponentRuntimeError::to_string(e)}")
        }
      }
      _ => ()
    }
  }
  let last = p.instances[p.instances.length() - 1]
  let inst = match instances.get(last.name) {
    Some(i) => i
    None => raise MissingInstance(last.name)
  }
  let f = inst.bind(call_port) catch {
    e => raise Runtime("cannot bind \{last.name}.\{call_port}: \{@component.ComponentRuntimeError::to_string(e)}")
  }
  let results = f.call(args) catch {
    e => raise Runtime(@component.ComponentRuntimeError::to_string(e))
  }
  let parts : Array[String] = []
  for v in results {
    parts.push(show_value(v))
  }
  parts.join(", ")
}

///|
/// Render one component-model value. Only scalars are in scope here.
fn show_value(v : @component.ComponentValue) -> String raise ExecError {
  match v {
    @component.Bool(b) => b.to_string()
    @component.S8(n) => n.to_string()
    @component.U8(n) => n.to_string()
    @component.S16(n) => n.to_string()
    @component.U16(n) => n.to_string()
    @component.S32(n) => n.to_string()
    @component.U32(n) => n.to_string()
    @component.S64(n) => n.to_string()
    @component.U64(n) => n.to_string()
    @component.F32(f) => f.to_string()
    @component.F64(d) => d.to_string()
    @component.Char(c) => c.to_string()
    @component.String(s) => s
    _ => raise UnsupportedValue("non-scalar component value")
  }
}

///|
/// Parse a CLI argument into a component value of the requested scalar kind.
/// `kind` is one of `s32`, `u32`, `s64`, `u64`, `f32`, `f64`, `bool`, `char`.
pub fn parse_arg(kind : String, text : String) -> @component.ComponentValue raise ExecError {
  match kind {
    "s32" =>
      @component.S32(@strparse.parse_int(text) catch {
        _ => raise UnsupportedValue("s32 from `\{text}`")
      })
    "u32" =>
      @component.U32(@strparse.parse_uint(text) catch {
        _ => raise UnsupportedValue("u32 from `\{text}`")
      })
    "s64" =>
      @component.S64(@strparse.parse_int64(text) catch {
        _ => raise UnsupportedValue("s64 from `\{text}`")
      })
    "u64" =>
      @component.U64(@strparse.parse_uint64(text) catch {
        _ => raise UnsupportedValue("u64 from `\{text}`")
      })
    "f64" =>
      @component.F64(@strparse.parse_double(text) catch {
        _ => raise UnsupportedValue("f64 from `\{text}`")
      })
    "f32" =>
      @component.F32(
        Float::from_double(
          @strparse.parse_double(text) catch {
            _ => raise UnsupportedValue("f32 from `\{text}`")
          },
        ),
      )
    "bool" => @component.Bool(text == "true")
    "char" =>
      match text.get_char(0) {
        Some(c) => @component.Char(c)
        None => raise UnsupportedValue("char from `\{text}`")
      }
    _ => raise UnsupportedValue("unknown argument kind `\{kind}`")
  }
}