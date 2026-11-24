# Universal PC Pilot — 电脑操控与工具协同全局规则

## 1. 四层工具调用优先级漏斗（强制执行）
1. **第 1 层（最高优先级）：原生终端 + 本机专用 CLI** — 文件批处理、文档转换（`markitdown`、`office-cli`）、代码构建（`msbuild`、`dotnet`、`conda`、`wechat-cli`）、知识库（`cli-anything-obsidian`、`obsidian-agent`）、协同（`lark-cli`、`gh`）、本地 AI（`ollama`）与虚拟机（`vmrun`、`vboxmanage`），直接走命令行。严禁绕道桌面截图点击，严禁用 `windows-mcp` 的 PowerShell 跑普通命令。
2. **第 2 层：垂直领域 MCP** — Notion、Figma、Canva、Zotero、Overleaf、Jupyter、Supabase 等优先走结构化 MCP。
3. **第 3 层：浏览器自动化 MCP** — 网页交互优先 `playwright`，性能/Cookie 调试用 `chrome-devtools`，前端逆向才用 `jshookmcp`。
4. **第 4 层：桌面 GUI 兜底（`fast-act` + `windows-mcp`）** — 仅用于无 CLI/API/MCP 的原生桌面客户端（微信、QQ、CAD/CAE、系统弹窗等）。
5. **横向粘合：`context-mode` MCP** — 大输出/长日志/多网页检索优先本地索引压缩后再汇总。

## 2. 本机动态工具清单
- 已接入 `~/.local/bin` 的全部可用 CLI 与路径清单见 `~/.pc-pilot/MACHINE_TOOLS.md`（可随时执行 `pc-doctor --json` 体检）。

## 3. 桌面 GUI 操控铁律（使用 `fast-act` / `windows-mcp` 时强制遵守）
- **无边框静默 & 窗口最大化**：保持 `--no-control` 与 `WINDOWS_MCP_DISABLE_FLASH=1`；激活窗口默认最大化（已最大化且在前台时勿重复刷掉浮层/菜单）。
- **单次动作链优先**：同界面连续动作优先用 `fast-act`，支持相对坐标 `rx, ry`（越界拦截）、`clickName`（UIA 直达）、`scroll`、`drag`、`readOcr`（纯文本 OCR 免传大图）与 `focusPopup`。
- **通讯软件发消息铁律**：在 `fast-act` 单轮内完成 `^f` 搜索 → 粘贴联系人 → 回车 → **50ms 本地 `assertOcr` 顶栏校验** → 粘贴消息 → 回车发送，绝不跳过 OCR 校验，也绝不点进聊天后干等传大图。
- **防串字与剪贴板保护**：`paste` 默认先清空原框并自动备份还原剪贴板（支持文本/图片/文件）；高危不可逆操作必须单步确认。
- **2.5 秒触碰即让权**：检测到用户移动鼠标或按键立即停手让权，停手满 2.5 秒后截图接力。
- **结束必弹回宿主窗口**：加上 `-ReturnFocus` 参数（或调用 `focus-caller`），自动将当前 Agent/IDE/终端窗口置顶弹回最前。
