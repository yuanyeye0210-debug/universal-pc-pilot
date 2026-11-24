# AI Agent 全自动一键安装指令（AI_INSTALL）

> 本文档专为 **AI Coding / Desktop Agent**（Google Antigravity、Claude Code、OpenAI Codex、Cursor、Windsurf、Cline、Roo Code、OpenClaw 等）编写。  
> **执行原则**：当用户要求你安装或启用 `Universal PC Pilot` 时，请直接自主顺序执行以下步骤，**无需反复向用户确认基础安装命令**。

---

## 第一步：克隆仓库并执行一键安装脚本（PowerShell）

在你的终端工具中执行以下 PowerShell 命令：

```powershell
# 1. 克隆或更新仓库到用户目录 ~/.pc-pilot/repo
$repoDir = Join-Path $env:USERPROFILE ".pc-pilot\repo"
if (Test-Path (Join-Path $repoDir ".git")) {
  git -C $repoDir pull
} else {
  git clone https://github.com/yuanyeye0210-debug/universal-pc-pilot.git $repoDir
}

# 2. 一键安装 CLI 工具链 (cli-hub / markitdown)、自动探测本机软件垫片、部署跨 Agent 规则与 Skill
powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoDir "install.ps1")

# 3. 运行全链路 JSON 体检，确认所有引擎与 Agent 挂载状态均为 true / OK
& (Join-Path $env:USERPROFILE ".local\bin\pc-doctor.cmd") --json
```

---

## 第二步：自动合并通用 MCP 配置（不覆盖用户现有配置）

安装完成后，本插件会在 `$env:USERPROFILE\.pc-pilot\mcp_config.ready.json` 生成即拷即用的通用 MCP 模板（包含 `windows-mcp` 无边框静默参数、`playwright-edge`、`context-mode`；Codex TOML 模板位于 `$env:USERPROFILE\.pc-pilot\repo\templates\codex_config.universal.toml`）。

请检查当前运行环境的 MCP 配置文件，**在保留用户原有所有其他 MCP 服务器的前提下**，按需补全缺失的 `windows-mcp`、`playwright-edge`、`context-mode`：

- **Google Antigravity**：`$env:USERPROFILE\.gemini\config\mcp_config.json`
- **Cursor**：`$env:USERPROFILE\.cursor\mcp.json`
- **Claude Code**：`$env:USERPROFILE\.claude.json`（或项目根目录 `.mcp.json`）
- **OpenAI Codex**：`$env:USERPROFILE\.codex\config.toml`

> 注意：若你的宿主环境运行在受限沙盒终端中（执行 `Get-Process | Where-Object MainWindowHandle -ne 0` 返回为空），则：
> - 普通 CLI（`office-cli`、`markitdown`、`cli-hub`、`git`、`gh` 等）直接走你的原生终端执行；
> - 桌面窗口操控脚本（`fast-act`、`focus-caller`）必须通过 `windows-mcp` 的 `PowerShell` 工具在交互式桌面会话中调用。

---

## 第三步：读取工具清单与规则开始工作

安装完成后，你可以直接读取以下文件掌握当前电脑的完整能力：
1. 本机实测探测到的全部 CLI 清单：`$env:USERPROFILE\.pc-pilot\MACHINE_TOOLS.md`
2. 完整路由与 `fast-act` 参考手册：`$env:USERPROFILE\.pc-pilot\repo\skills\pc-pilot\SKILL.md`
3. 随后直接向用户汇报 `pc-doctor --json` 体检结果与已就绪的能力即可。
