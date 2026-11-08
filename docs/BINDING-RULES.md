# 完整部署计划的绑定规则（M2.3）

`plan` 生成完整部署计划。每个组件的每个普通函数 import 必须恰有一条 wire 提供它；
没有隐式宿主依赖、没有开放 import 模式，也没有宿主依赖清单字段。
需要宿主函数时，应先将它实现为可验证的提供方组件，或等待后续显式宿主依赖模型。

- 同一目标函数 import 出现多个提供方时，报 `DuplicateBinding`；重复相同 wire 也拒绝。
- 缺少提供方时，报 `UnboundImport`，包括没有任何 wire 的孤立组件。
- 同一 export 可以连接多个不同 import。每个目标各有一条 wire 即可。
- 导入整个 interface instance 需要整体实例绑定；当前函数 wire 模型无法表达，统一报 `Unsupported`。
  即使为接口里的每个函数分别连线，或接口为空，也不能据此满足实例 import。
- 导出的接口函数仍可作为普通函数 import 的提供方，例如 `source.io.read → sink.in`。
- 类型、资源、值、模块和组件等非函数 import 在 IR 的 `unwireable_imports` 中保留名称，
  完整计划明确拒绝，解码时不再丢弃。规划器不推断其能被某个函数 wire 满足。

规划器先执行现有图与端口/类型检查，随后在排序后的 wires 上检查唯一提供方，最后
按组件名和 import 名排序检查覆盖。同类绑定错误不会因清单或 wires 重排而改变对象选择和提供方顺序。
语法、图、端口或类型本身无效的输入，仍可能先得到这些阶段的错误。

公开 API 变化：手工构造 `@ir.Iface` 时必须提供 `unwireable_imports`。没有非函数 import 时填 `[]`；
从二进制输入请使用 `decode_component`，以保留所有导入。新增 `PlanError::DuplicateBinding` 和 `UnboundImport`。

这是待发布 v0.2.0 的兼容性收紧。旧清单里的重复 wire、隐式宿主 import、接口局部绑定和非函数 import
会失败；迁移需去除重复项、补齐函数提供方，并将接口消费者适配为普通函数 import，或等待整体实例绑定支持。
合法线性链的计划 JSON 与黄金 hash 保持不变，格式与版本发布契约在 M2.5 完成。
