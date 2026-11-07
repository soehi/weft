# 连线类型支持矩阵（M2.1 / M2.2）

本规则用于规划器的函数级 wire，属于待发布 v0.2.0 的兼容性收紧。
它是严格结构相等规则，不提供 subtyping、资源身份匹配或接口实例整体兼容性证明。
清单与计划 JSON 的布局暂不变；格式版本与发布契约在 M2.5 收口，尚未发布新版本。

| 类型 | 规则 |
|---|---|
| 同步函数 | 参数数量、顺序、名称与类型相等；结果的存在性及类型相等。两端函数名可不同，由 wire 指定 |
| bool / s8 / u8 / s16 / u16 / s32 / u32 / s64 / u64 / f32 / f64 / char / string | 类型逐项精确匹配；同 ABI 不代表相等 |
| record | 字段数量、名称、声明顺序与字段类型相等 |
| tuple | 元素数量、顺序与类型相等 |
| list / option | 元素 / some payload 类型相等 |
| result | ok / err 的存在性分别相等，存在的 payload 递归比较；无 payload 与空 tuple 不等价 |
| variant | case 数量、名称、声明顺序、payload 存在性与类型相等 |
| flags / enum | 名称及声明顺序完全相等 |
| async / resource / own / borrow / future / stream / error-context | `Unsupported`，即使能展开为 i32 也拒绝 |
| fixed-list / map | 本轮尚未支持，明确 `Unsupported` |
| 非法、未解析、循环的 IR 类型引用 / 用函数作为值 | `Unsupported`，不会索引越界或静默近似 |

复合类型索引只在其所属组件的类型表内有意义。相同数值索引不代表相等，
不同数值索引也不代表不相等；二进制中的 alias 由现有 IR 解码路径解析后比较。

先检查两端函数及所有可达值类型是否支持，再做结构检查，最后以现有上游
`canonical_flat_types` 校验 ABI。错误点名组件、端口及参数 / 结果 / 字段 / case 路径。
未连接的函数暂不纳入 wire 检查；导入覆盖和接口实例规则另见 M2.3。

WAC 依赖固定为 `moonrockz/wac@0.3.0`。其结构比较器 `Check::compatible`
位于内部 `compatibility.mbt`，不在公开接口中；本实现遵循此处明确的严格子集，
不虚构可直接调用的上游比较 API。组件解码和 canonical ABI 展开继续复用上游。
