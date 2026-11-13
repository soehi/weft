# weft

> *weft*：织造时横向穿过的纬线。清单里的 `wires` 就是纬线——本项目把它们织成一份计划。

一个用 MoonBit 写的、可编译到 **native / wasm-gc / js** 的 WebAssembly Component **部署计划编译器**，附一个已通过 Linux 实际命令验证的实验性 native 执行适配层。

它不做运行时、不做分布式、不做静态合成。它只做一件事：**读一份声明式清单和若干组件二进制，算出一份确定性的实例化计划**，并且**同一份输入在三个后端产出逐字节相同的计划**。

---

## 安装与验收入口

0.10.19源码兼容同步及构建差异见 [工具链兼容记录](docs/TOOLCHAIN-COMPAT.md)；发布/CI仍使用归档哈希锁定的0.10.20。

当前正式交付：模块/CLI **0.3.1**，计划格式 **0.2.0**。注册表0.3.1已发布并经独立消费者三后端复验。
源码与预构建包同样可用；发布状态见 [候选验收记录](release/CANDIDATE.md)。

| 使用方式 | 入口与状态 |
|---|---|
| 评审材料与复演 | [公开申报书](docs/SUBMISSION.md)（不含联系方式）、[5–10分钟演示](release/DEMO.md)，正式版本证据见 [发布验收记录](release/CANDIDATE.md) |
| 源码构建 | 下方快速开始，固定工具链安装见 [构建说明](release/README.md) |
| Windows/Linux 预构建规划 CLI | [v0.3.1正式Release](https://github.com/soehi/weft/releases/tag/v0.3.1)，Windows/Linux包及SHA-256均已下载复验；见[构建说明](release/README.md) |
| Mooncakes 库 | 已发布 [soehi/weft@0.3.1](https://mooncakes.io/docs/soehi/weft)，依赖固定为0.3.1；[独立注册表消费者](examples/registry-consumer/README.md)已复验 |
| 本地库消费者 | [examples/consumer](examples/consumer/README.md)，通过本地workspace引入，不能替代注册表安装验证 |
| 浏览器本地演示 | [demo](demo/README.md)，用户组件留在本机内存 |
| Linux 可选执行 | [执行说明](docs/S3-EXECUTION.md)，独立实验命令；通用 weft run 仍未支持 |
| main 的接口实例新模式 | [D1开发说明](docs/INSTANCE-COMPOSITION.md)，显式instance-sync-v1与独立源码命令；未包含在已发布0.3.1包中 |

从新源码目录开始（Python 3.12+、Node 24系列；native构建需要平台C工具链）：

```bash
git clone https://github.com/soehi/weft.git
cd weft
python scripts/install-toolchain.py --destination _build/toolchains/pinned
```

Linux shell 的后续配置（当前锁文件支持Linux x86_64）：

```bash
export MOON_HOME="$PWD/_build/toolchains/pinned"
export PATH="$MOON_HOME/bin:$PATH"
moon update
moon check src/api src/cli --target js
python3 scripts/check-release-inputs.py
```

Windows PowerShell 改用：

```powershell
$env:MOON_HOME = Join-Path (Get-Location) '_build/toolchains/pinned'
$env:PATH = (Join-Path $env:MOON_HOME 'bin') + ';' + $env:PATH
moon update
moon check src/api src/cli --target js
python scripts/check-release-inputs.py
```

然后运行已提交的真实组件示例，无需先生成夹具：

```bash
moon run src/cli --target js -- plan examples/chain.json --out plan.json
# 类型错误，应失败并指出source.read/sink.in的签名不匹配
moon run src/cli --target js -- plan examples/type-mismatch.json
# 浏览器：打开 http://127.0.0.1:8000，选择成功链或类型错误示例
node scripts/build-demo.mjs
python scripts/serve-demo.py
```

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

留下的位置是：**单进程、可嵌入宿主的编排计划编译器**。

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
{"plan_version":"0.2.0",
 "instances":[
   {"name":"reader","path":"reader.wasm","order":0,"incoming":[]},
   {"name":"filter","path":"filter.wasm","order":1,"incoming":[1]},
   {"name":"sink","path":"sink.wasm","order":2,"incoming":[0]}],
 "wires":[
   {"from":"filter.out","to":"sink.in","from_signature":"(i32) -> (i32)","to_signature":"(i32) -> (i32)"},
   {"from":"reader.read","to":"filter.in","from_signature":"(i32) -> (i32)","to_signature":"(i32) -> (i32)"}],
 "resources":{"max_memory_pages":256,"quota":1000000},
 "plan_hash":"1a3640bcc99318d5"}
```

（上面为可读性做了换行；实际输出是一行，且该行的字节由 `src/plan/golden_wbtest.mbt` 逐字符断言。）

---

## 子命令

| 命令 | 作用 | 后端 |
|---|---|---|
| `weft plan <manifest> [--out <file>]` | 校验清单与组件二进制，输出确定性计划 JSON | native / wasm-gc / js |
| `weft emit-wac <manifest> [--out <file>]` | 把清单渲染成 WAC，交给外部工具链 | 全部 |
| `weft convert <file.wac> --dep <ns:name>[@version]=<path>... [--out <file>]` | WAC 组合 → 本工具的清单格式 | 全部 |
| `weft run <manifest>` | 预留命令，明确报未支持并退出 1 | 全部 |

`run` 在所有后端均返回 `error: run is unsupported`，退出码为 1。
独立 Linux 原生命令 `src/runtime_native` 已验证真实执行，支持显式调用目标与类型化参数，见下方执行层现状。
查看规划结果使用 `plan`。

`convert` 默认把清单打印到标准输出，`--out` 指定输出文件。`--dep` 的文件路径和
`--out` 均相对于**调用时工作目录**解析；输出清单中的组件路径为规范化的绝对路径，
因此输出文件放到另一目录后仍可直接交给 `plan`。这保证本机可读回，不提供跨机器路径可移植性。
包版本通过 `--dep ns:name@1.0.0=path` 显式提供。
未知选项、缺值、额外位置参数、重复 `--out`、格式错误或同一包版本的重复 `--dep` 均报错。
文件名以 `-` 开头时请使用 `./` 前缀。

失败时退出码为 1，错误消息总是点名具体对象：

```
$ weft plan cycle.json
error: plan: dependency cycle: filter -> reader -> filter      # 退出码 1

$ weft plan bad.json
error: plan: `sink` has no port `missing`                      # 退出码 1

$ weft plan missing.wasm.json
error: cannot read component `reader` from /path/to/reader.wasm: No such file or directory
```

`emit-wac` 按拓扑顺序发射；名称与端口采用明确的小写 kebab 子集，资源字段存在时拒绝转换。
详见 [WAC 支持范围与迁移](docs/WAC-SUBSET.md)。

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
│   ├── runtime_native/  ★ native-only 实验执行命令（Linux 验证）
│   ├── runtime_probe/   Linux 两组件真实连线执行探针
│   └── tools/         开发者工具（生成示例组件）
├── examples/
├── docs/
└── .github/workflows/ci.yml
```

硬性规则，可 grep 验证：

- `manifest` / `ir` / `plan` / `wac_adapter` / `exec_plan` **不 import wasmoon**，只依赖 `wasm_component`、`wac`、`wit`、`core`。
- `src/runtime_native` 与独立测试包 `src/runtime_probe` import wasmoon，均声明 `supported_targets = "native"`。
- `cli` 三后端都能 `moon build`。

### 解码路径

规划器不直接读 `wasm_component` 的原始 `Export.desc`——对 sort-only 导出它是 `None`，签名藏在 canon 段里。改用 `wac/verifier::decode_component_package` 的语义模型：它把组件解成一张类型 arena，world 类型带命名的 imports/exports、接口内的函数、以及完整的值类型。详见 `docs/S0-FINDINGS.md`。

签名检查先遵循 [支持矩阵](docs/TYPE-SUPPORT.md) 做语义结构比较；ABI 检查继续复用上游 canonical ABI：把 arena 转回 `model.TypeDef?` 表，调 `wasm_component::canonical_flat_types` 展开成 core 类型。规划器**不复制 ABI 规则**。

---

## 规划器做什么

输入：清单 + 每个组件的二进制。输出：确定性 JSON。

1. **解析组件**：`sniff_binary_kind` → 语义解码 → 校验。失败时报**哪个组件、什么错误**。
2. **提取接口**：world 的 imports/exports，含接口内函数与完整类型表。
3. **连线类型检查**：先拒绝未支持的函数和值类型语义，再按双方各自的类型表检查严格结构相等，最后用上游 canonical ABI 展开作补充检查。`bool` 和 `u32` 即使同为 i32 也不兼容；规则见 [支持矩阵](docs/TYPE-SUPPORT.md)。
4. **绑定覆盖**：拒绝重复 wire、未绑定 import 和当前无法表达的实例/非函数 import。允许同一 export 连接不同函数 import。
5. **依赖图 + 环检测**：DFS，报出环上的组件序列。
6. **拓扑排序**：Kahn，同层按组件名字典序 tie-break（自有 `cmp_str`，不依赖库的 `compare`）。
7. **输出计划**：JSON，含实例化顺序、连线绑定、资源策略元数据、`plan_hash`（对规范化后的计划体做 FNV-1a 64）。

### 确定性从哪来

- 组件按名字排序后建图；邻接表排序去重。
- 拓扑排序的 ready 集合始终按名字取最小。
- wire 按 `(from_component, from_port, to_component, to_port)` 排序后才输出。
- 所有字符串比较用 `src/ir/order.mbt` 的逐码点字典序——**不用 `String::compare`**，因为本工具链的实现是"先比长度再比内容"，不是字典序。
- JSON 手写拼装，键顺序、数字格式全部显式。

---

## 测试

```bash
moon test src/graph src/manifest src/ir src/plan src/wac_adapter src/exec_plan src/api src/cli --target native
moon test src/graph src/manifest src/ir src/plan src/wac_adapter src/exec_plan src/api src/cli --target wasm-gc
moon test src/graph src/manifest src/ir src/plan src/wac_adapter src/exec_plan src/api src/cli --target js
```

正式 tag `08306e9` 的 [完整 CI](https://github.com/soehi/weft/actions/runs/42613835620)：**139 个独立测试，三个后端各自全部通过**；各后端另外执行 35 项真实 CLI 检查。main 后续兼容维护的证据另见 [工具链兼容记录](docs/TOOLCHAIN-COMPAT.md)。

| 包 | 测试数 | 覆盖 |
|---|---|---|
| `graph` | 3 | 排序参考算法对照、输入排列与边界 |
| `manifest` | 25 | 合法/非法 JSON、缺字段、重复组件、端口路径、负数/小数配额、版本 |
| `ir` | 7 | 函数/接口导入导出、富类型、canonical 展开、排序、解码失败命名 |
| `plan` | 69 | 线性链、菱形、宽扇出、成环（自环/多节点）、未知组件/端口、签名不匹配、接口路径、资源、hash 敏感性、21 节点扇入、黄金字节、语义结构匹配、相同 ABI 反例、未支持类型、重复绑定、import 覆盖与端口索引失效 |
| `wac_adapter` | 18 | WAC→清单、Access→wire、缺依赖、往返、名称消毒 |
| `exec_plan` | 5 | 两阶段顺序、轨迹确定性、终点调用、空计划 |
| `api` | 7 | 内存输入、稳定诊断、缺字节、解码、类型/绑定与环 |
| `cli` | 5 | 严格参数解析、版本与路径保留 |

**跨后端一致性**由两条机制保证：

1. `src/plan/golden_wbtest.mbt` 把示例计划的完整字节写死在测试里；它在三个后端都跑，任何一个后端的排序/格式/hash 有偏差都会在该后端失败。
2. CI 的 `identical` job 与本地入口使用同一 Node 检查程序，直接比较三个后端 `--out` 文件的完整字节，不过滤换行或错误日志。

```bash
bash scripts/check-backends.sh
# Windows PowerShell（需要 moon、node）：
pwsh -NoProfile -File scripts/check-backends.ps1
# 故意失败的隔离夹具：验证两个入口均失败并保留原始诊断（另需 Bash、pwsh）
node scripts/test-gate.mjs
```

Windows 的 `bash` 若指向未安装发行版的 WSL，可设置 `WEFT_TEST_BASH` 为 Git Bash 的完整路径。
门禁包括三后端测试、示例计划逐字节比较，以及带空格目录、非默认文件名、版本依赖、
跨工作目录 `convert → plan` 和非法 CLI 参数的进程退出码检查。

---

## 范围与限制（诚实边界）

- 规划器对函数级 wire 执行严格语义结构匹配与 ABI 检查；async、resource、own/borrow、future/stream、error-context、fixed-list/map 明确报 `Unsupported`。不做 subtyping 或接口实例整体兼容性证明，完整计划要求每个函数 import 恰有一条提供方 wire；导入接口实例与非函数 import 暂时拒绝，详见 [绑定规则](docs/BINDING-RULES.md)。详见 [支持矩阵及迁移说明](docs/TYPE-SUPPORT.md)。
- **不宣称安全隔离 / 沙箱保证**。隔离语义来自 wasmoon，而 wasmoon 上游自述：

  > "This project is primarily developed with AI assistance and has not been thoroughly audited. **Do not use in production or security-sensitive environments.**"

  本项目只能宣称"编排策略"，不能宣称"隔离保证"。
- 实验执行器已通过清单规划到真实跨实例连线的 Linux 集成测试；独立原生命令已验证30项CLI检查。
- Linux 独立探针已验证真实连线、断线和改接；实验执行器及独立原生命令已接入。Windows/MSVC 的 C11 原子链接阻塞仍存在，macOS 未验证。见 `docs/S3-EXECUTION.md`。
- 不做分布式、不做集群、不做网络传输——那是 wasmCloud 的领域。
- 不做静态合成产物——那是 wasm-compose 的领域。
- 不重写 WAC 语言——解析与验证全部走 `moonrockz/wac`。本适配器只把**已通过验证**的语义模型映射成清单，遇到 spread、嵌套 `new`、rename 等超出清单模型的结构会明确报 `Unsupported`，不静默近似。
- 生态里已有 `moonrockz/wac`、`wasm-devkit`、`mizchi/wit`、`pei0331/moon-wit` 等工具。本文档不使用"首个""唯一"这类无法证伪的表述。

---

## 执行层现状

`src/runtime_native` 已改为安装导入后实例化，并显式指定调用组件与导出。实际执行器已通过 5 项 Linux 集成测试。
通用规划 CLI 的 `weft run` 仍未支持；独立原生命令可用。`src/runtime_probe` 在 Linux CI 中通过三个真实执行断言：
41 → 源 +1 → 消费者经 import 调用并 ×2 得到 84，断线实例化失败，改接 +2 得到 86。
Linux 下使用固定工具链执行示例：

```bash
moon run src/runtime_native --target native -- run examples/execution/chain.json --component consumer --export run --arg u32:41
```

输出 `84`、退出码0；失败退出1。清单中的 quota/max_memory_pages 请求均拒绝。
该命令独立构建，不包含在规划 CLI 发布包内；完整参数及复现说明见 [执行层实证](docs/S3-EXECUTION.md)。

`emit-wac` 与 `convert` 已验证库级往返及 CLI 文件往返，外部组合与运行尚未建立固定命令和结果断言，
所以暂不宣称可执行产物闭环。示例组件仅用于规划检查，reader 返回常数 0，sink 没有可调用导出。

`resources` 仅保留策略元数据，不代表配额已经执行。`plan_hash` 是规范计划体的 FNV-1a 64 标识，
不包含组件二进制摘要，不能用作制品完整性或安全校验。同路径、同接口的组件内容变化可能不改变 hash。

细节见 [执行层实证](docs/S3-EXECUTION.md)。

---

## 依赖

规划层：`Milky2018/wasm_component@0.18.0`、`Milky2018/wasm_core@0.18.0`、`moonrockz/wac@0.3.0`、`moonrockz/wit@0.3.0`、`moonbitlang/x@0.5.5`、`moonbitlang/core/json`。

执行层额外：`Milky2018/wasmoon@0.18.0`（native only）。

## 许可证

Apache-2.0。
格式、Schema、Unicode 排序和从 0.1.0 迁移见 [FORMAT.md](docs/FORMAT.md)。新计划输出 0.2.0，模块已发布到 Mooncakes，独立安装验证见examples/registry-consumer。

可嵌入入口为 `soehi/weft/api::compile`：输入清单字符串与组件名字节映射，返回规范计划或结构化诊断。
无文件系统消费者与错误码契约见 [API.md](docs/API.md)，独立示例位于 [examples/consumer](examples/consumer/README.md)。

浏览器演示：运行 `node scripts/build-demo.mjs`、`python scripts/serve-demo.py` 后打开本地 8000 端口。
可选择本地清单和组件、查看依赖图与错误、下载与 CLI 相同的规范计划。附五类真实示例，详见 [demo 使用与验证](demo/README.md)。

CLI/模块版本为 **0.3.1**，可运行 `weft --version` 查看；计划格式仍为 0.2.0。固定工具链、Actions 制品及干净目录首次使用见 [release/README.md](release/README.md)。
