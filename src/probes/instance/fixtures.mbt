///|
/// All modes are individually valid components. Only their compatibility differs.
pub fn provider(mode : String) -> Bytes raise {
  let delta = if mode == "alternate" { 10 } else { 1 }
  let value = if mode == "wrong-type" { "bool" } else { "u32" }
  let extra_export = if mode == "missing" { "" } else {
    "(export \"twice\" (func $twice))"
  }
  let initializer = if mode == "trap-start" { "(func $init unreachable) (start $init)" } else { "" }
  @text.parse_component_wat(
    (
      $|(component
      $| (type $value \{value})
      $| (core module $m
      $|  (func (export "inc") (param i32) (result i32)
      $|   local.get 0 i32.const \{delta} i32.add)
      $|  (func (export "twice") (param i32) (result i32)
      $|   local.get 0 i32.const 2 i32.mul)
      $|  \{initializer})
      $| (core instance $i (instantiate $m))
      $| (func $inc (param "x" $value) (result u32)
      $|  (canon lift (core func $i "inc")))
      $| (func $twice (param "x" u32) (result u32)
      $|  (canon lift (core func $i "twice")))
      $| (instance $ops
      $|  (export "value" (type $value))
      $|  (export "inc" (func $inc)) \{extra_export})
      $| (alias export $ops "value" (type $copy))
      $| (export "value-copy" (type $copy))
      $| (export "ops" (instance $ops)))
    ),
  )
}

///|
pub fn consumer() -> Bytes raise {
  @text.parse_component_wat(
    (
      #|(component
      #| (import "ops" (instance $ops
      #|  (type $value u32)
      #|  (export "value" (type (eq $value)))
      #|  (export "inc" (func (param "x" u32) (result u32)))
      #|  (export "twice" (func (param "x" u32) (result u32)))))
      #| (alias export $ops "value" (type $copy))
      #| (alias export $ops "inc" (func $inc))
      #| (alias export $ops "twice" (func $twice))
      #| (core func $lower-inc (canon lower (func $inc)))
      #| (core func $lower-twice (canon lower (func $twice)))
      #| (core module $m
      #|  (import "env" "inc" (func $inc (param i32) (result i32)))
      #|  (import "env" "twice" (func $twice (param i32) (result i32)))
      #|  (func (export "run") (param i32) (result i32)
      #|   local.get 0 call $inc call $twice))
      #| (core instance $i (instantiate $m
      #|  (with "env" (instance
      #|   (export "inc" (func $lower-inc))
      #|   (export "twice" (func $lower-twice))))))
      #| (func (export "run") (param "x" u32) (result u32)
      #|  (canon lift (core func $i "run"))))
    ),
  )
}

///|
/// D1 function binding regression: forward a root import to an explicit call.
pub fn function_consumer() -> Bytes raise {
  @text.parse_component_wat(
    (
      #|(component
      #| (import "inc" (func $inc (param "x" u32) (result u32)))
      #| (core func $lower (canon lower (func $inc)))
      #| (core module $m
      #|  (import "env" "inc" (func $inc (param i32) (result i32)))
      #|  (func (export "run") (param i32) (result i32) local.get 0 call $inc))
      #| (core instance $i (instantiate $m
      #|  (with "env" (instance (export "inc" (func $lower))))))
      #| (func (export "run") (param "x" u32) (result u32)
      #|  (canon lift (core func $i "run"))))
    ),
  )
}

///|
pub fn forwarded_import() -> Bytes raise {
  @text.parse_component_wat(
    "(component (import \"inc\" (func $inc (param \"x\" u32) (result u32))) (export \"run\" (func $inc)))",
  )
}
