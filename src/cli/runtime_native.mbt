// Native-only summary path for the `run` subcommand.
//
// The actual wasmoon executor lives in `src/runtime_native`, which is a
// separate executable because linking wasmoon needs a C11-capable toolchain.
// This function validates the manifest and prints the plan summary, so the
// `run` subcommand has a defined behaviour on every native build even when the
// executor binary is not present.

///|
pub fn run_plan(
  manifest_text : String,
  binaries : Map[String, Bytes],
) -> Result[String, String] {
  let input = load_plan_input(manifest_text, binaries) catch {
    e => {
      return Err(e.to_string())
    }
  }
  let p = @plan.plan(input) catch {
    e => {
      return Err(e.to_string())
    }
  }
  let sb = StringBuilder()
  sb.write_string(
    "planned \{p.instances.length()} instance(s), \{p.wires.length()} wire(s), hash \{p.hash}\n",
  )
  for inst in p.instances {
    sb.write_string(
      "  [\{inst.order}] \{inst.name} <- \{inst.path} (\{inst.incoming.length()} incoming)\n",
    )
  }
  sb.write_string(
    "\nto execute, use the `edgeplan_runtime_native` binary (src/runtime_native),\n" +
    "or export WAC with `edgeplan emit-wac` and compose with external tooling.\n",
  )
  Ok(sb.to_string())
}