# 内存规划 API（M3.1）

导入 `soehi/weft/api`。该包及其依赖链不读取文件、环境变量、网络或命令行，也不导入运行时。
输入是已经解码为合法 Unicode 的清单字符串和 `Map[String, Bytes]`；字节按清单组件的**精确名称**索引。
路径只是保留到计划中的逻辑标签，不用于查找文件。额外的字节映射项忽略，调用方传入的 Map 不会被修改。

```moonbit
let component : Bytes = [0x00, 0x61, 0x73, 0x6d, 0x0d, 0x00, 0x01, 0x00]
let manifest = "{\"components\":[{\"name\":\"empty\",\"path\":\"logical/path.wasm\"}]}"
match @api.compile(manifest, Map([("empty", component)])) {
  Ok(output) => println(output.json)
  Err(d) => println(d.code + ": " + d.message)
}
```

`compile` 返回 `Result[Output, Diagnostic]`，不通过异常报告正常输入错误。
`Output.plan` 是规划器的结构化计划；`Output.json` 是编译时由同一 emitter 生成的规范 JSON 快照，
可直接 UTF-8 编码下载。格式版本仍为 0.2.0，见 [FORMAT.md](FORMAT.md)。API 本身不生成文件。
若调用方随后修改计划中的数组，需自行重新序列化，原 JSON 快照不会自动更新。

`load_input` 是可选低层入口：返回 `Result[@plan.Input, Diagnostic]`，只做解析与二进制解码，
**尚未完成**图、类型或绑定检查。一般调用方应使用 `compile`。
CLI 的 `cmd_plan` 直接调用 `compile`；历史 `cli.load_plan_input` 保留为兼容包装，新消费者应使用 api 包。

## 结构化诊断

一次调用返回首个失败。清单失败先返回；缺失/损坏组件按组件名字典序选择；规划错误遵循现有规划器阶段。
不承诺在任意多重无效输入重排后都返回同一个错误，也不聚合全部诊断。

| 字段 | 含义 |
|---|---|
| code | 稳定分支标识；调用方按它判断，不解析 message |
| stage | manifest / input / decode / plan |
| message | 面向用户的完整说明，可随措辞修订 |
| location.component / port | 已知时填入组件名与端口；未知时 None |
| location.field | 已知时为清单字段位置，如 manifest.resources.quota、components[0].path；不是字节范围或 JSON Pointer |
| related | 相关位置列表，如类型不匹配的另一端或环上的组件 |
| detail | 底层补充说明；类型字段/case 的显示路径目前在此，尚不是稳定的机器可解析格式 |

缺少二进制时 `location.field` 为通用 `components.path`，组件由 component 唯一定位，原路径保留在 detail。
没有准确源码范围时不填假 offsets；JSON parser 的原始行列说明保留在 message。
此诊断模型是新增库 API，不改变计划 JSON，也不是 CLI 的 JSON 错误输出选项。

稳定代码：

- 清单：MANIFEST_JSON、MANIFEST_MISSING_FIELD、MANIFEST_FIELD_TYPE、MANIFEST_DUPLICATE_COMPONENT、
  MANIFEST_PORT_REF、MANIFEST_NUMBER、MANIFEST_NEGATIVE_NUMBER、MANIFEST_NUMBER_RANGE、
  MANIFEST_UNKNOWN_FIELD、MANIFEST_VERSION。
- 输入/解码：INPUT_MISSING_BINARY、COMPONENT_DECODE、COMPONENT_UNSUPPORTED_TYPE。
- 规划：PLAN_UNKNOWN_COMPONENT、PLAN_UNKNOWN_PORT、PLAN_PORT_KIND、PLAN_CYCLE、PLAN_TYPE_MISMATCH、
  PLAN_UNSUPPORTED、PLAN_DUPLICATE_BINDING、PLAN_UNBOUND_IMPORT、PLAN_ABI、PLAN_INVALID_INPUT。

## 独立消费者与验证

[examples/consumer](../examples/consumer/README.md) 是独立 MoonBit 模块，只导入 `soehi/weft/api`。
当前工具链通过 `moon.work` 的相对成员路径使用本地源码，不依赖旧版 moon.mod.json 的 path dependency。
这验证外部模块边界，不代表已经在 Mooncakes 发布新 API。

```bash
cd examples/consumer
moon run . --target native
moon run . --target wasm-gc
moon run . --target js
```

`scripts/test-consumer.mjs` 三后端构建并逐字节核对示例输出，已接入本地与 CI 门禁。
API 本轮有 7 个单测，覆盖成功、清单字段、缺字节、解码失败、类型/绑定/未支持语义和环；
CLI 另有一例验证与 API 的规范字节和错误消息完全一致。

这是 M3.1 的开发增量，浏览器文件选择、JS 桥接与页面展示留给 M3.2 / M3.3；
模块仍处于 0.2.0 开发版本，本轮没有发布 registry 或 Release。
