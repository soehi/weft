# S3 执行适配：现状与实证

更新：2026-11-07（M1 能力纠偏）。2026-11-05 的类型检查和 MSVC 阻塞仍成立，
但此前将端口查找称作绑定、将 WAC 往返称作执行闭环的结论已撤回。

## 当前状态

- `src/runtime_native` 是同一模块内唯一依赖 wasmoon 的包，限定 native。
- `moon check src/runtime_native --target native` 只证明类型与上游 API 对齐。
- `executor.mbt` 的 `Bind` 分支只调用端口查找，没有把源 export 安装为目标 import。
- 先全部实例化再 Bind 的纯逻辑轨迹有 5 个跨后端测试，但不证明 import 能在实例化后安装。
- 示例 reader 返回常数 0；sink 只有 import，没有 CI 之前试图调用的 `read` 导出。
- `weft run` 在所有后端明确报未支持并退出 1；独立适配器入口也关闭执行。
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
改接另一个加二的源得到 86。Windows 本机仅完成类型检查；Linux 实际结果待本次 CI 验证。
探针直接调用 linker，不接受部署计划，尚未修改执行轨迹或恢复 CLI `run`。
