# Linux 实验执行示例

固定工具链安装见 ../../release/README.md。运行：

```bash
moon run src/runtime_native --target native -- run examples/execution/chain.json --component consumer --export run --arg u32:41
```

源组件加1，消费者经 import 调用源后乘2，结果84。
将 source 路径改为 alternate.wasm 后结果86；删除 wire 将被拒绝。
trap.wasm 提供触发 guest trap 的 run 导出，用于失败退出码测试。

从 WAT 定义重新生成全部组件：

```bash
moon run src/tools/make_execution_fixtures --target native -- examples/execution
```

源码定义位于 src/tools/make_execution_fixtures/main.mbt，测试在独立临时目录重新生成并运行。
本示例不设置资源限制；执行请求含 quota/max_memory_pages 将被拒绝。
