# S3 执行适配：现状与实证

日期：2026-11-05。本文件如实记录执行层做到哪一步、在哪一步被平台挡住，以及这对项目结论意味着什么。

## 分层结论

执行层被**物理隔离**：同一模块 `soehi/edgeplan` 下的 `src/runtime_native` 包
是唯一依赖 wasmoon 的包，`supported_targets = "native"`。没有独立的
`moon.mod`——发布物是单一模块。

| 模块 | 依赖 wasmoon | 目标 | 状态 |
|---|---|---|---|
| `soehi/edgeplan`（主模块） | **否** | native / wasm-gc / js | 全绿，`moon test` 三后端全部通过 |
| `src/runtime_native`（包，native only） | **是** | native only | MoonBit 代码 `moon check` 通过；链接阶段被 MSVC 挡住 |

主模块的 `src/**/moon.pkg` 里没有任何 `wasmoon` import（只有注释提到它）。这条隔离是可 grep 验证的，也是项目"规划逻辑全后端可跑"这一核心主张成立的前提。

## 已实现的东西（可读、可测）

### 1. 纯逻辑执行轨迹（`src/exec_plan`，三后端可测）

把 `Plan` 展开成执行器要执行的原语序列：

```
instantiate reader <- reader.wasm
instantiate filter <- filter.wasm
instantiate sink <- sink.wasm
bind filter.out -> sink.in
bind reader.read -> filter.in
```

- 两阶段保证：所有实例化先于所有绑定（绑定时两端必须已存在）。
- 确定性：轨迹文本可直接跨后端 diff。
- **5 个单测在 native / wasm-gc / js 三后端全部通过**。

这一层的价值在于：执行器的**顺序正确性**（拓扑序、两阶段、端点存在性）不依赖任何 native 运行时，因此可以在 CI 的任意后端验证。

### 2. 原生执行器（`runtime_native/src/executor.mbt`）

按 wasmoon 的真实 API 实现，范围刻意收紧：

- `ComponentRuntime::instantiate(path, bytes)` 逐实例化。
- `ComponentInstance::bind(port)` 解析导出/导入端口，失败时带端口名报错。
- `ComponentFunction::call(args)` 调用终点。
- 只支持组件模型**标量**（int/float/bool/char/string）；resource、async、stream/future 明确报 `UnsupportedValue`，不静默近似。
- 资源配额入口保留（`ComponentRuntime::ComponentRuntime(resource_budget=...)`）。

**关键实证**：这份代码 `moon check --target native` 通过（0 警告），说明它与 wasmoon 的公开 API 是对得上的。失败完全发生在 C 运行时编译阶段。

## 阻塞点：Windows/MSVC 的 C11 原子

上游 `wasmoon_runtime/native/ffi` 的 C 文件需要 C11 原子。moon 调用：

```
cl.exe ... /std:c11 /bigobj ... gc_allocator.c /MT
```

MSVC 在 `/std:c11` 下**不接受** `_Atomic`，除非再加 `/experimental:c11atomics`。实测报：

```
vcruntime_c11_stdatomic.h(12): fatal error C1189: #error: "C atomic support is not enabled"
```

尝试过的绕过手段及结果：

| 尝试 | 结果 |
|---|---|
| `moon.pkg` 里 `link_configs { ... cc-flags }` | 拒绝：`Unexpected key 'link_configs' found in moon.pkg` |
| `moon.mod` 里 `link_configs` | 拒绝：`Unexpected key 'link_configs' found in moon.mod` |
| `options("cc-flags": ...)` | 解析通过，但**未作用于依赖包的 stub 编译**（`cl.exe` 命令行没有变化） |
| 临时改缓存里 `wasmoon_runtime/native/ffi/moon.pkg` 加 flags | 同上，未被采纳 |
| WSL | 未安装任何发行版 |
| clang / clang-cl | 本机未安装 |

结论：**在当前 Windows 环境下，`wasmoon@0.18.0` 的 native 后端无法链接**。这不是我们代码的问题，也不是提示词里没预料到的问题——提示词第 1.3 节已明确写出这一点。

## 这意味着什么

- **主交付物（规划器）不受影响**：它从不 import wasmoon，三后端全绿。
- **执行层是"可编译但未能在本平台运行"**：代码正确性靠类型检查 + 纯逻辑轨迹测试保证，但端到端跑不了。
- 按 §7 退路，闭环仍然完整：`edgeplan plan` → `edgeplan emit-wac` → 交给外部 `wasm-tools compose` / `wasmtime` 执行。这条链路已在 S2 双向验证（manifest → WAC → manifest 连线一致）。

## 复现执行层的方法

在 Linux AMD64 或 macOS AArch64 上：

```bash
cd edgeplan
moon build src/runtime_native --target native
moon run src/runtime_native --target native -- examples/chain.json --call read --arg s32:41
```

预期输出：

```
plan hash: <16 hex>
result: <terminal component's scalar result>
```

Windows 上需要 clang-cl 或 WSL（安装任一 Linux 发行版后同上）。

## 诚实边界（写进 README 的同款表述）

- 执行层依赖的 wasmoon 上游自述"未经审计，勿用于生产或安全敏感环境"。我们只宣称**编排策略**，不宣称**隔离保证**。
- 执行层只跑线性链 + 标量；不做热重启、故障恢复、健康检查。
- 执行层在本仓库的当前环境（Windows/MSVC）**无法链接**，这是平台限制，已在 CI 设计中用"Linux native"单独 job 覆盖。