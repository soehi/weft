# D0 完整接口实例探针

这些二进制由`src/probes/instance/fixtures.mbt`中的WAT生成，不表示当前规划器已支持实例级绑定。
`ops`实例导出命名类型`value`和两个函数`inc`、`twice`；消费者导入整个实例，guest依次调用两个函数。

| 文件 | 差异 | Linux探针预期 |
|---|---|---|
| source.wasm | inc为+1，twice为×2 | 输入41，结果84 |
| alternate.wasm | inc为+10，twice为×2 | 输入41，结果102 |
| missing.wasm | ops缺少twice成员 | 消费者实例化失败 |
| wrong-type.wasm | 命名类型value及inc参数为bool | 消费者实例化失败 |
| consumer.wasm | 导入ops并导出run | 不提供ops时实例化失败 |

这些组件自身均有效，失败来自组合关系。没有宿主代算，也不安装文件系统或网络能力。
用固定工具链在仓库根目录重新生成（目录需已存在）：

```bash
moon run src/tools/make_instance_fixtures --target native -- examples/instances
moon test src/probes/instance src/probes/digest --target js
# Linux真实调用；Windows仍只验证静态探针
moon test src/runtime_probe --target native
```

完整边界与证据见[实例探针记录](../../docs/INSTANCE-PROBE.md)。
