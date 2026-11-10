# v0.3.1 构建与首次使用验证

模块/CLI 版本为 0.3.1，计划格式仍为 0.2.0。CI 生成 Windows x86_64 与 Linux x86_64 CLI 验证包，
每包附同一版本 Node CLI；不包含 wasmoon 执行适配器，也不会将 run 开放为已验证能力。
正式下载入口：[v0.3.1 Release](https://github.com/soehi/weft/releases/tag/v0.3.1)。Mooncakes 0.3.1已发布并经独立消费者复验；Actions artifacts仍作为过程证据保留。

上述正式制品及注册表包来自 tag `v0.3.1`（`08306e9`）。复建该版本先运行
`git checkout v0.3.1`；main 包含发布后的整数语法兼容维护，不能当作原制品源码。
精确环境、复验命令及暂不发布0.3.2的依据见 [工具链兼容记录](../docs/TOOLCHAIN-COMPAT.md)。

## 固定输入

- toolchain.lock.json 固定官方 Linux/Windows 二进制及 core 归档的 SHA-256、moon/moonc/moonrun/core 版本。
  当前 moon 为 0.1.20261104，moonc/core 为 0.10.20+65efd5b93。
- 官方安装脚本说明支持历史版本路径，但本轮探测的候选归档地址返回 403。因此下载 URL 仍为官方 latest，
  **接受内容由固定哈希决定**：一旦上游更新，安装必须失败，不自动接受新字节。
  这不是不可变下载托管；应保留已校验的本地缓存，可用 --cache 指定缓存目录。没有旧缓存且上游撤回归档时，
  必须重新验证新的工具链并显式更新锁文件。工具链归档不随项目制品再分发。
- dependencies.lock.json 记录 17 个已解析模块的精确版本；检查器在解析后对照，出现漂移即失败。
  这是版本清单检查，不额外承诺第三方注册表源码的内容哈希锁定。
- CI 固定 Ubuntu 24.04 / Windows 2025 runner 系列；不承诺这些镜像内部的 C 编译器永远不变。

隔离安装，不覆盖已有 ~/.moon：

```powershell
python scripts/install-toolchain.py --destination _build/toolchains/pinned
$env:MOON_HOME = Join-Path (Get-Location) '_build/toolchains/pinned'
$env:PATH = (Join-Path $env:MOON_HOME 'bin') + ';' + $env:PATH
moon update
moon check src/api src/cli --target js
python scripts/check-release-inputs.py
```

Linux 使用同一 Python 安装命令，随后 export MOON_HOME 为该目录并将其 bin 加入 PATH。
安装器仅支持锁文件内的 Linux/Windows x86_64；首次安装需要 Python 3.12+、网络，Windows native 构建另需 MSVC。
如果初次安装中断而目录不完整，请选另一个空目录，脚本不会递归删除已有目录。

## 打包与校验

在干净的已提交源码上执行：

```bash
python scripts/build-release.py
python scripts/test-release.py _build/release/weft-0.3.1-windows-x86_64.zip
# Linux 的文件名为 weft-0.3.1-linux-x86_64.zip
```

包内包含原生 weft(.exe)、可用 `node weft.mjs` 运行的 CLI、示例、许可证与第三方说明、
BUILD.json、工具链/依赖记录，以及逐文件 SHA256SUMS；包外 .zip.sha256 校验整个压缩包。
BUILD.json 记录源码提交、项目/计划版本、平台和固定输入。
SHA-256 用于核对传输文件，不是签名；本轮不宣称跨机器 native 二进制逐位可重现。

CI 使用 artifacts 名称 weft-cli-ubuntu-24.04 / weft-cli-windows-2025。下载 Actions artifact 后，
再解开里面的 weft-*.zip，按 .zip.sha256 和 SHA256SUMS 校验。Linux 解包后需要 `chmod +x weft`。

## 从新目录首次运行

进入解包目录（不需要 MoonBit 或 .mooncakes；Node CLI 需要已安装 Node，当前验证使用 Node 24 系列）：

```bash
./weft --version
./weft plan examples/chain.json --out plan.json
node weft.mjs --version
node weft.mjs plan examples/chain.json --out plan-node.json
```

Windows 将 ./weft 替换为 ./weft.exe。输出应为 weft 0.3.1 (plan 0.2.0)，两份计划均等于包内 golden.json。
Linux native 包在 Ubuntu 24.04 同系列环境验证，仍依赖系统 ABI/标准共享库，不是所有发行版通用的静态二进制。

测试脚本会在带空格的全新临时目录校验/解包制品，从包目录之外同时调用原生与 Node CLI，
核对版本、黄金计划和错误退出码。[独立注册表消费者](../examples/registry-consumer/README.md)验证已发布0.3.1；
examples/consumer 则通过本地 workspace 验证维护源码，两种验证分别记录。
