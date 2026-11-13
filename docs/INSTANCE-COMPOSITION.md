# D1 接口实例组合开发记录

状态：D1源代码集成与验收中；正式交付仍为0.3.1，旧函数模式与计划0.2.0不变。
本文件描述新模式的明确子集，不宣称完整Component Model subtyping。

## 作用域IR

新增`soehi/weft/compose_ir`，独立于旧`ir.Iface`。`decode`保留每个组件自己的类型arena、二进制作用域索引映射、
实例成员、命名类型导出、Alias边和UsedType来源。类型构造中的引用均属于该组件的解析arena，不能跨组件按数值比较。
不支持的resource/handle/async等构造也显式保留，供类型层具名拒绝；不会转换成None而丢失语义。

这是候选0.4的新实验接口；旧`ir.decode_component`和`api.compile`保持原行为。
迁移到新模式应整体使用compose_ir，不将旧函数列表强转为完整接口。

## 实例兼容规则

`compose_types.check_instance`将消费者的完整实例import与提供方的完整实例export进行匹配，返回局部类型对应关系。

- 提供方满足消费者所有命名成员，允许额外的受支持成员；成员声明顺序不影响结论。
- 支持同步函数、非resource命名值类型和嵌套实例。函数参数标签不参与此新模式的类型相等；旧函数模式的规则保持原样。
- 标量类型严格匹配；record字段、tuple元素、variant case、flags/enum名称及顺序均严格匹配。支持list/option/result等现有同步结构。
- 两侧分别解析alias，再建立消费者类型引用到提供方引用的结构对应关系。一个共享消费者类型可以对应多个结构相等的提供方节点。
- 每侧先用显式DFS区分访问中与已完成节点，拒绝非法循环，再使用已验证类型对避免重复比较；遇到访问过的节点本身不作为循环兼容证明。
- 整个已绑定接口必须在支持子集内，额外的未支持成员也拒绝。resource/own/borrow、future/stream、async、map、fixed-list及外部宿主能力均不自动放行。
- 错误带稳定code、组件与分段path；类型不符、缺成员、重复成员、错误引用与不支持构造分别报告。path不靠点号拆分名称。

真实Wasm用例验证D0双函数、命名类型、alias及缺成员/同ABI异语义反例；真实复合类型夹具使用显式导出的类型别名满足可见性约束。
其他用例覆盖arena重编号、较长alias链、共享类型、嵌套复合值、循环、公共IR修改和具名错误路径。

## 新模式的输入与计划

`soehi/weft/compose`提供纯`parse`、`compile`与`emit_wac`。清单显式声明`manifest_version: "0.3.0"`与
`profile: "instance-sync-v1"`，不会隐式接收旧格式。组件仍用name/path声明，字节Map按精确name提供，缺少或多余ID均拒绝。
绑定kind为function或instance；from/to含component和port，函数来源可用独立member字段访问接口成员，不解析点号拼接。
实例必须整体绑定；同一import的重复提供方、整个实例与成员混用均拒绝，单独成员绑定不能满足实例import。
不同根import可以分别使用函数和实例绑定；每个import必须有且仅有一个明确提供方，非函数/实例宿主能力不自动安装。

新计划版本0.3.0包含确定性实例顺序、结构化bindings及InstallImport/Instantiate操作：提供方先实例化，
再为目标安装全部导入，最后实例化目标。清单和计划schema位于schemas/manifest-instance-v0.3.0.schema.json与
schemas/plan-instance-v0.3.0.schema.json。文件规范UTF-8、无BOM/末尾换行；stdout行结束符仅为终端传输。
本模式尚无内容摘要或锁文件，不能据此发现同路径同接口的二进制替换；这属于D2。没有把旧FNV当成新制品身份。

旧manifest/plan 0.1.0/0.2.0继续由原API与CLI处理；新模式在main开发，未发布0.4包或替换正式0.3.1制品。

## 源码命令与真实执行边界

```bash
moon run src/compose_cli --target js -- plan examples/instances/chain.json --out plan-instance.json
moon run src/compose_cli --target js -- emit-wac examples/instances/chain.json --out instance.wac
# Linux，先按release/README.md启用锁定工具链
moon run src/runtime_instance --target native -- run examples/instances/chain.json --component consumer --export run --arg u32:41
```

规划CLI可用native/wasm-gc/js；文件基于清单目录解析，从其他工作目录运行有效。WAC发射来自同一检查结果，
现阶段组件及端口只发射可保真的小写kebab子集；其他合法逻辑ID仍可规划，但WAC明确拒绝。
固定外部WAC 0.12.0已接受新发射器的完整实例传递，并拒绝缺成员与错误类型依赖。

独立runtime_instance只接受重新从清单和字节编译的计划，不把外部plan JSON当作可信执行输入。
调用仅开放D0已验证的同步单u32参数、单u32结果；静态复合值兼容性不等于复合值执行已支持。
新增Linux测试覆盖84/102、函数成员转发42、静态错误先于运行时、未知调用目标和未绑定时不实例化trapping源；真实结果以完整CI为准。
通用`weft run`仍未支持，Windows不声明原生执行可用。

## 本批验证入口

`node scripts/check-backends.mjs`包含原139测试、D0各4测试、D1各30测试，原35 CLI与新实例26 CLI分别计数。
`python scripts/test-external-wac.py`独立检查固定外部组合器；Linux另运行`python scripts/test-native-instance-cli.py`。
三后端实际新计划与docs/fixtures/plan-instance-v0.3.0.json逐字节一致；输入排列、部分绑定、重绑、未知格式、重复JSON键、
非法UTF-8、Unicode/空格目录和失败不覆盖输出均已纳入实际CLI验证。
