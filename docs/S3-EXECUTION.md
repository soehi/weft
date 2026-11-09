# S3 执行适配：现状与实证

更新：2026-11-09（E1 执行器集成）。2026-11-05 的类型检查和 MSVC 阻塞仍成立，
但此前将端口查找称作绑定、将 WAC 往返称作执行闭环的结论已撤回。

## 当前状态

- `src/runtime_native` 与独立测试包 `src/runtime_probe` 依赖 wasmoon，均限定 native。
- `moon check src/runtime_native --target native` 只证明类型与上游 API 对齐。
- `executor.mbt` 已改用底层 ComponentLinker，按目标安装源 export 后实例化；Linux 集成验证已通过。
- 纯逻辑轨迹改为逐目标 Bind → Instantiate，5 个测试在三个后端通过，调用目标必须显式指定。
- 示例 reader 返回常数 0；sink 只有 import，没有 CI 之前试图调用的 `read` 导出。
- 通用规划 CLI 的 `weft run` 在所有后端仍报未支持；独立 Linux 原生入口现已提供实验执行命令，见本文末尾。
- CI 保留实验适配器类型检查，并增加独立 `runtime_probe` 的真实执行断言；该探针不调用旧执行器。
- 资源字段仅为计划元数据，未验证执行配额；plan hash 不包含组件二进制内容。
- WAC 库级与 CLI 往返已验证，外部组合和执行尚未验证，不能据此宣称执行闭环。

## Windows/MSVC 链接阻塞

`wasmoon@0.18.0` 的 native C 代码需要 C11 原子。当前 MSVC 在 `/std:c11` 下报：

```
vcruntime_c11_stdatomic.h(12): fatal error C1189: #error: "C atomic support is not enabled"
```

历史尝试：`moon.pkg` / `moon.mod` 的 `link_configs` 被拒绝；`options("cc-flags": ...)`
未作用于依赖包的 stub 编译；临时修改缓存中的依赖配置也未生效。当时没有 WSL 发行版或 clang。
这些事实只描述当时平台，不能用作执行器语义正确的证据。

## 下一步：E1 探针

按 [ROADMAP.md](ROADMAP.md) 的依赖顺序，在 M1 与 M2 之后做 Linux 两组件探针：
确认是否可以在目标实例化时提供源 export；输入 41，源 +1，消费者经 import 调用源并 ×2，
导出 `run` 返回 84。断开或改接 wire 必须改变结果或失败。
只有实际结果与故障断言通过后，才重新开放执行入口并设置独立执行门禁。

wasmoon 上游声明未经审计；本项目不宣称安全隔离保证。

## E1 底层 API 探针（2026-11-08）

固定依赖 `wasmoon@0.18.0` 的高层 `component.ComponentRuntime` 没有公开的自定义
`ComponentHostInstaller` 构造入口；`bind` 仅查找导出。底层 `component/runtime_impl`
公开 `ComponentLinker::add_import`，允许将同一 linker 内源实例的 `get_export` 结果
在目标实例化之前安装到具名 import。该包是上游内部实现层，未来升级需要重新验证。

独立探针使用 `component_native.open_native_component_session`，创建两个真正独立的组件：
源的 core 函数对参数加一；消费者的 core 函数通过组件 import 调用源，再将结果乘二。
不使用返回预期常数的宿主回调，也不在 MoonBit 中代算。

```bash
moon test src/runtime_probe --target native
```

三个断言分别检查输入 41 得到 84、遗漏 `add_import` 时目标实例化失败且错误包含 inc、
改接另一个加二的源得到 86。Windows 本机完成类型检查；提交 `c4fdbee` 的
[Linux CI](https://github.com/soehi/weft/actions/runs/42469369648) 已实际运行，3 passed / 0 failed。
探针直接调用 linker，不接受部署计划，尚未修改执行轨迹或恢复 CLI `run`。

## E1.3 执行器集成（2026-11-09）

实验包新增 `execute(manifest, binaries, target, port, args)`：首先调用 api.compile，
按组件名索引字节（同路径实例也能使用不同字节），拒绝不完整清单，再逐目标准备全部 import 后实例化。
同名 import 每次由当前目标的完整 wires 覆盖，旧 linker 映射不能替代缺失 wire。
源和目标共享同一 linker/store；关闭时统一释放。

`execute_chain` 与隐式最后实例调用已移除，纯轨迹辅助函数改为 append_call 的显式目标。
这是尚未发布实验 API 的不兼容调整，计划 JSON 及已发布规划接口未变。
参数仅接受标量，bool 严格 true/false，char 严格单个 Unicode 标量；无符号数按完整位宽解析/显示。
资源限制请求明确拒绝。新增实际执行器集成测试；提交 `ac63c82` 的 [Linux CI](https://github.com/soehi/weft/actions/runs/42543565157)
实际执行器 5 测试与原有 3 探针均通过。
随后完成的独立命令参数协议、文件 I/O 与失败退出行为见下一节；通用规划 CLI run 仍未支持。

## E1.3 独立命令与 E1.4 限制拒绝（2026-11-09）

Linux x86_64 下使用固定工具链（安装步骤见 release/README.md）：

```bash
moon build src/runtime_native --target native
_build/native/debug/build/runtime_native/runtime_native.exe run examples/execution/chain.json --component consumer --export run --arg u32:41
```

成功输出应为 `84`，退出码 0。原生文件在 Linux 同样名为 runtime_native.exe，可直接执行。
也可使用 `moon run src/runtime_native --target native -- run ...`。组件路径以清单目录为基准，支持绝对路径。
参数支持 s32/u32/s64/u64/f32/f64/bool/char；重复 --arg 按顺序传入。
--component 与 --export 必须各出现一次，未知选项、缺值和额外位置参数拒绝；--help 单独使用退出 0。
参数、读取、规划、实例化、调用或 guest trap 失败均输出 error: 并退出 1。

实际二进制检查由 `python3 scripts/test-native-cli.py` 执行，包含正常/改接结果、跨目录/带空格路径、
断线、错误目标与参数、非法文件、guest trap，以及 quota/max_memory_pages 请求拒绝。提交 `3f81840` 的 [Linux CI](https://github.com/soehi/weft/actions/runs/42544614957) 已通过30项实际 CLI 检查及8项执行器/探针测试。
Windows native 仍受上游 C11 原子构建阻塞，本机只完成类型检查与夹具生成。
独立实验命令不包含在 v0.3.0 规划 CLI 包中；通用 weft run 保持未支持，浏览器也不执行组件。

`examples/execution` 的组件由 `moon run src/tools/make_execution_fixtures --target native -- examples/execution`
重新生成。配额没有声称已执行：任何显式 quota 或 max_memory_pages（包括 0）均拒绝执行，规划仍保存元数据。
