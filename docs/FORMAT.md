# v0.2.0 格式与迁移契约

模块的开发版本为 `0.3.0`，规范计划版本为 `0.2.0`。本仓库提交不等于 Mooncakes 发布或 GitHub Release。
本契约固定输入清单、规范计划文件与 hash；执行器仍未开放。

## 版本与 Schema

- 新清单建议显式写 `version: "0.2.0"`；省略时默认 `0.2.0`。
- 为迁移读取历史 `0.1.0` 清单，但使用当前 M2 的类型、绑定与 WAC 规则。
  仅接受这两个完整字符串，拒绝其他 patch、前缀、预发布和空白变体。
- 计划固定输出 `plan_version: "0.2.0"`；WAC 转换输出 `version: "0.2.0"`。
- [清单 Schema](../schemas/manifest-v0.2.0.schema.json)、[当前计划 Schema](../schemas/plan-v0.2.0.schema.json)
  使用 JSON Schema Draft 2020-12。另保留 [历史计划 Schema](../schemas/plan-v0.1.0.schema.json)。
- 清单与计划 Schema 均关闭额外字段。Schema 描述数据形状；名称唯一性、引用、拓扑、类型与完整绑定
  由 MoonBit 规划器检查。当前没有读取任意计划 JSON 的执行入口。

## 清单文本

输入为无 BOM 的合法 UTF-8 JSON。CLI 严格解码；JSON 字符串不得含孤立 surrogate。
拒绝重复键（包括转义后相同的键），最大 JSON 嵌套深度为 64。所有对象的未知字段都拒绝。

| 对象 | 字段与规则 |
|---|---|
| 根 | components 必需；version / wires / resources 可省略 |
| component | name、path 都是非空字符串；name 不含 `.`，按解码后的 Unicode 字符串唯一 |
| wire | from、to 必需，按首个 `.` 分为组件与端口；两半非空、端口无空段，接口路径另受支持范围约束 |
| resources | max_memory_pages、quota 可省略；显式 null 不接受 |

资源数值限定 0 到 2147483647。文本必须使用十进制整数 token，不接受小数点或指数形式，
即使 `1.0`、`1e0` 数学上为整数也拒绝；负零可接受并规范化为 0。
此 token 限制和重复键检测属于 JSON Schema 无法表达的额外文本规则。
数值在转换为 Int32 前检查范围，避免溢出、截断或较大 double 舍入后误放行。

不做 Unicode NFC/NFD 归一化。路径作为文本保留于计划；`plan` 读取相对路径时以清单所在目录为基准。
`convert --dep` 仍按调用目录解析并输出本机绝对路径，因此不同机器的转换结果不必相同。

## 规范计划字节

库 `plan_json` 和 CLI `--out` 文件使用同一规范内容：UTF-8，无 BOM，无缩进，无尾部换行。
stdout 用于终端传输，会附加平台行结束符；要获得可比较、可下载的规范制品请使用 `--out`。

顶层键顺序固定为 plan_version、instances、wires、resources、plan_hash。
实例键依次为 name、path、order、incoming；wire 键依次为 from、to、from_signature、to_signature；
资源键为 max_memory_pages、quota，缺失资源限制统一输出 null。

实例按确定性拓扑顺序排列：就绪节点按 Unicode 标量值逐字符字典序选择，前缀短串优先。
wire 按源组件、源端口、目标组件、目标端口四元组排序；incoming 是此排序下的 wire 索引，按升序输出。
JSON 转义固定使用核心库的 JSON 字符串化规则，双引号、反斜线及控制字符转义，合法非 ASCII 字符保留为 UTF-8。
整数输出十进制，无小数或指数。JSON 中的所有字符串原文参与规范体，不忽略路径或名称中的空白。

[ASCII 当前样本](fixtures/plan-v0.2.0.json) 和 [Unicode/转义/整数上界样本](fixtures/format-plan-v0.2.0.json)
为逐字节门禁；三个后端各生成文件并与同一黄金文件比较。

## Hash

`plan_hash` 为 FNV-1a 64，初值 `cbf29ce484222325`，逐字节异或后乘 `100000001b3`，每步模 2^64，
输出 16 位小写十六进制。输入是规范计划体的 UTF-8 字节，不含 plan_hash 字段及其前导逗号；
计划体以 `}` 闭合，无换行。plan_version 参与 hash。

该值表示计划元数据，不是密码学摘要；不包含组件文件字节。相同接口和路径下替换组件实现可能不改变它。
资源值参与 hash，但仍只是元数据，不表示执行配额已生效。

## 从 0.1.0 迁移

1. 使用当前版本重新生成计划；不要将历史计划的版本字段手工改名后复用 hash。
2. [旧样本](fixtures/plan-v0.1.0.json) 保持原始字节与 `e96eb1e1a80fbdaa`，供兼容性审阅。
   当前同一链的 hash 为 `1a3640bcc99318d5`，因为 plan_version 已改变。
3. 移除未知字段、重复键和重复 wire，补齐所有函数 import；按 M2 规则统一函数语义及参数名。
   接口实例、非函数 import 与未支持值类型仍拒绝。资源数值改用范围内的整数 token。
4. WAC 的名称与资源边界见 [WAC-SUBSET.md](WAC-SUBSET.md)。

新增字段、改变支持范围或排序/编码/兼容性策略时，必须显式更新版本契约与黄金样本，
说明迁移；历史样本保留。后续是否接受旧输入版本应逐个枚举，不使用前缀匹配。

验证命令：`python -m pip install -r scripts/schema-requirements.txt` 后执行
`python scripts/check-schemas.py`；CI 使用独立虚拟环境。此脚本验证 schemas/样本并独立计算 UTF-8 FNV。
三后端测试与真实 CLI 字节门禁另执行 `scripts/check-backends.ps1` 或 `.sh`。
