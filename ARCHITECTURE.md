# 架构

本文档解释 weft 的分层、数据流，以及每个关键决策背后的理由。README 讲"是什么"，这里讲"为什么这样切"。

## 一眼图

```
             --target native / wasm-gc / js        --target native only
            ┌──────────────────────────────┐      ┌──────────────────────┐
 manifest ──▶│ manifest  →  ir  →  plan     │─JSON─▶│ exec_plan → runtime_ │─▶ wasmoon
 (JSON)      │             ▲                │      │            native    │
             │        wac_adapter           │      └──────────────────────┘
             │             ▲                │
             │       wac/parser+verifier    │
             └──────────────────────────────┘
```

左半边是主交付物：纯逻辑，三后端行为一致。右半边是实验代码：唯一接触运行时的部分，被物理隔离在一个包里。

## 分层与依赖方向

依赖只能自上而下，没有回边：

```
cli  ──▶ plan ──▶ ir ──▶ manifest
 │        │        │
 │        └────────┴──▶ wasm_component / wac / wit / core
 ├──▶ wac_adapter ──▶ manifest
 ├──▶ exec_plan ──▶ plan
 └──▶ runtime_native ──▶ exec_plan, plan, ir, manifest, wasmoon   (native only)
```

硬规则与它的验证方式：

| 规则 | 怎么验证 |
|---|---|
| 规划层不碰 wasmoon | `grep -r wasmoon src/ --include=*.pkg` 只应命中 `runtime_native`（注释不算） |
| 规划层不碰文件系统 | `src/{manifest,ir,plan,wac_adapter,exec_plan}/*.moon.pkg` 无 `moonbitlang/x/fs` |
| `runtime_native` 仅 native | 该包 `supported_targets = "native"` |
| 模块级 wasmoon 依赖不污染纯规划路径 | 外部消费者项目在 **js 后端** `import soehi/weft/plan` 编译通过——`+native` 限制只在真正 import `runtime_native` 的包上生效，模块级声明 `Milky2018/wasmoon` 不会传染 |
| CLI 三后端可编译 | CI 对三个 target 各跑一次 `moon build src/cli` |

## 数据流

### 输入阶段

1. **清单**（`src/manifest`）：JSON → `Manifest`。严格校验形状与引用语法，但**不解析组件**，因此不依赖任何二进制解码。纯字符串 + `core/json`。
2. **组件二进制**（`src/ir`）：每个 `path` 的字节 → `Iface`。这是全项目**唯一**解码组件的地方。

### 解码为什么用 `wac/verifier` 而不是直接读 `wasm_component`

`wasm_component` 的 `model.Export.desc` 对 `(export "f" (func $f))` 这类 sort-only 导出是 `None`。签名实际藏在：

- canon 段的 `Lift(core_func_idx, opts, type_idx)`，以及
- 若干独立索引空间（导入函数、canon 产生的函数、lift 产生的函数）。

要还原它得重建全部索引空间，容易出错且随规范演进漂移。`wac/verifier::decode_component_package` 已经做了这件事，并给出语义模型：

- `BinaryPackage::types()` → 类型 arena
- `BinaryPackage::world()` → arena 中一个 `World(imports, exports, ...)`
- 每个 import/export 是 `Extern{name, kind}`，`kind` 指向 arena
- 接口的 kind 是 `Instance(i)` 或 `Type(i)`，指向 `Interface(externs)`
- 函数是 `Function(params, result, is_async)`
- 标量是 `Scalar("s32")` 等

`src/ir/convert.mbt` 只做一件事：把这张 arena 转成自己的 `TypeDef?` 表与 `PortEntry` 列表，保持索引对齐（arena 的 `i` 就是 IR 表的 `i`）。

`docs/S0-FINDINGS.md` 记录了这条路径的实测证据（六个探针 + 三后端一致性）。

### 语义检查与上游 ABI 的分工

`src/plan/semantic.mbt` 先验证两端函数及可达值类型属于支持子集，然后按双方各自的类型表迭代比较结构。
类型索引只作表内引用，不用于跨组件判等；显式工作栈与已访问类型对避免递归和重复比较。
字段、case、参数名称及顺序参与匹配；未支持类型返回点名组件、端口与值路径的 `Unsupported`。
具体规则见 [支持矩阵](docs/TYPE-SUPPORT.md)。上游 WAC 的 `Check::compatible` 为内部 API，
不在公开接口中；本项目没有绕过可见性或复制资源身份/subtyping 机制。

`src/ir/convert.mbt::to_model_table` 把 IR 表转回 `model.TypeDef?`，索引不变；`flatten_func` 调 `wasm_component::canonical_flat_types`。所以：

- ABI 规则只有一份（上游的），我们不复制。
- `string` → `[i32, i32]`、`list<u32>` → `[i32, i32]` 这些展开由上游负责。
- 我们的测试只需断言结果，不需要维护 ABI 语义。

代价是 `wasm_core/types` 必须作为显式依赖（moon 不允许用传递依赖的类型），已在 `moon.mod` 声明。

### 规划阶段

`src/plan` 的主要职责分布：

