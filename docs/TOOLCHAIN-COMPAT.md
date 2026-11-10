# 0.10.19 源码兼容同步（2026-11-10）

依据 [官方0.10.19更新说明](https://www.moonbitlang.com/updates/2026/11/05/index)，
将源码中的Int/UInt别名同步为明确宽度的Int32/UInt32，并采用格式化器规范化包与源码写法。
Json已显式导入core/json，既有moon.mod/moon.pkg已是当前格式。
公有生成接口与计划格式没有改变，发布版本0.3.1及已发布制品不覆盖。

## 两个已核对的构建

| 用途 | moonc/core | moon/moonrun |
|---|---|---|
| 兼容同步时的本机环境（历史指纹） | 0.10.19+97801ee1b，编译器日期2026-10-30 | 0.1.20261029 |
| 仓库发布与CI锁 | 0.10.20+65efd5b93 | 0.1.20261104 |

不能只根据0.10.19这个版本短号判断新语法是否可用。本机10月30日构建不识别11月5日更新说明中的
#derive属性；直接转换会丢失派生实现并导致编译失败。因此Location、Diagnostic、ValTy三处暂保留
derive(...)，两个环境都可编译。锁定工具链会对此给出已知弃用警告，保留本机兼容时不能直接将这三处转换为属性。
这也是当前没有以0.10.20的全量格式化产物作为唯一格式门禁的原因。

## 验证范围

- 本机0.10.19：三后端各139个测试、各35项CLI检查、独立workspace消费者、格式黄金字节通过；浏览器bridge五例及CLI字节对照通过。
- 0.10.20：本机三后端各139测试、35项CLI、独立消费者、bridge五例及真实Chromium回归通过。
- 提交 `70ecdf3` 的 [远程CI](https://github.com/soehi/weft/actions/runs/42792069139) 九项全部成功，包含Linux真实执行、浏览器及Windows/Linux制品验证。
- 版本锁仍用于发布输入校验；在0.10.19环境运行check-release-inputs.py会拒绝该版本，这是发布锁校验的预期行为，不等于源码不兼容。

复现兼容回归：将目标工具链的bin置于PATH最前并设置对应MOON_HOME，运行
`node scripts/check-backends.mjs`、`node scripts/build-demo.mjs`、`node scripts/test-demo.mjs`。
切换环境后生成接口最终以仓库锁定工具链的moon info为准。
0.10.19证据来自Windows本机；远程CI继续使用锁定0.10.20，不宣称已增加旧工具链的远程Linux验证。

## 支持矩阵与发布输入

| 输入与平台 | 精确编译器 | 源码可构建 | 回归证据 | 发布锁接受 |
|---|---|---|---|---|
| main维护源码，Windows x86_64 | 0.10.19+97801ee1b；moon/moonrun 0.1.20261029 | 是 | 三后端139测试/35 CLI、workspace消费者、bridge五例；未单独验证此构建的真实Chromium | 否，预期拒绝 |
| main维护源码，Windows x86_64 | 0.10.20+65efd5b93；moon/moonrun 0.1.20261104 | 是 | 同等回归及真实Chromium | 是，仍须依赖清单等全部输入匹配 |
| main维护源码，Linux x86_64（Ubuntu 24.04） | 同上0.10.20构建 | 是 | [791853f完整CI九项通过](https://github.com/soehi/weft/actions/runs/42802691079)，含真实执行 | 是，仍须全部输入匹配 |
| 正式注册表soehi/weft@0.3.1，Windows x86_64 | 上述0.10.20构建 | 是（API消费者） | 2026-11-10全新目录安装，三后端合法计划黄金字节、缺字节及类型错误诊断通过；未据此验证0.10.19的正式包 | 是，仍须全部输入匹配 |
| 正式v0.3.1 Windows/Linux预构建规划CLI | 使用锁定0.10.20构建；使用者无需MoonBit | 不适用 | [发布流程五项检查](https://github.com/soehi/weft/actions/runs/42614477838)，双平台下载与源码SHA；Windows本轮再抽检见[演示记录](../release/DEMO.md) | 原制品构建输入已验收 |
| 0.10.16、其他0.10.19构建、macOS或其他未列平台 | 未验证 | 未验证 | 编译器最低参赛要求不等于已测试的支持范围 | 未接受 |

本轮M8复核时，本机默认安装也已为0.10.20+65efd5b93，与隔离发布锁指纹相同。
默认目录和隔离目录的注册表复验都是0.10.20，不能算作两种编译器的证据；
上文0.10.19的main源码回归沿用第29节记录，不宣称本轮重新取得了旧工具链或完成正式包的0.10.19消费者验证。

## 隔离复验入口

锁定工具链按 [构建说明](../release/README.md) 安装到 `_build/toolchains/pinned`，不覆盖已有安装。
以下在仓库根目录的PowerShell运行，切换仅影响当前进程，结束后恢复环境：

```powershell
# 默认检验隔离安装的发布锁；检验既有旧构建时，将此行改为其MOON_HOME目录。
$compatMoon = Join-Path (Get-Location) '_build/toolchains/pinned'
$priorMoon = $env:MOON_HOME
$priorPath = $env:PATH
try {
  $env:MOON_HOME = $compatMoon
  $env:PATH = (Join-Path $compatMoon 'bin') + ';' + $priorPath
  moon version --all
  if ($LASTEXITCODE -ne 0) { throw 'toolchain unavailable' }
  # 先核对输出指纹与上表一致，不能仅凭0.10.19短号推定兼容。
  node scripts/check-backends.mjs
  if ($LASTEXITCODE -ne 0) { throw 'backend checks failed' }
  node scripts/build-demo.mjs
  if ($LASTEXITCODE -ne 0) { throw 'demo build failed' }
  node scripts/test-demo.mjs
  if ($LASTEXITCODE -ne 0) { throw 'bridge checks failed' }
  node scripts/test-registry-consumer.mjs 0.3.1
  if ($LASTEXITCODE -ne 0) { throw 'registry checks failed' }
} finally {
  $env:MOON_HOME = $priorMoon
  $env:PATH = $priorPath
}
```

Linux使用同一锁定安装目录，在子shell中设置`MOON_HOME`和`PATH`后执行相同Node命令；
完整浏览器复验另见 [demo验证](../demo/README.md)。本轮没有取得可校验的旧版Linux归档，
不添加追随latest的“0.10.19 CI”，也不下载未核对的旧工具链替换现有安装。

## 0.3.2补丁决策（2026-11-10）

**暂不发布0.3.2，已验证环境继续使用正式0.3.1。** 已发布0.3.1在Windows锁定0.10.20下的注册表API消费者通过；
正式Windows预构建包再次下载、校验、运行通过。main新增的是Int32/UInt32显式写法与格式维护，
公有生成接口、计划格式与黄金字节未变；尚无需要用户通过注册表获取的修复或分发需求。
这些源码改动未包含在原0.3.1包或Release中，维护源码不会覆盖原tag、包或资产。

若出现可复现的安装/编译失败，或明确需要分发main兼容改动，再启用ROADMAP M8.4：
独立0.3.2候选、完整门禁、包审核、注册表消费者、双平台Release下载及源码SHA核对，全部通过后交付。
