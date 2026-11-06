name = "soehi/edgeplan"

version = "0.1.0"

license = "Apache-2.0"

description = "A backend-portable planner for WebAssembly Component deployment on edge devices, in MoonBit"

keywords = [ "wasm", "component-model", "wit", "orchestration", "edge" ]

source = "src"

preferred_target = "wasm-gc"

import {
  "Milky2018/wasm_component@0.18.0",
  "Milky2018/wasm_core@0.18.0",
  "moonrockz/wac@0.3.0",
  "moonrockz/wit@0.3.0",
  "moonbitlang/x@0.5.5",
  "Milky2018/wasmoon@0.18.0",
}
