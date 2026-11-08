# weft 浏览器规划工作台

在仓库根目录执行：

```bash
moon update
node scripts/build-demo.mjs
python scripts/serve-demo.py
```

打开 http://127.0.0.1:8000 。支持现代 Chromium 浏览器；请通过 HTTP 打开，直接双击 index.html 无法加载模块 Worker。
专用服务器为 .mjs 设置跨平台的正确 MIME 类型，仅绑定本机回环地址。

选择清单与一个或多个组件文件，确认文件映射后点击检查。清单可编辑；路径按选中文件的逻辑路径或唯一 basename 匹配，
Windows 原始绝对路径不会被访问。同名文件不会猜测，必须从下拉框手动指定。同一个文件可供多个组件实例使用。

下载按钮保存 MoonBit API 返回的规范 UTF-8 JSON，不重新序列化，不加 BOM 或换行。
图和表使用实际计划中的实例顺序与连线；错误时显示稳定诊断码与已知组件、端口、字段。
修改清单、文件或对应关系会使旧下载结果失效。所有用户文件都留在内存中，不上传。

五类示例通过本地静态资源载入：成功链、分支汇合、成环、类型不符、缺失导入。
成功示例必须经过真正的规划器；预期失败示例展示真实诊断。组件只用于静态规划，页面不会执行 Wasm。

JS bridge 位于 src/browser_bridge，采用官方 ESM 导出配置：
https://docs.moonbitlang.com/en/latest/toolchain/moon/package.html#js-backend-link-options
页面在模块 Worker 中调用同一 api.compile，主线程只做 I/O、映射、展示和下载。
生成的 demo/planner.mjs 与 demo/examples 不提交，每次由构建脚本生成。可将构建完成的整个 demo 目录放到静态 HTTP 服务；本轮不自动部署。

测试：

```bash
node scripts/build-demo.mjs
node scripts/test-demo.mjs
python -m pip install -r scripts/browser-requirements.txt
python -m playwright install chromium
python scripts/test-browser.py
```

CI 另安装 Chromium 系统依赖。实际浏览器检查五类示例、下载/CLI 字节相同、图表来自计划、无用户文件网络请求、
重复键错误、同名文件手动映射、失效下载、非法 UTF-8、Worker 加载失败及 390px 响应布局。
DOM 输出使用 textContent，不将文件名/清单内容作为 HTML 插入。页面无 CDN、外部字体、遥测或服务端规划接口。
