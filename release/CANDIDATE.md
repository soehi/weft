# 0.3.0 候选验收记录

状态：M4材料与打包对齐中；尚未创建Mooncakes版本或正式GitHub Release。
功能证据基线：`61f9488`，最终候选为本记录与材料提交后、通过完整CI的提交。
最终源码SHA由CLI制品BUILD.json和本地 `_build/release/candidate.json` 记录，避免文档自引用提交SHA。

| 输入 | 固定记录 |
|---|---|
| 模块 / CLI | soehi/weft 0.3.0 / weft 0.3.0 |
| 计划格式 | 0.2.0；读取精确0.1.0/0.2.0清单 |
| moon / moonrun | 0.1.20261104 |
| moonc / core | 0.10.20+65efd5b93 |
| 工具链归档 | toolchain.lock.json 的SHA-256锁定；可变URL及缓存限制见README.md |
| 依赖 | dependencies.lock.json，17个解析模块的精确版本 |
| 功能门禁 | 当前139独立测试在三个后端重复；各33项规划CLI进程检查 |
| 实验执行 | 独立Linux命令，8项测试及30项进程检查；不进入规划CLI包 |
| 性能 | 18个规模场景，单独计时，不计入功能测试数 |

2026-11-09 `moon view soehi/weft@0.3.0 --json` 返回404。保留0.3.0作为候选。
隔离MOON_HOME未登录，用户原有MoonBit环境可查询到soehi账号；固定工具链已在用户现有登录下执行发布预检：解包校验通过，服务器返回202 Accepted；临时凭证链接已清理，尚未实际发布。

## 打包范围

moon.mod声明README与仓库；根LICENSE为Apache-2.0。`.moonignore`复制必要的构建忽略规则，
额外排除仓库性能原始报告和申报书，保留源码、生成接口、文档、示例、schema和发布说明。
包过滤规则及内容以 `moon package --list` 和 `python scripts/check-package.py` 实际输出为准。
第三方模块源码不嵌入Mooncakes包，按依赖声明解析；来源与许可证核对见THIRD-PARTY.md。

## 仍待完成

- 最终候选提交的完整CI及Windows/Linux CLI包重建。
- 注册表预检、发布后查询以及无本地moon.work的消费者三后端复验。
- 对应tag/Release、演示脚本及从稳定下载入口的干净目录复验。

未完成项按ROADMAP第24节推进，不用本地打包成功替代注册表或正式Release成功。
