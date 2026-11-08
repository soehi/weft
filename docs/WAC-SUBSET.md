# WAC 往返支持范围（M2.4）

`emit-wac` 是不读取组件二进制的文本转换；实际端口、类型和 import 覆盖仍由 `plan`
或 WAC 验证器检查。往返承诺覆盖组件名称、依赖路径与函数连线，不代表可执行产物验证。

## 发射规则

- 规划器与 WAC 适配器共用 `src/graph` 的图构建、环检测和拓扑排序。规划包保留旧函数包装及 `Graph` 类型别名。
- 按依赖顺序声明实例；就绪节点按组件名字典序选择，参数与导出按固定顺序发射。
- 组件名限定为小写 kebab 名：每段以 a–z 开头，后续可含 a–z 和数字，段间一个 `-`。
  名称不做有损消毒；冒号、斜线、下划线、Unicode、引号、反斜线、换行等明确 `Unsupported`。
  因此 `a:b` / `a/b` 不会碰撞成同一个包名。
- 包引用固定为 `weft:<组件名>`，局部变量为 `c-<组件名>`，映射一一对应，避免保留字冲突。
- 函数端口同样限定为上述 kebab 名。参数使用字符串名、export access 使用括号字符串形式。
  `iface.func` 等接口路径暂时拒绝；不将实例语义近似成函数连线。
- 路径不嵌入 WAC 注释，避免换行或引号注入；实际路径由 `convert --dep` 或库的 `WacDep.path` 提供。
- 环、未知组件和重复目标绑定明确报错。资源策略无法由当前 WAC 子集携带，存在任何资源字段
  （包括 0）时发射失败；调用方须明确移除后才可转换。

## 转换规则

先由固定依赖的上游 WAC 验证器检查，再映射已验证模型：

- 每个实例必须恰有一个 whole-instance export，其名称作为清单组件名并满足上述 kebab 规则。
- 直接函数 Access 作为实例化参数恢复为 wire；依赖按包名和版本查找，路径使用对应 `WacDep.path`。
- 隐藏实例、同一实例多重导出、函数/类型等非实例导出、宿主 import、本地定义值、
  非函数参数和不能追溯到直接实例导出的 access，明确拒绝。
- 经上游正规化后满足上述结构的表达式可转换；不承诺保留原 WAC 的变量名、语法布局或未使用声明。
- `convert` 不接收原清单资源策略，因此不会重建这些字段；清单格式版本写入当前的 `0.1.0`。
  跨版本格式契约在 M2.5 固定。

## 使用与迁移

资源策略清单可直接 `plan`；如需 WAC，应另备明确移除 `resources` 的转换清单。
`emit-wac plain.json --out composition.wac` 后，提供所有 `weft:<组件名>=<实际路径>` 依赖：

```bash
weft convert composition.wac --dep weft:reader=reader.wasm --dep weft:filter=filter.wasm --out converted.json
weft plan converted.json
```

`manifest_to_wac` 现在抛 `WacError`；库调用方须处理错误。`instance_name` 现在只添加 `c-` 前缀，
输入合法性由发射入口检查。原先依赖名称消毒、包短名推断或隐藏实例的调用需按上面的子集迁移。
