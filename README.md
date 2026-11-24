# Universal PC Pilot (全通用电脑极速操控与 CLI + MCP 协同引擎)

> 让市面上**所有主流 AI Agent**（Google Antigravity、Claude Code、OpenAI Codex、Cursor、Windsurf、Cline、Roo Code、OpenClaw 等）在任何 Windows 电脑上**拿到就能直接用**的 CLI 优先 + MCP 协同 + 亚秒级桌面操控插件。

---

## 给 AI Agent 的全自动安装指令

把下面这句话直接发给任意 AI Agent，它就会自己读完文档并一键装好：

> 请读取 `https://raw.githubusercontent.com/yuanyeye0210-debug/universal-pc-pilot/main/AI_INSTALL.md` 并按照里面的步骤在我的电脑上全自动完成安装、MCP 配置合并与 `pc-doctor` 体检。

---

## 核心解决什么问题？

1. **拒绝慢吞吞的盲点截图**：建立「**原生 CLI（最高优先级）→ 垂直 MCP → 浏览器 MCP → 桌面 GUI 兜底**」四层漏斗，能用命令行 0.1 秒解决的绝不截图点鼠标。
2. **换台电脑也能自动识别本机软件**：自动扫描当前电脑已安装的办公、编程、AI、虚拟化软件（Office / WPS / VS MSBuild / PyCharm / Conda / Ollama / 7-Zip / VMware / VirtualBox / 微信开发者工具等），无污染挂载到 `~/.local/bin` 并生成当前机器专属工具清单。
3. **国产 WPS + 微软 Office 双引擎静默办公 CLI**：内置 `office-cli`，无需打开窗口即可后台静默将 Word / Excel / PPT 导出为 PDF（`to-pdf`）、Excel 转 CSV（`to-csv`）、读取文档结构（`info`）。
4. **亚秒级 Win32 + UIA + WinRT 本地 OCR 桌面动作链（`fast-act` v2.0）**：
   - 自动记忆调用方宿主窗口句柄，无论你在 Antigravity、Claude Code、Codex 还是 Cursor 中调用，操控完都能自动置顶弹回原窗口；
   - 支持 `assertOcr`（50ms 本地顶栏校验，通讯软件发消息 100% 防发错人）与 `readOcr`（免传大图直接返回纯文本）；
   - 支持 `scroll`、`drag`、`clickName`、`focusPopup`、STA 安全全类型剪贴板保护，以及 2.5 秒硬件级人机协同让权。
5. **一仓多端原生兼容**：同时内置 `SKILL.md`（`npx skills add` 通用标准）、`plugin.json`（Antigravity）、`.claude-plugin/plugin.json`（Claude Code）、`AGENTS.md`（Codex）、`CLAUDE.md`、`GEMINI.md`、`.cursor/rules/pc-pilot.mdc`、`.clinerules`、`.windsurfrules`。

---

## 快速开始（拿到就能用）

### 方式 1：完整一键安装（推荐，适用于任意 Windows 电脑）

```powershell
git clone https://github.com/yuanyeye0210-debug/universal-pc-pilot.git
cd universal-pc-pilot
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

安装完成后会自动：
- 安装 `cli-hub`（`cli-anything-hub`）与 `markitdown`；
- 扫描本机已装软件并在 `~/.local/bin` 生成 `.cmd` 垫片（不污染全局 `PATH`）；
- 为本机已存在的 Antigravity / Claude Code / Codex / Cursor / `.agents` 自动挂载规则与技能；
- 输出本机工具清单 `~/.pc-pilot/MACHINE_TOOLS.md` 与 MCP 模板 `~/.pc-pilot/mcp_config.ready.json`；
- 运行 `pc-doctor` 输出体检报告。

### 方式 2：通过 `npx skills` 仅安装通用技能包

```bash
npx skills add yuanyeye0210-debug/universal-pc-pilot -y -g
```

### 方式 3：作为项目级规则直接使用

直接将该仓库作为工作区或子目录引入，Cursor / Codex / Claude Code / Antigravity / Cline / Windsurf 会自动读取根目录对应的规则文件。

---

## 常用命令速查

```powershell
# 1. 环境体检
pc-doctor
pc-doctor --json

# 2. Office / WPS 静默处理
office-cli info .\report.xlsx --json
office-cli to-csv .\report.xlsx .\out.csv --sheet 1
office-cli to-pdf .\slides.pptx

# 3. 文档转 Markdown（供 Agent 秒读）
markitdown .\document.docx

# 4. 极速桌面动作链（带本地 OCR 防发错人 + 自动弹回原 Agent）
fast-act -ProcessName WeChat -ActionsJson '[{"type":"key","keys":"^f"},{"type":"wait","ms":180},{"type":"paste","text":"文件传输助手"},{"type":"wait","ms":450},{"type":"key","keys":"{ENTER}"},{"type":"wait","ms":200},{"type":"assertOcr","rx":520,"ry":30,"w":500,"h":70,"contains":"文件传输助手"},{"type":"paste","text":"测试消息"},{"type":"wait","ms":60},{"type":"key","keys":"{ENTER}"}]' -ReturnFocus
```

---

## 目录结构

```text
universal-pc-pilot/
├── install.ps1 / uninstall.ps1       # 一键安装与安全卸载
├── plugin.json                       # Antigravity 插件清单
├── .claude-plugin/plugin.json        # Claude Code 插件清单
├── AGENTS.md / CLAUDE.md / GEMINI.md # 多 Agent 入口规则
├── .cursor/rules/pc-pilot.mdc        # Cursor 规则
├── .clinerules / .windsurfrules      # Cline / Windsurf 规则
├── rules/pc-pilot-routing.md         # 核心四层路由规则
├── skills/pc-pilot/                  # 通用 Agent Skill 与参考手册
├── scripts/
│   ├── fast-act.ps1                  # 桌面动作链引擎 v2.0
│   ├── focus-caller.ps1              # 通用宿主窗口记忆与弹回
│   ├── office-cli.ps1                # Office + WPS 双引擎静默 CLI
│   ├── bootstrap-clis.ps1            # 本机软件动态探测与垫片挂载
│   └── doctor.ps1                    # 全链路体检工具 (pc-doctor)
└── templates/                        # 通用 MCP 配置模板 (JSON / TOML)
```

## License

MIT
