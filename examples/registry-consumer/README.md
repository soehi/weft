# 已发布注册表消费者

此模块没有moon.work，没有本地路径依赖，只导入soehi/weft/api。
先配置固定工具链；注册表版本已发布，普通索引模式先运行moon update，再运行：

```bash
cd examples/registry-consumer
moon run . --target native
moon run . --target wasm-gc
moon run . --target js
```

空组件样例的规范计划hash为31496a9d30ad1eaf。
完整的新目录安装验收（合法链+缺字节+类型错误）在仓库根目录运行：

```bash
node scripts/test-registry-consumer.mjs
```

该验收脚本使用固定工具链的HTTP注册表模式（MOON_REGISTRY_API=1），避免索引更新延迟；
自动创建独立消费者并从注册表解析0.3.1，不引入本地workspace或path override。
