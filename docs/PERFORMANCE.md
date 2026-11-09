# 规划器规模基线

按 ROADMAP.md 第5节先测量，再决定是否优化。使用真实组件二进制和实际 CLI，
覆盖总计100、1,000个组件的链、扇出与扇入，每种均有 N−1 条 wire，所有 import 均完整绑定。
扇入末端有 N−1 个独立函数 import；各组件字节会按实际 CLI 路径重复读取、解码，不预先缓存接口。

在仓库根目录启用 release/README.md 的固定工具链后运行：

```bash
node scripts/benchmark-planner.mjs 3
```

需要 Node、MoonBit 与 native C 编译环境，不依赖 wasmoon 执行器。夹具生成、三个后端的 debug
构建不计时。每场景/后端先作一次不计时预热，再对全新 CLI 进程采样3次，保留原始毫秒值、最小值、中位数。
每个计时样本包括进程启动、文件读取、组件解码、语义校验、图算法和 JSON 输出写入。
OS 文件缓存通常已热；这不是纯拓扑排序基准，也不是完全冷启动磁盘测试，不用于宣称执行器吞吐。

每次检查实例数、完整 wire 集合及拓扑先后关系；三个后端输出必须逐字节一致。
每个计时样本也核对字节，再额外反转 components/wires 输入验证确定性。
异常、非零退出、单次超过120秒或结果不符会使脚本失败，不输出成功报告。

报告输出 `_build/benchmarks/latest.json`，记录提交、脚本 SHA-256、工具链、debug 构建模式、
OS/CPU/Node、全部原始样本与每场景规范计划的 SHA-256。
CI 的 `planner scale baseline (linux)` job 同样采样3次，并上传 `planner-scale-baseline` artifact。
没有绝对毫秒性能门槛；runner 共享负载与平台差异较大，应在相同环境多轮测量后比较。

当前仅记录数据，不修改算法；若需要定位开销，下一步分别测量解码与规划，而不是根据整体耗时猜测热点。
