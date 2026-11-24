# CLI + MCP 协同路由决策矩阵

## 1. 重复能力主次分工表

| 场景 | 首选（主） | 备选（辅） | 严禁 |
| :--- | :--- | :--- | :--- |
| 执行本地命令/文件批处理 | Agent 原生终端 + `~/.local/bin` CLI | Python / PowerShell 脚本 | 绕道 `windows-mcp` 的 PowerShell 工具跑普通命令 |
| 读取 Word / Excel / PPT / PDF | `markitdown` / `office-cli info` / `office-cli to-csv` | Python (`openpyxl`/`python-pptx`) | 用截图一页页翻看文档 |
| 导出 Office / WPS 为 PDF | `office-cli to-pdf` | — | 打开 GUI 菜单手动点击“导出为 PDF” |
| 操作 Obsidian 知识库 | `cli-anything-obsidian` / `obsidian-agent` | 直接读写 `.md` 文件 | 模拟鼠标点开笔记逐行编辑 |
| 操作 Notion / Figma / Canva / Zotero | 对应垂直 MCP | — | 用浏览器 MCP 模拟人工翻页 |
| 普通网页交互与表单填写 | `playwright`（如 `playwright-edge`） | 内置浏览器代理 | 用桌面坐标点浏览器网页 |
| 网络抓包 / Cookie / 性能审计 | `chrome-devtools` | `jshookmcp`（仅 JS 签名逆向） | — |
| 微信 / QQ / 腾讯会议 / 无 API 客户端 | `fast-act`（单轮批处理 + `assertOcr`） | `windows-mcp` (`Snapshot` / `Screenshot`) | 点进聊天后停下来传大图干等 |
| 长日志 / 多文件 / 海量命令输出 | `context-mode` 本地沙盒索引 | 管道过滤 (`Select-Object` / `rg`) | 原始大输出直接塞进上下文 |

## 2. 四种高价值协同组合模式

1. **CLI 批处理 + `fast-act` 收尾/发送**：用 `office-cli`、`markitdown` 或脚本后台生成成品文件 → 用 `fast-act` 切到微信/客户端窗口单轮发送或视觉核验。
2. **`windows-mcp`/`fast-act` 开路 + CLI 接管**：本地软件首次需要扫码登录或点授权弹窗时用 GUI 完成 → 后续全部切回 CLI 高速批处理。
3. **浏览器 MCP 取数 + CLI 转换 + 垂直 MCP 归档**：`playwright` / `chrome-devtools` 提取登录态数据 → `markitdown` / `office-cli` / Python 清洗 → `notion` / `lark-cli` / `obsidian-agent` 归档。
4. **自检与排障**：遇到工具找不到或 COM/OCR 异常时，第一时间运行 `pc-doctor --json` 定位缺失项。
