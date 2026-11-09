// Experimental executor code is retained for the E1 wiring probe.
// Port lookup alone does not install cross-instance imports.

///|
fn main {
  println(
    "error: execution is unsupported: the experimental executor is not exposed through this command. Use `weft plan`.",
  )
  @sys.exit(1)
}
