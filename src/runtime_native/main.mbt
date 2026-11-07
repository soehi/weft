// Experimental executor code is retained for the E1 wiring probe.
// Port lookup alone does not install cross-instance imports.

///|
fn main {
  println(
    "error: execution is unsupported: real cross-instance wiring has not been verified. Use `weft plan`.",
  )
  @sys.exit(1)
}
