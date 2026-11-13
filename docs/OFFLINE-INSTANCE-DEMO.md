# 离线实例组合复演（main 开发版）

准备好已锁定的MoonBit、依赖、Node和Linux C工具链后，以下规划、核验与调用都不访问网络。Windows可生成与核验，真实执行采用Linux。正式发布仍为0.3.1；这些源码命令尚未发布。

## 审核并运行

`examples/instances/reviewed.json`含两个兼容提供方source/alternate及consumer，初始绑定source。两份提供方都在锁内，只有一个被消费。

```sh
moon run src/compose_cli --target js -- seal examples/instances/reviewed.json --out plan.json --lock inputs.lock.json
moon run src/compose_cli --target js -- verify plan.json --lock inputs.lock.json --inputs examples/instances/reviewed.json
moon run src/runtime_instance --target native -- run-locked plan.json --lock inputs.lock.json --inputs examples/instances/reviewed.json --component consumer --export run --arg u32:41
```

结果为84。consumer在guest内依次调用两个导入函数：`inc(41)`得到42，`twice(42)`得到84；宿主只传参和读取结果。

浏览器可先运行`node scripts/build-demo.mjs`及`python scripts/serve-demo.py`，打开`http://127.0.0.1:8000/deployment.html`。
选中reviewed.json与三个组件文件，审核表格中的逻辑ID、顺序与SHA，再下载plan.json和inputs.lock.json。
两份下载原样来自纯API，真实Chromium测试已证明它们与CLI字节一致，并再次通过CLI核验。将审核过的锁、计划和组件复制到Linux；路径可改，逻辑ID和原始字节必须一致。

## 三种拒绝与重新审核

1. **替换内容**：保留原锁与计划，将清单中source的path改为alternate.wasm。接口仍兼容，但核验报`BINARY_DIGEST_MISMATCH`，不会实例化。恢复清单。
2. **改接兼容提供方**：将外部计划中绑定的from.component由source改成alternate。未重新计算摘要时先报`PLAN_DIGEST_MISMATCH`；即使攻击者重新计算计划摘要，也报`BINDING_INTENT_MISMATCH`，因为可信锁固定了原审核关系。自动化用例明确重新计算摘要后断言此错误。
3. **缺成员**：把待审核清单的提供方path改为missing.wasm再尝试seal，报`MISSING_MEMBER`，路径包含consumer/ops/function:twice；不生成新的计划或锁。若仅替换已锁二进制，则在更早的字节摘要检查被拒绝。

合法切换时，在清单中将绑定来源改为alternate，重新检查并生成新的计划/锁，再经审核后运行。此时`inc(41)`得到51，guest继续调用`twice(51)`，结果为102。不能沿用原锁。

一次复验上述行为（Linux）：

```sh
python scripts/test-native-deployment.py
```

该脚本还检查显式函数成员绑定42、有效非规范计划可执行，以及重新计算摘要后的签名、拓扑顺序、incoming和操作篡改均拒绝。
浏览器不会执行组件；原生只开放同步单u32参数、单u32结果。record、variant等复合值有静态检查/差分证据，不据此声明可原生调用。

## 生成、变异与差分证据

```sh
moon test src/compose_types src/compose_plan --target js
python scripts/install-external-wac.py
python scripts/test-composition-differential.py
# 单独重放一个真实二进制种子
python scripts/test-composition-differential.py --seed 7
```

安装外部WAC是预备步骤，需要网络；安装完成并验证固定哈希后，差分脚本本身离线运行。

- 类型参考循环固定2000种子，每种4个变体，最多11节点/图，参考深度32；独立结构渲染器与生产兼容检查对照。
- DAG参考循环另用2000种子，每图3–6节点，至多6!个完整排列；用穷举参考核对规范拓扑，并独立回放安装/实例化，检查删除、重复和自环。
- 外部差分是额外27个真实二进制DAG，每图3–5组件，覆盖scalar/list/option/record/tuple/flags/enum/variant/result九类值类型。每种正常、错误类型、缺成员三例，并实际验证weft发射的WAC。该共同子集为只含命名值类型的接口；函数执行另由上述真实guest覆盖，不将这27例当作全部组件模型证明。
- 每份部署计划施加21类字段变异，重新计算自校验摘要后，与独立Python参考核验流程对照；参考的类型事实来自有限生成语法，不调用生产解码/shape/compile/verify。另核对输入/绑定重排的规范字节，以及合法绑定数组重排的非规范有效性。

普通测试数量与生成循环的比较次数分开记录；每个生成循环只算一个测试。CI portable job有15分钟期限，外部差分步骤5分钟，每个外部/CLI命令30秒、Node堆256MiB。图规模、种子和参考深度硬编码为上限；不输入无界大图。原生/wasm-gc内存由小图结构及runner容量约束，不将Node堆预算描述成整进程物理内存上限。

差分报告写入`_build/d3/report.json`并由CI上传。失败时保留种子、完整WAT、组件字节、清单、WAC、工具版本/哈希、原始stdout/stderr。
若weft与外部工具的接受结论不同，自动贪心删除无关sink/孤立节点并重试，保存`reduced.json/reduced.wac`；这只保证在该删除操作下不能继续缩减，不声称全局最小。缩减器有独立固定例检查。
若是计划字段参考结论不同，保存当时的sealed.json、lock.json与输入，可先恢复基线再逐项恢复被变异字段；变异本身只有一个字段/操作，故不用把多个故障混在一个样本中。

这些是可复现的检查与差分证据，不是形式化证明。摘要相对于可信审核输入保证内容一致性，不提供作者认证或组件隔离。
