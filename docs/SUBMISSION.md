# weft 项目申报书

## 基本信息

- 项目名称：weft——基于 MoonBit 的跨后端 WebAssembly Component 部署计划编译器
- 参赛者：soehi
- GitHub 仓库：[https://github.com/soehi/weft](https://github.com/soehi/weft)
- 项目方向：系统工具 / WebAssembly 组件工具链 / 跨平台基础设施
- 主要实现语言：MoonBit
- 已验证编译器版本：moonc v0.10.20+65efd5b93，满足不低于 v0.10.16 的要求
- 开源许可证：Apache-2.0
- 是否为移植项目：否；本项目实现部署规划逻辑，组件解码、WAC 解析验证和 canonical ABI 展开复用已有 MoonBit 开源库

## 项目简介

weft 是一个用 MoonBit 实现的 WebAssembly Component 部署计划编译器。开发者提供一份描述组件、文件路径及端口连线的 JSON 清单，以及对应的组件二进制，weft 在执行前解析组件接口、检查连接、检测依赖环并计算实例化顺序，最终生成包含连接关系、资源策略元数据和计划标识的 JSON 计划。

项目的核心目标是让同一份规划逻辑能够用于本机命令行、CI 检查及浏览器本地规划。同一份输入在 native、wasm-gc、js 三个后端生成逐字节一致的计划，从而为不同宿主提供统一的检查结果和可复现的部署描述。

“weft”意为织造中的纬线，对应清单中的 `wires`：项目把组件之间的连接关系组织成一份有序、可检查的计划。当前核心交付物是规划库、CLI 和可复现示例；原生执行适配器属于实验代码，不纳入已经完成的核心功能声明。

## 项目目标与真实需求

组件组合涉及多个文件和多条依赖关系。开发者需要在启动运行时之前确认：组件能否解码、端口是否存在、连线签名是否匹配、组件之间是否形成依赖环，以及应按什么顺序实例化。依靠人工阅读清单和分别检查二进制，难以稳定覆盖这些问题。

同一份部署描述还可能在本地和 CI 中重复检查。若排序、序列化和错误处理随宿主环境变化，计划文件便难以比较、回归和归档。因此，本项目将“执行前检查”和“确定性计划生成”作为主要任务，面向以下使用场景：

1. **本地开发**：在组件启动前发现错误，诊断指出具体组件、端口或依赖环。
2. **持续集成**：对清单及组件变更运行相同检查，比较计划输出，保留可复现结果。
3. **工具集成**：通过 MoonBit 包接口调用规划逻辑，由宿主提供输入字节并处理输出。
4. **浏览器检查**：已通过 js bridge 调用同一 api.compile，支持本地组件、图、诊断和规范计划下载。

项目处理的是通用 WebAssembly Component 组合问题，使用者无需将组件改写为 MoonBit，也不依赖特定业务框架。

## 核心功能范围

### 已实现功能

| 模块 | 功能 |
|---|---|
| `manifest` | 解析组件清单，校验字段形状、重复组件、端口引用和资源数值，返回具名错误 |
| `ir` | 从真实组件二进制提取 imports、exports、函数签名及类型表，作为规划器的统一输入 |
| `plan` | 构建依赖图、检测自环和多节点环、执行确定性拓扑排序，严格检查同步值类型结构与绑定覆盖，canonical ABI 展开作补充 |
| `plan` 输出 | 生成固定字段顺序的计划 JSON，包含实例化顺序、wire 索引、两端签名、资源策略和 `plan_hash` |
| `wac_adapter` | 在当前支持的 WAC 子集内进行 WAC 与清单转换；WAC 输入经过上游验证，不支持的组合结构明确报错 |
| `exec_plan` | 将计划展开为可测试的实例化、绑定等操作描述；该描述本身不代表实际执行完成 |
| `cli` | 提供 `plan`、`emit-wac`、`convert`，支持输出文件、版本化依赖参数及非法参数诊断 |
| 开发与验证工具 | 从 WAT 生成示例组件，进行三后端测试、真实 CLI 检查及计划文件逐字节比较 |

清单中的组件文件路径相对于清单目录解析。`convert` 保留显式依赖版本，并将组件路径输出为规范化的绝对路径，使转换后的文件在本机换目录保存后仍可直接交给 `plan`。跨机器路径迁移不属于该机制的保证范围。

### 当前能力边界

- 当前版本对明确支持的同步标量和复合值类型做严格结构比较，明确拒绝 resource/async 等未支持语义；不宣称完整组件 subtyping 或资源身份兼容性证明。
- `resources` 是计划中的策略元数据，不代表运行时已执行内存或计算配额限制。
- `plan_hash` 使用 FNV-1a 64 标识规范计划体，不包含组件二进制摘要，不作为安全或制品完整性校验。
- `run` 明确返回未支持并以非零状态退出。通用规划 CLI 未接入执行；独立 Linux 原生命令已验证输入41，经源+1、消费者import调用后×2返回84，断线失败、改接返回86。外部WAC组合后执行未验证。
- 项目不包含分布式调度、集群管理、故障恢复、热更新，也不自行实现通用 WebAssembly 运行时。

## 技术方案与项目特点

### 1. 纯规划核心与宿主 I/O 分离

规划层接收已经读取的清单文本及组件信息，文件系统操作由 CLI 等宿主入口承担。组件解码集中在 `ir`，图算法和计划输出集中在 `plan`，WAC 转换集中在 `wac_adapter`。实验性运行时依赖单独保留在 native-only 包中，避免进入其他后端的规划构建路径。

这种分层使规划逻辑能够独立测试和复用，浏览器工作台复用同一 api.compile 计算核心。

### 2. 明确定义确定性规则

组件和连接在输出前归一化排序；拓扑排序对同时可用的组件采用名称字典序决策；JSON 字段顺序和数字表示显式确定。项目通过固定的黄金输出和真实 CLI 文件比较验证结果，而不只依赖算法层面的推断。

确定性使计划文件适合版本比较与回归验证。其承诺限定于格式约定下的相同输入，不将不同路径文本、不同组件内容等输入差异自动视为等价。

### 3. 复用生态能力，补充部署规划环节

组件二进制模型与 canonical ABI 展开复用 `Milky2018/wasm_component`，WAC 解析和语义验证复用 `moonrockz/wac`。本项目的主要实现集中于清单模型、接口整理、依赖检查、排序、计划序列化及 CLI 集成。

项目特点是将这些能力组合成可独立调用、可跨后端验证的规划流程，不以重写上游解析器、运行时或宣称“首个”“唯一”作为创新依据。

## 实测结果与最小使用样例

以下记录以候选验收基线 `61f9488`（模块/CLI 0.3.0、计划格式0.2.0）为依据，
[该提交CI成功](https://github.com/soehi/weft/actions/runs/42582669079)。材料与元数据对齐后须以最终候选提交重跑门禁，
该源码SHA、打包清单及发布状态记于 release/CANDIDATE.md，不将尚未完成的注册表或Release工作计作已发布成果。

| 验证项目 | 结果 |
|---|---|
| 核心回归 | 139个独立测试，在native、wasm-gc、js各运行一次并通过；不是417个独立用例 |
| 真实规划CLI | 每后端33项进程检查，包括错误退出、带空格/跨目录路径与转换往返 |
| 计划格式 | 三后端规范UTF-8文件逐字节一致，保留0.1.0/0.2.0黄金样本，输出计划0.2.0 |
| 内存API | api.compile接收清单和组件名字节映射，结构化诊断；独立本地workspace消费者三后端通过 |
| 浏览器 | 实际Chromium验证五类示例、本地映射、诊断和下载与CLI字节相同 |
| Linux独立执行 | 8项执行器/探针测试，30项实际命令检查；正常/断线/改接、trap、资源请求拒绝 |
| 门禁 | 9个CI job涵盖功能、浏览器、Linux执行、制品、模式及性能；故意失败的Bash/PowerShell入口保留原始诊断并失败 |
| 性能 | 100/1000组件链、扇出、扇入，3后端共18场景；样本不作为功能测试数量 |

性能采用debug构建，分别记录新进程CLI耗时和预热内存阶段。拓扑排序、绑定覆盖、宽端口表三项优化均保留
计划字节及错误行为。Windows千组件扇出CLI中位数约344.5→232.5ms，随后千组件扇入约330.2→223.0ms；
这些是具体环境的前后测量，不代表所有工作负载或所有平台的加速保证，方法及原始证据见 docs/PERFORMANCE.md。

在已安装 MoonBit 工具链及 native 编译所需平台工具的环境中，可按以下步骤运行规划示例。完整门禁还需要 Node.js；Windows 可使用 PowerShell 入口。

```bash
git clone https://github.com/soehi/weft.git
cd weft
# 先按README设置固定工具链的MOON_HOME/PATH，再解析依赖
moon update

# 生成三个真实组件二进制和示例清单
moon run src/tools/make_fixtures --target native -- examples

# 按清单生成计划
moon run src/cli --target native -- plan examples/chain.json

# 使用其他后端处理同一输入
moon run src/cli --target wasm-gc -- plan examples/chain.json
moon run src/cli --target js -- plan examples/chain.json

# 运行三后端测试、CLI 检查及输出比较
node scripts/check-backends.mjs
```

示例清单连接 `reader.read → filter.in`、`filter.out → sink.in`，规划结果的实例化顺序为 `reader`、`filter`、`sink`，当前0.2.0计划的 `plan_hash` 为 `1a3640bcc99318d5`。示例证明的是从组件文件到部署计划的完整路径，不声称已经运行这条组件链。

## 验收交付计划与当前发布状态

M1–M3、E1及三轮性能优化已完成，接下来按 docs/ROADMAP.md 第24节推进：

| 阶段 | 交付内容 | 当前状态 |
|---|---|---|
| M4 候选冻结 | 最终源码SHA、材料、README、发布元数据、打包与许可证核对 | 候选d6ebb0b九项CI成功；最终tag工作流继续核对源码SHA |
| M5 Mooncakes闭环 | soehi/weft@0.3.0注册表发布，无本地workspace的独立消费者三后端复验 | 0.3.0已发布，独立注册表消费者三后端合法计划和两项错误诊断通过 |
| M6 正式制品与复演 | tag/GitHub Release、SHA-256、5–10分钟演示、干净目录下载抽检 | 尚未完成；当前Actions artifacts只是过程制品 |

2026-11-09发布前精确版本查询返回404，随后从候选d6ebb0b实际发布0.3.0，服务器返回200 OK，
moon view可查询目标版本。注册表独立消费者不引用本地moon.work/path override，三后端计划与黄金文件一致，
缺组件字节及类型错误诊断通过。包checksum与发布源码记于release/CANDIDATE.md。
M6的正式tag/Release及下载抽检正在推进，最终制品源码SHA以v0.3.0 tag及包内BUILD.json为准，
原注册表包保持不可变。CI安装Action问题已在早期修复，不再作为当前阻塞；发布阶段保持格式与公共API稳定。

## 移植或参考说明

本项目不是将某个现有项目整体翻译为 MoonBit。规划器与清单、图算法、输出规则及命令行集成由本项目组织实现；通用组件模型、解析及验证能力通过包依赖复用。直接依赖及用途如下，许可证信息依据所用版本的模块声明整理。

| 依赖项目 | 来源链接 | 使用版本 | 声明许可证 | 用途 |
|---|---|---|---|---|
| `Milky2018/wasm_component` | [Milky2018/wasmoon](https://github.com/Milky2018/wasmoon) | 0.18.0 | Apache-2.0 | 组件模型、canonical ABI 展开、WAT 示例汇编 |
| `Milky2018/wasm_core` | [Milky2018/wasmoon](https://github.com/Milky2018/wasmoon) | 0.18.0 | Apache-2.0 | Core Wasm 类型模型 |
| `moonrockz/wac` | [moonrockz/wasm-devkit](https://github.com/moonrockz/wasm-devkit) | 0.3.0 | Apache-2.0 | WAC 解析、验证与组件语义解码 |
| `moonrockz/wit` | [moonrockz/wasm-devkit](https://github.com/moonrockz/wasm-devkit) | 0.3.0 | Apache-2.0 | WIT 类型工具链依赖 |
| `moonbitlang/x` | [moonbitlang/x](https://github.com/moonbitlang/x) | 0.5.5 | Apache-2.0 | CLI 所需文件系统与系统接口 |
| `Milky2018/wasmoon` | [Milky2018/wasmoon](https://github.com/Milky2018/wasmoon) | 0.18.0 | Apache-2.0 | 实验性 native 执行适配器依赖，仅用于独立Linux实验执行，通用规划命令不执行组件 |

本项目根目录提供 Apache-2.0 `LICENSE`，依赖目录不纳入仓库源代码。规划CLI制品已带第三方说明；Mooncakes源码包与正式Release仍须按实际内容核对许可证、版权及NOTICE保留要求。项目不将上游实现归为本项目原创成果，也不将上游运行时的存在等同于本项目已经完成执行验证。

## 预期生态价值

weft 提供一套可在多个 MoonBit 后端运行的组件部署检查与计划生成实践：一方面，为组件开发者提供启动前的错误发现和稳定计划输出；另一方面，为 MoonBit 生态补充可组合的清单、接口、图算法与确定性序列化能力。

后续工具可复用同一规划核心构建终端命令、CI 检查或浏览器界面。项目的价值以公开代码、独立消费者、可复现示例和自动化验证体现，具体能力以测试覆盖和已发布版本为准。
