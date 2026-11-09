# 第三方依赖核对

候选模块及源码采用Apache-2.0，根LICENSE包含完整条款。下表来自固定版本实际moon.mod声明；
第三方源码不复制进Mooncakes源码包。core随固定工具链使用，不属于下述17个注册表模块。
规划CLI包含编译后的依赖代码，包内THIRD-PARTY.txt保留模块版本及实际可获取的LICENSE文件。
固定模块根目录未发现NOTICE文件；部分上游模块只声明许可证而未携带独立LICENSE文件，
本表记录所用包元数据及实际文件；运行依赖仍只由独立native包导入。

| 模块 | 版本 | 声明许可证 | 仓库 |
|---|---|---|---|
| Milky2018/aarch64_target | 0.18.0 | Apache-2.0 | https://github.com/Milky2018/wasmoon.git |
| Milky2018/milkir | 0.18.0 | Apache-2.0 | https://github.com/Milky2018/wasmoon.git |
| Milky2018/regalloc | 0.18.0 | Apache-2.0 | https://github.com/Milky2018/wasmoon.git |
| Milky2018/vcode | 0.18.0 | Apache-2.0 | https://github.com/Milky2018/wasmoon.git |
| Milky2018/vcode_regalloc | 0.18.0 | Apache-2.0 | https://github.com/Milky2018/wasmoon.git |
| Milky2018/wasm_component | 0.18.0 | Apache-2.0 | https://github.com/Milky2018/wasmoon.git |
| Milky2018/wasm_core | 0.18.0 | Apache-2.0 | https://github.com/Milky2018/wasmoon.git |
| Milky2018/wasm_milkir | 0.18.0 | Apache-2.0 | https://github.com/Milky2018/wasmoon.git |
| Milky2018/wasmoon | 0.18.0 | Apache-2.0 | https://github.com/Milky2018/wasmoon.git |
| Milky2018/wasmoon_jit | 0.18.0 | Apache-2.0 | https://github.com/Milky2018/wasmoon.git |
| Milky2018/wasmoon_runtime | 0.18.0 | Apache-2.0 | https://github.com/Milky2018/wasmoon.git |
| Milky2018/x64_target | 0.18.0 | Apache-2.0 | https://github.com/Milky2018/wasmoon.git |
| marianoguerra/uri | 0.1.2 | Apache-2.0 | https://github.com/marianoguerra/uri-mb |
| moonbitlang/async | 0.22.4 | Apache-2.0 | https://github.com/moonbitlang/async |
| moonbitlang/x | 0.5.5 | Apache-2.0 | https://github.com/moonbitlang/x |
| moonrockz/wac | 0.3.0 | Apache-2.0 | https://github.com/moonrockz/wasm-devkit |
| moonrockz/wit | 0.3.0 | Apache-2.0 | https://github.com/moonrockz/wasm-devkit |
