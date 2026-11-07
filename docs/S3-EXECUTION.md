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
- CI 只报告实验适配器类型检查，不再运行没有结果断言的示例链。
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
