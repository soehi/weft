# 文档索引

先读 [../README.md](../README.md)（是什么、怎么用、边界在哪），再读
[../ARCHITECTURE.md](../ARCHITECTURE.md)（为什么这样分层）。

这两份是"计划中应当如此"的说明。下面三份是**实测记录**，记录在真实工具链上
发生了什么、哪些假设被证伪、哪些做法被换掉。

| 文件 | 内容 |
|---|---|
| [S0-FINDINGS.md](S0-FINDINGS.md) | 三后端门禁的六次探针：`wasm_component` / `wac` 的真实 API、`Export.desc` 为 `None` 的坑、为什么改用语义模型、canonical 展开如何复用 |
| [S3-EXECUTION.md](S3-EXECUTION.md) | 执行层做到哪一步、Windows/MSVC 的 C11 原子阻塞、尝试过的全部绕过手段及结果、Linux 上的复现步骤 |

## 关键实测结论（速查）

1. **`canonical_flat_types` 的第三参是 core 的 `ValueType`**，不是 model 的。且 `wasm_core` 必须显式依赖。
2. **`model.Export.desc` 对 sort-only 导出是 `None`**，所以规划器从 `wac/verifier` 的 arena 取签名。
3. **`String::compare` 在本工具链里先比长度再比内容**，不是字典序。项目自备 `cmp_str`。
4. **WIT 编码（`encode_wit_component_wasm`）产出的是 WIT 包组件**，不是可运行组件；测试夹具走 WAT。
5. **wasmoon 只支持 native**，且 MSVC 上因 C11 原子无法构建；因此执行层被隔离在单独包里。

## 复现

```bash
bash scripts/check-backends.sh
```

一条命令完成：生成夹具 → 三后端跑 75 个测试 → 三后端各生成一份计划 → 逐字节比较。