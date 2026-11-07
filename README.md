# weft

> *weft*：织造时横向穿过的纬线。清单里的 `wires` 就是纬线——本项目把它们织成一份计划。

一个用 MoonBit 写的、可编译到 **native / wasm-gc / js** 的 WebAssembly Component **部署计划编译器**，附一个 native 执行适配层作为可行性证明。

它不做运行时、不做分布式、不做静态合成。它只做一件事：**读一份声明式清单和若干组件二进制，算出一份确定性的实例化计划**，并且**同一份输入在三个后端产出逐字节相同的计划**。

---

## 为什么有它

生态里已有的工具各占一块：

| 项目 | 它做什么 | weft 不做什么 |
|---|---|---|
| `wasm-compose` (Rust) | 构建时静态合成，产物是一个 `.wasm` | 不生成合成产物 |
| `wasmCloud` (CNCF) | 分布式集群编排，依赖 NATS/lattice/k8s | 不做网络、不做分布式 |
| `moonrockz/wac` + `wasm-devkit` | WAC/WIT 语言工具链 | 不重写语言工具，**消费**它 |
| `wasmoon` | 组件运行时 | 不做执行引擎，执行层依赖它 |
| `moonkoog` | LLM Agent 编排 | 完全不碰 LLM/Agent |
| `golemcloud/golem_sdk` | 云端 durable agent 平台 | 不做云端平台 |

留下的位置是：**单进程、无外部依赖、可嵌入任何宿主的编排计划编译器**。

价值不在"运行时编排很新"——wasmCloud 已经做了。价值在：**同一份编排逻辑能编译到 native/wasm-gc/js 并在三处行为一致**。`wasm-compose` 的 CLI 是 Rust 原生二进制，`wasmCloud` 需要集群，都做不到在浏览器标签页里对一份清单做静态校验。

---

## 快速开始

```bash
# 生成示例组件（从 WAT 汇编成真实组件二进制）
moon run src/tools/make_fixtures --target native -- examples

# 生成计划
moon run src/cli --target native -- plan examples/chain.json

# 同样的命令，换后端，输出逐字节相同
moon run src/cli --target js -- plan examples/chain.json
```

`examples/chain.json`：

```json
{
  "version": "0.1.0",
  "components": [
    { "name": "reader", "path": "reader.wasm" },
    { "name": "filter", "path": "filter.wasm" },
    { "name": "sink",   "path": "sink.wasm" }
  ],
  "wires": [
    { "from": "reader.read", "to": "filter.in" },
    { "from": "filter.out", "to": "sink.in" }
  ],
  "resources": { "max_memory_pages": 256, "quota": 1000000 }
}
```

输出：

```json
{"plan_version":"0.1.0",
 "instances":[
   {"name":"reader","path":"reader.wasm","order":0,"incoming":[]},
   {"name":"filter","path":"filter.wasm","order":1,"incoming":[1]},
   {"name":"sink","path":"sink.wasm","order":2,"incoming":[0]}],
 "wires":[
   {"from":"filter.out","to":"sink.in","from_signature":"(i32) -> (i32)","to_signature":"(i32) -> (i32)"},
   {"from":"reader.read","to":"filter.in","from_signature":"(i32) -> (i32)","to_signature":"(i32) -> (i32)"}],
 "resources":{"max_memory_pages":256,"quota":1000000},
 "plan_hash":"e96eb1e1a80fbdaa"}
```

（上面为可读性做了换行；实际输出是一行，且该行的字节由 `src/plan/golden_wbtest.mbt` 逐字符断言。）

---

## 子命令

| 命令 | 作用 | 后端 |
|---|---|---|
| `weft plan <manifest> [--out <file>]` | 校验清单与组件二进制，输出确定性计划 JSON | native / wasm-gc / js |
| `weft emit-wac <manifest> [--out <file>]` | 把清单渲染成 WAC，交给外部工具链 | 全部 |
| `weft convert <file.wac> --dep <ns:name>=<path>...` | WAC 组合 → 本工具的清单格式 | 全部 |
| `weft run <manifest>` | 执行（原生适配层） | 仅 native |

