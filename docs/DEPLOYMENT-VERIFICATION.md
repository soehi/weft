# 制品锁与独立核验（main 开发版）

正式模块仍为 0.3.1。D1 清单/计划 0.3.0 与旧函数计划 0.2.0 保持；新增部署计划 **0.4.0**、输入锁 **0.1.0**，profile 为 `instance-sync-v1`，规划器协议为 `instance-planner-v1`。这些是协议号，不能视为模块发布号。

## 使用

纯 API `compose.seal(manifest_text, binaries)` 返回 `Deployment { plan_text, lock_text }`；`compose.verify(plan_text, trusted_lock_text, binaries)` 独立返回诊断或 `VerifiedDeployment { canonical, plan }`。字节映射的键是精确逻辑组件 ID，无文件系统依赖。

```sh
moon run src/compose_cli --target js -- seal examples/instances/chain.json --out plan.json --lock inputs.lock.json
moon run src/compose_cli --target js -- verify plan.json --lock inputs.lock.json --inputs examples/instances/chain.json
# Linux only; call limits remain synchronous u32 -> u32
moon run src/runtime_instance --target native -- run-locked plan.json --lock inputs.lock.json --inputs examples/instances/chain.json --component consumer --export run --arg u32:41
```

CLI 核验退出码：0 为有效且规范；2 为有效但非规范；1 为无效输入、摘要或语义失败。核验与执行时 `--inputs` 清单只提供逻辑 ID 到文件的映射，绑定意图来自可信锁，不从该清单重新生成计划。组件文件只读一次，执行使用同一份内存字节。

锁必须从可信审核渠道取得。随计划一起替换锁不构成原审核结果；这些 SHA-256 只保证相对于可信输入的内容一致性，不保证作者身份、签名信任或恶意组件隔离。

## 字节与摘要协议

所有编码使用 UTF-8，无 BOM、尾换行或多余空白。对象按本节列出的字段顺序编码；字符串使用 MoonBit core JSON `stringify(escape_slash=false)`；整数使用非负十进制。算法只能为 `sha256`，摘要必须为 64 位小写十六进制。未知字段、重复 JSON 键、未知版本/profile/规划器协议、负数/小数/越界索引全部拒绝。当前长度和索引上限为 2147483647。

- **旧标识**：0.2.0 的 FNV-1a `plan_hash` 语义不变，不用于制品身份。
- **组件摘要**：SHA-256 覆盖组件文件原始字节，包含所有自定义段；长度是原始字节数。相同接口而行为不同的组件必须获得不同摘要。逻辑 ID 是实例身份：同字节可有不同 ID，不能合并；换目录而 ID/字节不变可迁移。输入映射额外、缺少 ID 都拒绝。
- **锁摘要**：`SHA256(UTF8("weft:input-lock:v1\n" + canonical_lock_json))`。锁本身没有摘要字段。字段依次为 `lock_version, profile, artifacts, bindings`。artifacts 按 ID 的 UTF-8 字典序排列，各项字段为 `id, algorithm, digest, length`；绑定按目标端点、来源端点、种类排序，各项为 `kind, from, to`。端点字段为 `component, port` 和可选 `member`；无 member 先于有 member，instance 先于 function。路径不入锁；输入锁包含完整规范绑定意图，不仅是文件列表。
- **计划摘要**：`SHA256(UTF8("weft:deployment-plan:v1\n" + payload_json))`。payload 字段依次为 `plan_version, profile, planner_version, lock_digest, instances, bindings, operations`，**排除整个 plan_digest 字段**。摘要对象字段为 `algorithm, value`。实例项字段为 `id, algorithm, digest, length, order, imports`；绑定项为 `kind, from, to, from_signature, to_signature`；操作项为 `op, component` 或 `op, binding`。最终 JSON 在 payload 最后追加 `plan_digest`。核验先严格解析，再按上述字段重编码，保留所有声明数组顺序计算摘要。外部对象字段顺序、空白和数字写法不影响有效性，但影响规范性。

类型签名是结构 Merkle SHA-256。每个非 alias 节点的 payload 为 `weft:type-signature:instance-sync-v1:v1\n` 加 `{"tag":TAG,"members":[{"label":LABEL,"digest":CHILD_OR_NULL},...]}`；CHILD 为子节点摘要字符串，无 payload 的边为 JSON null。alias 直接沿用目标摘要，不编码 arena 索引。后序显式栈及局部 memo 保持共享 DAG，不展开成指数级文本。先独立检查支持类型、引用位置及无环性。

tag/边规则：scalar 的 tag 为 `scalar:TYPE` 且无边；record 用 `field:NAME`；tuple 用 `tuple:INDEX`；list 用 `element`；option 用 `some`；result 依次 `ok, err`；variant 用 `case:NAME`；flags/enum 用原名称及空 payload；function 用 `parameter:INDEX` 后接 `result`；instance 按成员名排序，用 `function:NAME / instance:NAME / type:NAME`。record/case/flags/enum 顺序保留，函数参数标签忽略，实例名、arena 编号及 alias/use 来源不入结构摘要；use 引用的合法性仍先检查。resource 等超出 D1 profile 的结构拒绝。

u32 节点标准向量：`8af9aafb8305662baa02403c8bc7d4ec6119d679cf39dd40c12042d25ebe999b`。绑定两端摘要分别核对实际解码类型；提供方允许额外受支持成员，因此不能简单要求两端摘要相等。

## 独立不变量

核验不调用 `compile`、`plan` 或 `seal`。它独立解析锁和计划，核对输入集合、原始字节、锁摘要和计划摘要；比较完整绑定意图；再次解码并检查每个端口及两端类型摘要；核对每个 root import 恰好一个提供方、禁止隐式宿主能力；检查 provider 在 consumer 之前，因而同时排除循环；检查 incoming 索引的范围、目标、唯一性与完整性。

操作必须按实例声明顺序分组，先安装该实例全部导入，再实例化一次；不允许跨消费者交错安装同名全局 linker 导入。任何合法拓扑序、绑定数组排列和组内安装排列均可有效；规范结果额外要求字典序 Kahn 顺序、上述绑定排序、升序 incoming/安装索引及精确编码。独立核验器重建规范表示仅用于 `canonical` 判定，语义有效性由前述不变量决定。

原生 `run-locked` 在开执行会话前核验，随后在首个实例化前验证全部 root 输入。D1 的直接源码 `run` 继续从清单编译；通用旧 `weft run` 仍不支持。Linux CI `43371786122` 的原生 job 已通过19测试与11项锁定部署CLI检查，真实guest结果为84/102/42；完整CI验收进度见ROADMAP。

浏览器先执行`node scripts/build-demo.mjs`及`python scripts/serve-demo.py`，打开`http://127.0.0.1:8000/deployment.html`。
Worker调用同一纯API，分别导出计划及输入锁；实际Chromium检查两份下载与CLI字节一致，并再次通过CLI核验。完整接口/缺成员与另一提供方示例均为本地资源，用户选择文件不上传。
