# 5–10分钟验收演示

先按README配置固定工具链并运行moon update。正式预构建入口为 https://github.com/soehi/weft/releases/tag/v0.3.1 ，已完成双平台下载首次使用验证。
演示操作均在仓库根目录；规划与浏览器不依赖Linux执行器。

1. **版本与安装（约1分钟）**：运行 `moon run src/cli --target js -- --version`，应输出
   `weft 0.3.1 (plan 0.2.0)`。预构建包则运行 `node weft.mjs --version` 或原生 weft(.exe)。
2. **成功计划（约1分钟）**：运行 `moon run src/cli --target js -- plan examples/chain.json --out plan.json`。
   结果按 reader/filter/sink 实例化，hash为 `1a3640bcc99318d5`，完整字节等于docs/fixtures/plan-v0.2.0.json。
3. **错误诊断（约1分钟）**：分别对examples/cycle.json和type-mismatch.json运行plan。
   两条命令都应失败（退出1），分别说明依赖环、source.read/sink.in类型不匹配，不产生成功计划。
4. **跨后端核对（约1分钟，首次构建另计）**：对同一chain.json用native/wasm-gc/js分别 `--out plan-<target>.json`。
   三份文件字节相同；自动核对可运行 `node scripts/check-backends.mjs`，该完整门禁耗时另计。
5. **浏览器本地文件（约2分钟）**：运行 `node scripts/build-demo.mjs`、`python scripts/serve-demo.py`，
   打开本地8000端口，演示成功链、类型错误，下载规范计划；下载与CLI字节相同。
   自选本地清单和组件后检查，文件在浏览器内处理，不上传到服务器。修改输入后旧下载立即失效。
6. **可选Linux数值链（约1分钟）**：运行
   `moon run src/runtime_native --target native -- run examples/execution/chain.json --component consumer --export run --arg u32:41`。
   应返回84；source路径换为alternate.wasm返回86，删除wire应失败。Windows本轮不演示native执行。

证据：功能门禁见候选提交CI；格式黄金样本在docs/fixtures；浏览器用scripts/test-browser.py复验；
独立执行用scripts/test-native-cli.py复验。性能数据在docs/PERFORMANCE.md，属于另一个测量口径，
不将debug性能样本计为功能测试数量。

## 入口抽检（2026-11-10）

- 版本：正式0.3.1，计划0.2.0；源码tag `v0.3.1`，`08306e9a0ed4ce40984461ac2502c38caa863292`。
- Windows x86_64本机从[正式Release](https://github.com/soehi/weft/releases/tag/v0.3.1)重新匿名下载zip及`.zip.sha256`。
  `python scripts/test-release.py <zip>`通过：压缩包及逐文件SHA-256、带空格干净目录中的native/Node版本、黄金计划与错误退出。
  `python scripts/check-release-source.py <zip> 08306e9a0ed4ce40984461ac2502c38caa863292 0.3.1`通过。
- 同日本机在默认安装和隔离安装中运行`node scripts/test-registry-consumer.mjs 0.3.1`；
  两者实际指纹均为0.10.20+65efd5b93，不计作两个版本。每次均新建无workspace/path override的消费者，
  三后端合法链字节及缺字节、类型错误诊断通过。精确范围见[支持矩阵](../docs/TOOLCHAIN-COMPAT.md)。
- Linux本轮未在本机重复运行二进制；沿用[正式发布流程](https://github.com/soehi/weft/actions/runs/42614477838)中
  Ubuntu 24.04双入口下载运行及源码核对的成功证据。浏览器与独立执行仍以对应完整CI记录为准。
- README到公开申报书、Release、注册表消费者及本演示的本地链接、源码路径均已核对；公开申报书没有联系方式。
  本轮为文档与分发入口维护，没有修改代码或替换原制品。
