# Universal PC Pilot v2.1.0 (全通用电脑极速操控与人机协同插件)

> 让市面上**所有主流 AI Agent**（Google Antigravity、Claude Code、OpenAI Codex、Cursor、Windsurf、Cline、Roo Code、OpenClaw 等）在任何 Windows 电脑上**拿到就能直接用**的 CLI 优先 + MCP 协同 + 人机无缝接力 + 亚秒级桌面操控插件。

---

## 给 AI Agent 的全自动安装指令

把下面这句话直接发给任意 AI Agent，它就会自己读完文档并一键装好：

> 请读取 `https://raw.githubusercontent.com/yuanyeye0210-debug/universal-pc-pilot/main/AI_INSTALL.md` 并按照里面的步骤在我的电脑上全自动完成安装、Windows-MCP 增强补丁部署、MCP 配置合并与 `pc-doctor` 体检。

---

## v2.1.0 核心能力与解决的问题

1. **拒绝慢吞吞的盲点截图**：建立「**原生 CLI（最高优先级）→ 垂直 MCP → 浏览器 MCP → 桌面 GUI 兜底**」四层漏斗，能用命令行 0.1 秒解决的绝不截图点鼠标。
2. **增强版 `Windows-MCP` 一键补丁打包（跨机 100% 复现）**：
   - 内置标准补丁 [`patches/windows-mcp-handoff.patch`](./patches/windows-mcp-handoff.patch) 与部署脚本 [`scripts/setup-windows-mcp.ps1`](./scripts/setup-windows-mcp.ps1)，自动对齐基线 `CursorTouch/Windows-MCP@dba6528` 并打好增强补丁；
   - **0ms 触碰即停让权**（`WINDOWS_MCP_YIELD_ON_ANY_INPUT=1`）：用户移动鼠标（>=4px）、点击、滚轮或敲击任意键时立刻停手且不吞掉用户输入；
   - **2.5 秒硬等待 + `RESCAN_REQUIRED` 强制重查接力**：用户停手满 2.5 秒后，底层强制要求先 `Snapshot`/`Screenshot` 同步最新画面（注入 `[HUMAN_HANDOFF_SYNC]`），否则硬拦截后续动作，绝不盲目沿用旧计划；
   - **无大边框 + P 款三点思考图标 + 隐藏系统指针**（`WINDOWS_MCP_OVERLAY_MODE=spinner`、`WINDOWS_MCP_CONSENT_COUNTDOWN=0`、`WINDOWS_MCP_DISABLE_FLASH=1`）：取消屏幕四周彩色边框、顶部黑横幅与截图闪光，思考期仅在鼠标旁显示 44px 灰白三点波浪起伏动画并隐藏系统白色箭头，一碰键鼠或结束瞬间恢复；
   - **仅在任务完成时弹回宿主窗口**：多步骤中间不频繁切换抢焦点，仅整套任务彻底完成时先释放控制再置顶弹回。
3. **Antigravity 原生插件化挂载 + 不覆盖个人守则**：
   - `install.ps1` 自动组装 `~/.gemini/config/plugins/universal-pc-pilot/` 原生插件（不含多余 `mcp_config.json`，避免双实例冲突）；
   - 修复旧版覆盖 `~/.gemini/GEMINI.md` 问题，默认完全保留用户既有个人全局守则。
4. **换台电脑也能自动识别本机软件 + 国产 WPS / 微软 Office 双引擎**：
   - 自动扫描本机已安装的办公、编程、AI、虚拟化软件并生成 `~/.local/bin` 无污染垫片与 `~/.pc-pilot/MACHINE_TOOLS.md`；
   - 内置 `office-cli` 后台静默导出 PDF（`to-pdf`）、Excel 转 CSV（`to-csv`）、读取文档结构（`info`）。
5. **亚秒级 Win32 + UIA + WinRT 本地 OCR 桌面动作链（`fast-act` v2.1）**：
   - 支持 `assertOcr`（50ms 本地顶栏校验，通讯软件发消息 100% 防发错人）与 `readOcr`（免传大图直接返回纯文本）；
   - 支持 `scroll`、`drag`（每步检测 + 4px 防误触）、`clickName`、`focusPopup`、STA 安全全类型剪贴板保护，以及临时文件零残留规范。

---

## 快速开始（拿到就能用）

### 方式 1：完整一键安装（推荐，适用于任意 Windows 电脑）

```powershell
git clone https://github.com/yuanyeye0210-debug/universal-pc-pilot.git
cd universal-pc-pilot
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -MergeMcpConfig
```

