///|
pub(all) suberror ExecError { Invalid(String); Runtime(String) }

///|
fn scalar_u32(c : @ir.Component, start : Int32) -> Bool {
  let mut i = start
  for _ in 0..=c.types.length() {
    if i < 0 || i >= c.types.length() { return false }
    match c.types[i].kind {
      @ir.Alias(next) => i = next
      @ir.Scalar("u32") => return true
      _ => return false
    }
  }
  false
}

///|
fn check_call(c : @ir.Component, port : String) -> Unit raise ExecError {
  let mut found = -1
  for e in c.exports { if e.name == port && e.item is @ir.Function(i) { found = i } }
  let mut i = found
  for _ in 0..=c.types.length() {
    if i < 0 || i >= c.types.length() { raise Invalid("call target is not an exported function") }
    match c.types[i].kind {
      @ir.Alias(next) => i = next
      @ir.Function(ps, Some(result), false) => {
        if ps.length() == 1 && scalar_u32(c, ps[0].ty) && scalar_u32(c, result) { return }
        raise Invalid("execution supports only one u32 argument and one u32 result")
      }
      _ => raise Invalid("execution supports only synchronous u32 -> u32 calls")
    }
  }
  raise Invalid("invalid call type alias cycle")
}

///|
/// Always compile from the provided bytes before opening an execution session.
/// This D1 entry does not accept externally stored plan JSON as trusted input.
pub fn execute(
  source : String, binaries : Map[String, Bytes],
  target : String, port : String, argument : UInt32,
) -> UInt32 raise ExecError {
  let output = match @compose.compile(source, binaries) {
    Ok(output) => output
    Err(d) => raise Invalid(@host.diagnostic(d))
  }
  if !output.plan.order.contains(target) { raise Invalid("unknown explicit call component") }
  let call_ir = @ir.decode(target, binaries.get(target).unwrap()) catch {
    @ir.InvalidComponent(_, detail) => raise Invalid(detail)
  }
  check_call(call_ir, port)
  let linker = @linker.ComponentLinker::with_core_execution_engine(
    @native.open_native_component_session(),
  ) catch { e => raise Runtime(e.to_string()) }
  defer linker.close()
  let instances : Map[String, @linker.ComponentInstance] = Map([])
  for operation in output.plan.operations {
    match operation {
      @plan.InstallImport(index) => {
        let b = output.plan.bindings[index].binding
        let provider = instances.get(b.from.component).unwrap()
        let mut exported = match provider.get_export(b.from.port) {
          Some(e) => e
          None => raise Invalid("validated source export is absent: " + b.from.port)
        }
        if b.from.member_name is Some(name) {
          guard exported is @linker.Instance(instance) else { raise Invalid("source is not an instance") }
          exported = match instance.get_export(name) {
            Some(e) => e
            None => raise Invalid("validated function member is absent: " + name)
          }
        }
        let correct_kind = match (b.kind, exported) {
          (@plan.Instance, @linker.Instance(_)) | (@plan.Function, @linker.Func(_)) => true
          _ => false
        }
        if !correct_kind { raise Invalid("runtime export kind differs from checked binding") }
        linker.add_import(b.to.port, exported) catch { e => raise Runtime(e.to_string()) }
      }
      @plan.Instantiate(name) => {
        let validated = linker.validate_input(binaries.get(name).unwrap()) catch { e => raise Invalid(e.to_string()) }
        let instance = linker.instantiate(name, validated) catch { e => raise Runtime(name + ": " + e.to_string()) }
        instances.set(name, instance)
      }
    }
  }
  let results = instances.get(target).unwrap().call_exported_func(port, [@linker.U32(argument.reinterpret_as_int())]) catch {
    e => raise Runtime(target + "." + port + ": " + e.to_string())
  }
  guard results is [@linker.U32(value)] else { raise Runtime("result is not exactly one u32") }
  value.reinterpret_as_uint()
}