`run` 在 wasm-gc/js 上**能编译**，运行时明确报：

```
error: the `run` subcommand requires the native runtime adapter; this build targets wasm-gc/js.
       Use `weft plan` here, or `weft emit-wac` and compose with external tooling.
```

失败时退出码为 1，错误消息总是点名具体对象：

```
$ weft plan cycle.json
error: plan: dependency cycle: filter -> reader -> filter      # 退出码 1

$ weft plan bad.json
error: plan: `sink` has no port `missing`                      # 退出码 1

$ weft plan missing.wasm.json
error: cannot read component `reader` from /path/to/reader.wasm: No such file or directory
```

组件路径相对于**清单文件所在目录**解析，因此 `weft plan examples/chain.json` 在任何工作目录下都成立。

---

## 架构

```
weft/
├── src/
│   ├── manifest/      声明式清单：解析 + 校验（纯逻辑，三后端）
│   ├── ir/            组件二进制 → 干净的接口/类型表（唯一解码点）
│   ├── plan/          ★ 规划器：图构建、环检测、拓扑排序、canonical 签名检查、JSON + hash
│   ├── wac_adapter/   WAC ↔ 清单 双向转换
│   ├── exec_plan/     计划 → 执行轨迹（纯逻辑，三后端可测）
│   ├── cli/           CLI（三后端可编译）
│   ├── runtime_native/  ★ native-only 执行适配（唯一 import wasmoon 的包）
│   └── tools/         开发者工具（生成示例组件）
├── examples/
├── docs/
└── .github/workflows/ci.yml
```

硬性规则，可 grep 验证：

- `manifest` / `ir` / `plan` / `wac_adapter` / `exec_plan` **不 import wasmoon**，只依赖 `wasm_component`、`wac`、`wit`、`core`。
- 只有 `src/runtime_native` import wasmoon，且声明 `supported_targets = "native"`。
- `cli` 三后端都能 `moon build`。

### 解码路径

规划器不直接读 `wasm_component` 的原始 `Export.desc`——对 sort-only 导出它是 `None`，签名藏在 canon 段里。改用 `wac/verifier::decode_component_package` 的语义模型：它把组件解成一张类型 arena，world 类型带命名的 imports/exports、接口内的函数、以及完整的值类型。详见 `docs/S0-FINDINGS.md`。

签名检查复用上游 canonical ABI：把 arena 转回 `model.TypeDef?` 表，调 `wasm_component::canonical_flat_types` 展开成 core 类型。规划器**不复制 ABI 规则**。

---

## 规划器做什么

输入：清单 + 每个组件的二进制。输出：确定性 JSON。

1. **解析组件**：`sniff_binary_kind` → 语义解码 → 校验。失败时报**哪个组件、什么错误**。
2. **提取接口**：world 的 imports/exports，含接口内函数与完整类型表。
3. **连线类型检查**（canonical ABI，**只做函数签名级**）：对每条 wire，把两端签名展开成 core 类型序列后逐项比较。
4. **依赖图 + 环检测**：DFS，报出环上的组件序列。
5. **拓扑排序**：Kahn，同层按组件名字典序 tie-break（自有 `cmp_str`，不依赖库的 `compare`）。
6. **输出计划**：JSON，含实例化顺序、连线绑定、资源配额、`plan_hash`（对规范化后的计划体做 FNV-1a 64）。

### 确定性从哪来

- 组件按名字排序后建图；邻接表排序去重。
- 拓扑排序的 ready 集合始终按名字取最小。
- wire 按 `(from_component, from_port, to_component, to_port)` 排序后才输出。
- 所有字符串比较用 `src/ir/order.mbt` 的逐码点字典序——**不用 `String::compare`**，因为本工具链的实现是"先比长度再比内容"，不是字典序。
- JSON 手写拼装，键顺序、数字格式全部显式。

---

## 测试

