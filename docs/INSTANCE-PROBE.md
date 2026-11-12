# D0 接口实例与摘要探针（2026-11-12）

本批落实[核心深化规划](CORE-DEVELOPMENT.md)第8节的三个先行探针。
生产IR、规划API、清单和计划格式均未变；通用`weft run`仍未支持，当前函数模式继续拒绝接口实例import。

## 固定规则与输入

规范快照为[Component Model AST Explainer，6250899](https://github.com/WebAssembly/component-model/blob/6250899af9a71591dcfdb2500b41343c330623f9/design/mvp/Explainer.md)，
原始文本SHA-256和依赖版本见[快照记录](specs/component-model-d0.lock.json)。快照仅固定采用规则，不代表依赖实现了全文所有特性。

- 实例实参必须满足消费者声明的每个命名成员；独立验证组件成功不能代替组合兼容性检查。
- 函数与命名类型关系必须在各自作用域解析；arena下标仅是局部引用，不能跨组件直接比较。
- 非resource值类型以结构关系为依据；导出类型及alias需要保留来源与引用，不能只提取函数列表。
- 本批执行只验证两个同步u32函数和一个u32类型导出。bool反例与u32有相同的core ABI形状，仍须拒绝。
- resource身份、async、复杂值真实执行、嵌套接口以及完整subtyping均不在此次执行结论内。

## 解码结论

固定`wasm_component@0.18.0`汇编的五个[真实组件](../examples/instances/README.md)均由`wac/verifier@0.3.0`成功语义解码。
上游world保留实例import/export，实例成员中保留`value`类型导出及两个函数，arena保留`Alias`节点；
通过显式`alias export`与`value-copy`类型再导出核对这些信息并非仅存在于WAT文本。

当前`ir.decode_component`的接口导出只剩`inc`/`twice`函数列表；`value-copy`顶层类型导出被忽略，
`build_types`将Alias和Interface映射为None，类型使用处解引用后只保留值结构。
两项可移植回归断言同时检查上游保留与现有IR丢失，避免将当前IR误当成完整接口语义。
这证明D1需要保留信息的解码适配；暂不新增公开IR字段，不将“函数可枚举”等同于实例支持。

## Linux完整实例实际调用

新增三项native测试放在`src/runtime_probe/instance_wbtest.mbt`：

1. 实例化source，取其`ops`导出，以单个`Instance`外部值传给linker，再实例化consumer；输入0/7/41应分别得到2/16/84。
2. 不接ops、缺少twice、value/inc类型不符，均要求消费者实例化失败；两个错误提供方须先独立验证、实例化成功。
3. 同时实例化原提供方和另一提供方，将整个ops改接到后者，consumer输入41应得到102。

使用已有固定版本的底层`ComponentLinker.add_import`，没有将两个成员分别注册成host函数。
两个算术步骤都由组件内的core Wasm执行，宿主仅连接并断言返回值。
本机Windows类型检查已通过。首次Linux运行中正常调用与改接通过；负例测试暴露上游缺成员时仅报告`UnknownImport("ops")`，
而不是成员`twice`。探针按固定上游的实际错误类型断言，D1仍须在独立静态检查中补齐成员路径，不依靠运行时诊断实现该要求。
修正后完整结果以本批CI为准，不能将首次失败运行算作全套探针通过。

## SHA-256选择

复用已固定的`moonbitlang/x@0.5.5`中`crypto.sha256`及增量`SHA256`，模块和源文件声明Apache-2.0。
这是纯MoonBit字节实现，没有引入新的依赖版本或host crypto接口；源码哈希见快照记录。

两项独立测试覆盖空输入、ASCII abc、56字节及112字节多块向量、一百万个a、0到255的二进制字节，
以及0/1/55/56/63/64/65/255/256处分片的增量与一次性结果一致。
文本向量显式UTF-8且无BOM，不复用上游测试中的UTF-16文本编码假设。
标准例值参考[NIST SHA-256示例](https://csrc.nist.gov/projects/cryptographic-standards-and-guidelines/example-values)和
[NIST NSRL测试数据](https://www.nist.gov/itl/ai/ai-standards-and-guidelines-group/nsrl-test-data)；二进制向量亦与Python标准库结果核对。
这些检查验证此固定实现的本项目使用路径，不构成密码模块认证或独立安全审计。

## 复验与下一步

```bash
node scripts/check-backends.mjs
# Linux固定工具链
moon test src/runtime_probe src/runtime_native --target native
```

原139个核心测试与35项CLI按原口径报告；D0另列4个可移植探针和3个native测试。
## 固定外部组合器

选择[Bytecode Alliance WAC 0.12.0](https://github.com/bytecodealliance/wac/releases/tag/v0.12.0)，
许可证Apache-2.0。Windows/Linux官方原始二进制SHA-256固定在`release/external-tools.lock.json`，
安装器只写`_build/external`，不改变系统PATH；工具不随规划CLI或Mooncakes库再分发。
依赖解析使用显式本地`--dep`参数，组合时不跳过产物验证。

```bash
python scripts/install-external-wac.py
python scripts/test-external-wac.py
# 等价的合法组合命令（Windows使用wac.exe）
_build/external/wac compose examples/instances/compose.wac \
  --dep d0:provider=examples/instances/source.wasm \
  --dep d0:consumer=examples/instances/consumer.wasm -o _build/instance.wasm
```

本机五个外部用例通过：source与alternate成功生成不同的组件制品；缺成员点名twice，错误类型点名value/u32/bool，
断线点名ops，三个反例均非零退出且不生成制品。脚本固定UTF-8读取诊断，支持带空格及Unicode路径。
Linux已纳入native可移植门禁，实际结果待本批CI。该外部组合证明当前最小子集，不扩大为完整接口兼容性或复杂类型差分结论。

D0在Linux运行与外部门禁全部通过后完成；随后进入D1的作用域IR、结构化实例绑定与迁移设计。