- `graph.mbt`：兼容包装，共用 `src/graph` 的图构建、环检测和拓扑排序；WAC 适配器直接依赖此纯逻辑包。图逻辑从清单的 wires 建图。边是 `provider → consumer`，因为 provider 必须先实例化。邻接表排序去重。DFS 找环（显式栈，避免大图递归过深）。Kahn 拓扑排序，ready 集合按名字取最小。
- `bindings.mbt`：完整计划的唯一提供方与导入覆盖检查；整体实例和非函数导入暂时明确拒绝。
- `semantic.mbt`：支持子集验证与严格的跨类型表结构比较。
- `types.mbt`：端口路径解析（`f` 或 `iface.f`）+ canonical 展开 + 两端比较。比较给出**具体的差异**（"parameter 0: i32 vs i64"），不是布尔。
- `emit.mbt`：手写 JSON 拼装。键顺序、数组顺序、数字格式全部显式，不用反射。`plan_body` 是去掉 hash 字段的版本，hash 就覆盖它。
- `planner.mbt`：驱动。先解析所有 wire（保证端口错误先于排序错误被报），再排序、挂 incoming 索引、算 hash。

### 确定性清单

计划字节只依赖以下输入，且每项都被归一化：

| 影响输出的量 | 归一化方式 |
|---|---|
| 组件顺序 | 按名字排序后建图 |
| 邻接表顺序 | 排好序再存 |
| 拓扑序 | Kahn + 名字 tie-break |
| wire 顺序 | 按四元组排序 |
| 字符串比较 | 自有逐码点 `cmp_str`（**不用** `String::compare`） |
| JSON 格式 | 手写，固定键序 |
| hash 覆盖范围 | 规范化计划体（不含 hash 自身） |

`String::compare` 的坑值得单列：本工具链实现是"先比长度、再比内容"，例如 `"zeta".compare("alpha") == -1`。用它排序会得到一个稳定但反直觉的顺序，且把计划确定性绑到核心库实现细节上。因此 `src/ir/order.mbt` 自己定义字典序，全项目统一使用。

### 执行阶段

`src/exec_plan` 把 `Plan` 摊平成原语序列：

```
instantiate reader <- reader.wasm
instantiate filter <- filter.wasm
instantiate sink   <- sink.wasm
bind filter.out -> sink.in
bind reader.read -> filter.in
```

该轨迹目前只验证两阶段顺序。真实组件的 import 可能必须在实例化前提供；它不证明该轨迹可被运行时执行，后续 E1 探针决定是否改为按拓扑序准备 import 后实例化。

`src/runtime_native` 保留实验性的线性链与标量执行代码，但 `Bind` 目前仅查找端口，未安装跨实例 import。CLI 与独立适配器的执行入口均已关闭，返回未支持并退出 1。CI 的适配器 job 仅作类型检查。该包单独门控为 native，其他后端的构建不受影响。

## 为什么执行层单独隔离

三个理由：

1. **平台**：wasmoon 的 C 运行时需要 C11 原子。MSVC 在 `/std:c11` 下不启用 `_Atomic`，需要 `/experimental:c11atomics`；我们无法从 `moon.pkg`/`moon.mod` 注入这个标志（试过的所有方式都失败，记录在 `docs/S3-EXECUTION.md`）。把 wasmoon 留在主模块里会让整个项目在 Windows 上无法 `moon test`。
2. **承诺**：项目的核心承诺是"规划逻辑三后端一致"。wasmoon 一旦进入主模块的测试构建图，这条承诺就无法在本机验证。
3. **责任边界**：wasmoon 上游声明未经审计。隔离在一个包里，README 的"不宣称隔离保证"才有对应的代码边界，而不只是措辞。

## WAC 适配器

`src/wac_adapter` 不做语言工具。它：

- **输入**：`@wac/verifier::verify` 的 `Verified` 模型（需要调用方把组件二进制作为 `dependencies` 传入）。
- **映射**：`CompositionNode` 的 `Instantiate(pkg, ver, args)` → 一个清单组件；参数值是 `Access(node, port)`，反查得到 `(源实例, 端口)` → 一条 wire。
- **拒绝**：spread、嵌套 `new`、rename、整实例连线（非端口级）都报 `Unsupported`，不猜测。
- **输出**：`manifest_to_wac` 生成 `package weft:generated;` 的 WAC，每个组件 `new weft:<name> { ... }`，最后具名 `export`。

往返测试（`wac round trip: manifest -> wac -> plan works`）证明生成的 WAC 能被同一验证器接受并还原出相同连线。

## 测试策略

| 层 | 测什么 | 在哪跑 |
|---|---|---|
| 单元 | 每个包的纯逻辑与恶意输入 | 三后端 |
| 黄金字节 | 示例计划的完整文本 | 三后端（同一份期望） |
| 跨后端 | 三后端生成计划后 `cmp` | CI 的 `plan-identical` |
| 执行轨迹 | 顺序与不变量 | 三后端 |
| 原生执行 | 端到端调用 | CI 的 `runtime-native`（Linux） |

"三后端跑同一份黄金期望"是核心机制：它在**每个**后端上验证同一组字节，而不是只比较两个产物。差异会在具体后端失败，定位更直接。

CI 另有 `plan-identical` 作为冗余的第二道保险——用真实 CLI 生成文件再 `cmp`，覆盖 CLI 的 I/O 与路径解析（例如清单相对路径）。

## 目录

```
src/manifest/       清单模型、JSON 解析、错误类型
src/ir/             组件解码、类型表转换、canonical 展开、自有排序
src/plan/           图、环检测、拓扑序、签名检查、JSON 发射、hash
src/wac_adapter/    WAC ↔ 清单
src/exec_plan/      计划 → 执行轨迹
src/cli/            CLI 核心、native 入口、wasm/js 入口
src/runtime_native/ wasmoon 执行器（native only）
src/tools/          示例组件生成器
examples/           清单与三个真实组件二进制
docs/               S0 实证、S3 现状
```
WAC 的发射顺序、名称与资源边界见 [WAC-SUBSET.md](docs/WAC-SUBSET.md)。