安装完成后会自动：
- 安装 `cli-hub`（`cli-anything-hub`）与 `markitdown`；
- 扫描本机已装软件并在 `~/.local/bin` 生成 `.cmd` 垫片；
- 克隆基线 `CursorTouch/Windows-MCP` 至 `~/.pc-pilot/Windows-MCP`，应用增强补丁并写入 `~/.windows-mcp/config.toml`（`idle_timeout_seconds = 2.5`、`consent_countdown_seconds = 0`、`mouse_takeover_units = 40`）；
- 挂载 Antigravity 原生插件（`~/.gemini/config/plugins/universal-pc-pilot`）及 Claude Code / Codex / Cursor / `.agents` 技能与规则；
- 生成即用的 `~/.pc-pilot/mcp_config.ready.json` 与 `~/.pc-pilot/codex_config.ready.toml`（附 `-MergeMcpConfig` 时自动合并进已有 Antigravity / Cursor MCP 配置）；
- 运行 `pc-doctor` 输出体检报告。

> 说明：如本机已有本地 `Windows-MCP` 源码目录，可传 `-WindowsMcpDir <路径>` 直接复用；如只需安装规则与 CLI 垫片、不想拉取 `Windows-MCP`，可加 `-SkipWindowsMcp`。

### 方式 2：通过 `npx skills` 仅安装通用技能包

```bash
npx skills add yuanyeye0210-debug/universal-pc-pilot -y -g
```

### 方式 3：作为项目级规则直接使用

直接将该仓库作为工作区或子目录引入，Cursor / Codex / Claude Code / Antigravity / Cline / Windsurf 会自动读取根目录对应的规则文件。

---

## 常用命令速查

```powershell
# 1. 环境体检（含增强版 Windows-MCP 补丁与原生插件状态）
pc-doctor
pc-doctor --json

# 2. 单独部署或重打 Windows-MCP 增强补丁
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup-windows-mcp.ps1 -MergeMcpConfig

# 3. Office / WPS 静默处理
office-cli info .\report.xlsx --json
office-cli to-csv .\report.xlsx .\out.csv --sheet 1
office-cli to-pdf .\slides.pptx

# 4. 文档转 Markdown（供 Agent 秒读）
markitdown .\document.docx

# 5. 极速桌面动作链（单轮发消息 + 本地 OCR 防发错人；仅整任务结束时附带 -ReturnFocus）
fast-act -ProcessName WeChat -ActionsJson '[{"type":"key","keys":"^f"},{"type":"wait","ms":180},{"type":"paste","text":"文件传输助手"},{"type":"wait","ms":450},{"type":"key","keys":"{ENTER}"},{"type":"wait","ms":200},{"type":"assertOcr","rx":520,"ry":30,"w":500,"h":70,"contains":"文件传输助手"},{"type":"paste","text":"测试消息"},{"type":"wait","ms":60},{"type":"key","keys":"{ENTER}"}]' -ReturnFocus
```

---

## 目录结构

```text
universal-pc-pilot/
├── install.ps1 / uninstall.ps1       # 一键安装、原生插件挂载与安全卸载
├── plugin.json                       # Antigravity 原生插件清单 (v2.1.0)
├── .claude-plugin/plugin.json        # Claude Code 插件清单 (v2.1.0)
├── AGENTS.md / CLAUDE.md / GEMINI.md # 多 Agent 入口规则
├── .cursor/rules/pc-pilot.mdc        # Cursor 规则
├── .clinerules / .windsurfrules      # Cline / Windsurf 规则
├── patches/
│   └── windows-mcp-handoff.patch     # Windows-MCP 0ms 让权/重查拦截/三点隐藏指针补丁
├── rules/pc-pilot-routing.md         # 核心四层路由与人机协同铁律
├── skills/pc-pilot/                  # 通用 Agent Skill 与参考手册
├── scripts/
│   ├── setup-windows-mcp.ps1         # 增强版 Windows-MCP 自动克隆、打补丁与合并配置
│   ├── fast-act.ps1                  # 桌面动作链引擎 v2.1
│   ├── focus-caller.ps1              # 通用宿主窗口记忆与弹回
│   ├── office-cli.ps1                # Office + WPS 双引擎静默 CLI
│   ├── bootstrap-clis.ps1            # 本机软件动态探测与垫片挂载
│   └── doctor.ps1                    # 全链路体检工具 (pc-doctor)
└── templates/
    ├── windows_mcp_config.toml       # ~/.windows-mcp/config.toml 标准配置
    ├── mcp_config.universal.json     # 通用 JSON MCP 模板
    └── codex_config.universal.toml   # Codex TOML MCP 模板
```

## License

MIT
