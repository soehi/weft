# 独立 API 消费者

这是单独的 MoonBit 模块，`moon.pkg` 只导入 `soehi/weft/api`。
`moon.work` 将当前目录与上两级 weft 模块列为成员，以本地源码满足模块依赖。

在本目录执行：

```bash
moon run . --target js
moon run . --target wasm-gc
moon run . --target native
```

输入组件为空组件的固定二进制，清单路径为不存在的逻辑标签；程序不会访问文件系统。
三个后端的计划 hash 应为 `31496a9d30ad1eaf`，JSON 规范内容相同。
根目录运行 `node scripts/test-consumer.mjs` 可执行完整检查。

这里只验证本地 workspace 消费；实际依赖发布版本和干净安装验证属于 M3.4。
