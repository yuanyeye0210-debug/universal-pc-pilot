---
name: pc-pilot
description: >-
  Universal Windows PC automation & tool routing skill: CLI-first execution
  (CLI-Anything, Office/WPS silent COM, dev toolchains), vertical & browser MCP
  coordination, context-mode output compression, patched Windows-MCP human handoff
  (0ms touch-to-yield, 2.5s RESCAN_REQUIRED rescan gate, 3-dot wave spinner with
  hidden system cursor), and sub-second Win32/UIA/WinRT-OCR desktop GUI control
  via fast-act.
---

# Universal PC Pilot v2.1.0（全通用电脑极速操控与人机协同指南）

当你需要操控用户的 Windows 电脑、批量处理本地文件/办公文档、调试项目或操作桌面软件时，强制遵循以下路由优先级与执行规范。

## 1. 四层工具调用优先级漏斗（强制执行）

**能通过后台 CLI、脚本或接口秒完成的任务，严禁绕道桌面截图点击！**

1. **第 1 层：原生终端 + 本机专用 CLI（最高优先级）**
   - 直接通过原生终端/Shell 调用 `~/.local/bin` 中已接入的 CLI（支持 `--json` 时优先使用 `--json`）：
     - `cli-hub` / `cli-anything-*`：桌面软件 Agent CLI 化控制（Obsidian、Ollama、Mermaid 等）
     - `markitdown <文件>`：将 `.docx` / `.xlsx` / `.pptx` / `.pdf` 快速提取为结构化 Markdown
     - `office-cli`：基于 Microsoft Office / WPS 双引擎 COM 静默导出 PDF（`to-pdf`）、Excel 转 CSV（`to-csv`）、读取文档结构（`info`）
     - 开发与系统：`git`、`gh`、`code`、`pycharm`、`msbuild`、`dotnet`、`vswhere`、`devenv`、`conda`、`wechat-cli`、`vmrun`、`vboxmanage`、`7z`、`winget`
   - 若已运行过 `install.ps1`，当前机器的实时可用工具列表位于 `~/.pc-pilot/MACHINE_TOOLS.md`。
   - **禁止**使用 `windows-mcp` 的 `PowerShell` 工具跑普通命令；普通命令直接走 Agent 自带终端。
2. **第 2 层：垂直领域 MCP**
   - 云服务与专业系统（Notion、Figma、Canva、Zotero、Overleaf、Jupyter、Supabase、Tavily、arXiv）优先直接调用对应 MCP 工具。
3. **第 3 层：浏览器自动化 MCP**
   - 常规网页交互/登录态表单操作优先使用 `playwright`（如 `playwright-edge`）或内置浏览器代理；
   - 性能/Network/Console/Cookie 调试使用 `chrome-devtools`；
   - 前端 JS 签名逆向分析使用 `jshookmcp`。
4. **第 4 层：桌面 GUI 兜底（`fast-act` + `windows-mcp`）**
   - 仅用于既无 CLI 也无 MCP/API 的原生桌面客户端（如微信、QQ、腾讯会议、SOLIDWORKS、Ansys、系统弹窗等）。
5. **横向粘合剂：`context-mode` MCP**
   - 批量执行 CLI、解析长编译日志或抓取大量网页时，配合 `context-mode` 在本地沙盒索引过滤，只回传关键结论，防止撑爆上下文。

---

## 2. 桌面 GUI 极速高准度操控与人机协同铁律

当必须进入第 4 层桌面操控时，优先使用本插件提供的 `fast-act`（已加入 `PATH`）与增强版 `windows-mcp` 协同工作：

- **无大边框 + P 款三点思考图标 + 隐藏系统鼠标箭头**：保持 `--control --control-idle-timeout 2.5 --control-policy balanced` 与 `WINDOWS_MCP_OVERLAY_MODE=spinner`、`WINDOWS_MCP_YIELD_ON_ANY_INPUT=1`、`WINDOWS_MCP_CONSENT_COUNTDOWN=0`、`WINDOWS_MCP_DISABLE_FLASH=1`；思考与操控桌面期间只在鼠标旁显示 44px 灰白三点波浪起伏思考动画并自动隐藏系统白色鼠标箭头，不显示屏幕四周大边框与顶部黑横幅。
- **默认最大化与前台强校验**：激活目标窗口时默认最大化；每次点击/输入前自动校验前台 PID，若焦点被用户切走立即中止。
- **已最大化窗口防刷掉浮层**：若目标窗口已处于前台且已最大化，`fast-act` 不会重复调用最大化，避免冲掉搜索下拉框或右键菜单。
- **相对坐标 + 原生控件直达**：优先使用 `clickName`（Windows UIA 按控件文本直接点击）或窗口内相对坐标 `rx, ry`（越界自动拦截）；核验截图（`-CapturePath`）自带 `100px` 刻度标尺与红点准星。
- **纯文本本地 OCR（零传图消耗）**：读取弹窗或列表状态优先用 `readOcr` 动作直接返回文本，无需每次截 2K 大图。
- **通讯软件发消息单轮铁律（1 秒内一气呵成且 100% 防发错人）**：
  在 `fast-act` 单次调用中串联：
  1. `{"type":"key","keys":"^f"}` → `{"type":"wait","ms":180}` → `{"type":"paste","text":"联系人名"}` → `{"type":"wait","ms":450}` → `{"type":"key","keys":"{ENTER}"}`
  2. `{"type":"wait","ms":200}` → `{"type":"assertOcr","rx":520,"ry":30,"w":500,"h":70,"contains":"联系人名"}`（50ms 本地 WinRT OCR 校验顶部标题栏，不匹配当场报错拦截！）
  3. `{"type":"paste","text":"消息内容"}` → `{"type":"wait","ms":60}` → `{"type":"key","keys":"{ENTER}"}`（仅当整个任务到此结束时才附带 `-ReturnFocus`）
- **防串字与全类型剪贴板保护**：`paste` 默认先 `Ctrl+A -> Backspace` 清空（可通过 `"clear": false` 关闭），并在前后自动备份还原用户的文本/图片/文件剪贴板；涉及删除、支付、不可撤回发送等高危操作必须单步确认。
- **触碰即停 + 2.5 秒让权 + 强制重查接力**：检测到用户移动鼠标、点击、滚轮或按键时 0ms 立即停手让权（不吞用户输入），思考动画消失并瞬间恢复系统指针；待用户停手满 2.5 秒后，必须先调用 `Snapshot` / `Screenshot` 检查当前电脑界面与用户协助点好的最新进度（否则底层返回 `RESCAN_REQUIRED` 硬拦截），再重新规划下一步，严禁盲目沿用旧计划。
- **仅在任务完成时弹回宿主 Agent 窗口**：多步骤操控与思考期间**严禁**频繁弹回 Antigravity / 宿主窗口（勿传 `-ReturnFocus`、勿中途调用 `focus-caller`）；仅在整个任务彻底完成或必须由用户在聊天框回复时，先调用 `ControlStatus(release=true)` 释放控制并恢复指针，再弹回宿主窗口。
- **临时文件零残留铁律**：执行过程中生成的核验截图与中转文件必须复用同一临时路径覆盖写入（如 `$env:TEMP\pc_pilot_verify.png`），**任务结束前必须彻底删除本次 AI 生成的全部临时文件**，不占用用户磁盘与内存。

---

## 3. 详细参考手册

- `fast-act` 完整参数与 14 种动作 JSON Schema：[fast-act-reference.md](./references/fast-act-reference.md)
- CLI + MCP 协同矩阵与决策树：[cli-mcp-matrix.md](./references/cli-mcp-matrix.md)