```bash
moon test src/manifest src/ir src/plan src/wac_adapter src/exec_plan --target native
moon test src/manifest src/ir src/plan src/wac_adapter src/exec_plan --target wasm-gc
moon test src/manifest src/ir src/plan src/wac_adapter src/exec_plan --target js
```

部署前实测：**75 个测试，三个后端全部通过**。

| 包 | 测试数 | 覆盖 |
|---|---|---|
| `manifest` | 19 | 合法/非法 JSON、缺字段、重复组件、端口路径、负数/小数配额、版本 |
| `ir` | 7 | 函数/接口导入导出、富类型、canonical 展开、排序、解码失败命名 |
| `plan` | 35 | 线性链、菱形、宽扇出、成环（自环/多节点）、未知组件/端口、签名不匹配、接口路径、资源、hash 敏感性、21 节点扇入、黄金字节 |
| `wac_adapter` | 9 | WAC→清单、Access→wire、缺依赖、往返、名称消毒 |
| `exec_plan` | 5 | 两阶段顺序、轨迹确定性、终点调用、空计划 |

**跨后端一致性**由两条机制保证：

1. `src/plan/golden_wbtest.mbt` 把示例计划的完整字节写死在测试里；它在三个后端都跑，任何一个后端的排序/格式/hash 有偏差都会在该后端失败。
2. CI 的 `plan-identical` job 用三个后端分别生成计划文件，再 `cmp` 逐字节比较。

---

## 范围与限制（诚实边界）

- 规划器**只做函数签名级 canonical 检查**。不做 resource 类型语义、不做 async 语义、不做 subtyping。
- **不宣称安全隔离 / 沙箱保证**。隔离语义来自 wasmoon，而 wasmoon 上游自述：

  > "This project is primarily developed with AI assistance and has not been thoroughly audited. **Do not use in production or security-sensitive environments.**"

  本项目只能宣称"编排策略"，不能宣称"隔离保证"。
- 执行层仅支持**线性链 + 组件模型标量**。不做热重启、故障恢复、健康检查、resource/stream/future。
- 执行层平台：Linux AMD64 / macOS AArch64。**Windows 需 clang-cl 或 WSL**（MSVC 在 `/std:c11` 下缺 `_Atomic`，上游 C 运行时报 `C1189`）。见 `docs/S3-EXECUTION.md`。
- 不做分布式、不做集群、不做网络传输——那是 wasmCloud 的领域。
- 不做静态合成产物——那是 wasm-compose 的领域。
- 不重写 WAC 语言——解析与验证全部走 `moonrockz/wac`。本适配器只把**已通过验证**的语义模型映射成清单，遇到 spread、嵌套 `new`、rename 等超出清单模型的结构会明确报 `Unsupported`，不静默近似。
- 生态里已有 `moonrockz/wac`、`wasm-devkit`、`mizchi/wit`、`pei0331/moon-wit` 等工具。本文档不使用"首个""唯一"这类无法证伪的表述。

---

## 执行层现状

执行层代码完整（`src/runtime_native`），`moon check --target native` 通过；链接依赖的 wasmoon C 运行时在当前 Windows/MSVC 环境无法构建。这不是本项目代码的问题，是平台约束，已在设计阶段预料到。

**退路已实现**：`weft emit-wac` 把计划渲染成标准 WAC，交给 `wasm-tools compose` / `wasmtime` 执行。闭环仍然是完整的：**解析 → 规划 → 生成可执行产物**，只是执行器是外部的。这条链路在 S2 做过双向验证（清单 → WAC → 清单，连线一致）。

细节与复现步骤见 `docs/S3-EXECUTION.md`。

---

## 依赖

规划层：`Milky2018/wasm_component@0.18.0`、`Milky2018/wasm_core@0.18.0`、`moonrockz/wac@0.3.0`、`moonrockz/wit@0.3.0`、`moonbitlang/x@0.5.5`、`moonbitlang/core/json`。

执行层额外：`Milky2018/wasmoon@0.18.0`（native only）。

## 许可证

Apache-2.0。