# 浏览器五类案例

这些清单使用根 examples 目录的组件文件；构建 demo 时将清单与真实组件一起复制到 demo/examples。
如需通过 CLI 复现，可将对应清单和它引用的 .wasm 放在同一目录后运行 plan；或参考 scripts/test-demo.mjs 的临时目录流程。

| 文件 | 预期 |
|---|---|
| chain.json | 三实例两连线，计划成功 |
| diamond.json | 四实例分支汇合，计划成功 |
| cycle.json | PLAN_CYCLE |
| type-mismatch.json | PLAN_TYPE_MISMATCH（s32 / s64） |
| missing-import.json | PLAN_UNBOUND_IMPORT |

reader、filter、sink、join、wide-sink 均由 src/tools/make_fixtures 从 WAT 生成。
reader 返回常数，示例只检查规划，不代表运行闭环。
