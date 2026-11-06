# S0 实证记录（三后端门禁）

日期：2026-11-05。工具链 `moon 0.1.20261029` / `moonc 0.10.19`。

## 结论：地基绿

| 检查 | native | wasm-gc | js |
|---|---|---|---|
| `wasm_component@0.18.0` 解析组件 | 通过 | 通过 | 通过 |
| `wasm_component/text` WAT→二进制 | 通过 | 通过 | 通过 |
| `validator` 校验 | 通过 | 通过 | 通过 |
| `wac/verifier@0.3.0` 语义解码 | 通过 | 通过 | 通过 |
| canonical ABI 展开（复用上游） | 通过 | 通过 | 通过 |

S0/S0B/S0C/S0D/S0E/S0F 六个探针在 `src/s0*_probe/`（可删）。**三后端输出逐字节一致**。

## 与提示词原文的偏差（已实测修正）

1. `canonical_flat_types` 第三参是 **`wasm_core/types.ValueType`（core 类型）**，不是 `model.ValueType`。必须传入 `I32`/`I64` 作为 pointer type，且需要显式依赖 `Milky2018/wasm_core@0.18.0`（不能靠传递依赖，moon 会拒绝）。
2. `parse_component_wat` 抛 `ComponentTextError`；`validate_component*` 抛 `ComponentValidationError`。
3. `wac` 的 `Verified`/`BinaryPackage` 通过子包 `@wac/verifier` 使用，`ReadOnlyArray` 用 `.length()` 不用 `.size()`。

## 关键架构发现

### 1. `wasm_component` 的 `Export.desc` 对 sort-only 导出为 `None`

组件里 `(export "f" (func $f))` 这类导出，`model.Export.desc` 是 `None`；签名藏在 canon `Lift(_, _, tyidx)` 与 func 索引空间里，需要重建两套索引空间才能对上。**规划器不直接走这条路。**

### 2. 正确来源：`wac/verifier::decode_component_package`

它返回 `BinaryPackage`，`world()` 指向 arena 中一个 `TypeKind::World`，其中：
- `imports: ReadOnlyArray[Extern]`（name + ItemKind）
- `exports: ReadOnlyArray[Extern]`
- `ItemKind` 指向 arena；`TypeKind::Function(params, result, is_async)` / `Scalar(name)` / `Record` / `List` / `Option` / `Result` / `Tuple` / `Variant` / `Flags` / `Enum` / `Resource` / `Own` / `Borrow` / `Interface(name, used, externs)`。

接口函数形态：world 的某个 import/export 名 → `ItemKind::Type(i)` → arena[i] 是 `Interface(name, _, externs)`，`externs` 里是 `Extern{name, kind}`，`kind` 再指向 arena 的 `Function`。

### 3. 类型表可无损转回 `model` 并复用上游 canonical ABI

`arena -> Array[model.TypeDef?]` 的转换后，`@wasm_component.canonical_flat_types(valtype, table, I32)` 能得到正确的 core 扁平类型：

```
param xs: [i32, i32]   # list<u32> = ptr+len
param flag: [i32]      # bool
result: [i32, i32]     # string = ptr+len
```

规划器的签名检查就建立在这条链上，不复制 ABI 规则。

### 4. WIT 编码产物不是可运行组件

`wit.encode_wit_component_wasm` 产出的是「WIT 包组件」（world 导出为嵌套 world），**不能当普通组件执行**。测试夹具应走 WAT 路径（`parse_component_wat`），或直接写二进制。这点已写死，避免 S3 踩坑。

## 平台事实

- `wasmoon@0.18.0` 只有 `supported_targets = "+native"`，且 Windows MSVC 因 C11 原子失败（需 clang-cl / WSL / Linux）。规划层绝不依赖它。