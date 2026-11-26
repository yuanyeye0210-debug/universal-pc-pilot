# Universal PC Pilot — 电脑操控与工具协同全局规则 (v2.1.0)

## 1. 四层工具调用优先级漏斗（强制执行）
1. **第 1 层（最高优先级）：原生终端 + 本机专用 CLI** — 文件批处理、文档转换（`markitdown`、`office-cli`）、代码构建（`msbuild`、`dotnet`、`conda`、`wechat-cli`）、知识库（`cli-anything-obsidian`、`obsidian-agent`）、协同（`lark-cli`、`gh`）、本地 AI（`ollama`）与虚拟机（`vmrun`、`vboxmanage`），直接走原生终端。严禁绕道桌面截图点击，严禁用 `windows-mcp` 的 PowerShell 跑普通命令。
2. **第 2 层：垂直领域 MCP** — Notion、Figma、Canva、Zotero、Overleaf、Jupyter、Supabase 等优先走结构化 MCP。
3. **第 3 层：浏览器自动化 MCP** — 网页交互优先 `playwright`，性能/Cookie 调试用 `chrome-devtools`，前端逆向才用 `jshookmcp`。
4. **第 4 层：桌面 GUI 兜底（`fast-act` + `windows-mcp`）** — 仅用于无 CLI/API/MCP 的原生桌面客户端（微信、QQ、已打开的登录态浏览器、CAD/CAE、系统弹窗等）。沙盒化 Agent 中，通过 `windows-mcp` 的 `PowerShell` 直接 `&` 调用 `fast-act.ps1` / `focus-caller.ps1`（勿套多余子 Shell）。
5. **横向粘合：`context-mode` MCP** — 大输出/长日志/多网页检索优先本地索引压缩后再汇总。

## 2. 本机动态工具清单
- 已接入 `~/.local/bin` 的全部可用 CLI 与路径清单见 `~/.pc-pilot/MACHINE_TOOLS.md`（可随时执行 `pc-doctor --json` 体检）。

## 3. 桌面 GUI 操控与人机协同铁律
- **无大边框 + P 款三点思考图标 + 隐藏系统鼠标箭头**：保持 `--control --control-idle-timeout 2.5 --control-policy balanced` 与 `WINDOWS_MCP_OVERLAY_MODE=spinner`、`WINDOWS_MCP_YIELD_ON_ANY_INPUT=1`、`WINDOWS_MCP_CONSENT_COUNTDOWN=0`、`WINDOWS_MCP_DISABLE_FLASH=1`；思考与操控桌面期间只在鼠标旁显示 44px 灰白三点波浪起伏思考动画并自动隐藏系统白色鼠标箭头，不显示屏幕四周大边框与顶部黑横幅；激活窗口默认最大化（已最大化且在前台时勿重复刷掉浮层/菜单）。
- **单次动作链 + 零传图优先**：同界面连续动作优先用 `fast-act`，支持相对坐标 `rx, ry`（越界拦截）、`clickName`（UIA 直达）、`scroll`、`drag`、`focusPopup`；只需核对弹窗/状态文字时优先 `readOcr`（纯文本本地 OCR，免传 2K 大图，极速省上下文）。
- **通讯软件发消息铁律**：在 `fast-act` 单轮内完成 `^f` 搜索 → 粘贴联系人 → 回车 → **50ms 本地 `assertOcr` 顶栏校验** → 粘贴消息 → 回车发送，绝不跳过 OCR 校验，也绝不点进聊天后干等传大图。
- **防串字与剪贴板保护**：`paste` 默认先清空原框并自动备份还原剪贴板（支持文本/图片/文件）；高危不可逆操作必须单步确认。
- **触碰即停 + 2.5 秒让权 + 强制重查接力**：检测到用户移动鼠标、点击、滚轮或按键时 0ms 立即停手让权（绝不吞掉用户输入），思考动画消失并瞬间恢复系统指针；待用户停手满 2.5 秒后，强制先执行 `Snapshot`/`Screenshot` 重查当前最新界面与前景窗口（未重查前底层以 `RESCAN_REQUIRED` 硬拦截所有动作），确认用户已协助完成的操作后再重新规划下一步。
- **仅在任务完成时弹回宿主窗口**：多步骤操控与思考期间严禁中途弹回 Antigravity / 宿主窗口（勿传 `-ReturnFocus`、勿中途调用 `focus-caller`）；仅在整个任务彻底完成或需用户回复确认时，先调用 `ControlStatus(release=true)` 释放控制并恢复指针，再调用 `focus-caller` 置顶弹回。

## 4. 临时文件零残留铁律（强制执行）
- **单文件覆盖，绝不堆积**：AI 执行过程中产生的临时核验截图、临时脚本或中转文件，统一写入临时路径并**复用同一个文件名覆盖**（如 `$env:TEMP\pc_pilot_verify.png`），严禁按步骤编号堆积占用磁盘。
- **任务结束强制清理**：每次任务完成后、向用户汇报前，**必须删除本次思考与执行过程中由 AI 生成的全部临时文件**，仅保留用户明确要求创建的正式文件。
