# AI Agent 全自动一键安装指令（AI_INSTALL v2.1.0）

> 本文档专为 **AI Coding / Desktop Agent**（Google Antigravity、Claude Code、OpenAI Codex、Cursor、Windsurf、Cline、Roo Code、OpenClaw 等）编写。  
> **执行原则**：当用户要求你安装、升级或启用 `Universal PC Pilot` 时，请直接自主顺序执行以下步骤，**无需反复向用户确认基础安装命令**。

---

## 第一步：克隆或更新仓库并执行一键安装（PowerShell）

在你的终端工具中执行以下 PowerShell 命令（包含 `cli-hub`、`markitdown`、`fast-act`、`Windows-MCP` 增强补丁部署、Antigravity 原生插件挂载及自动 MCP 合并）：

```powershell
# 1. 克隆或更新仓库到用户目录 ~/.pc-pilot/repo
$repoDir = Join-Path $env:USERPROFILE ".pc-pilot\repo"
if (Test-Path (Join-Path $repoDir ".git")) {
  git -C $repoDir pull
} else {
  git clone https://github.com/yuanyeye0210-debug/universal-pc-pilot.git $repoDir
}

# 2. 一键安装 CLI 工具链、部署增强版 Windows-MCP 补丁、挂载原生插件与跨 Agent 规则，并安全合并 MCP 配置
powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoDir "install.ps1") -MergeMcpConfig

# 3. 运行全链路 JSON 体检，确认所有引擎、原生插件与 windowsMcp 补丁状态均为 true / OK
& (Join-Path $env:USERPROFILE ".local\bin\pc-doctor.cmd") --json
```

> 说明：
> - `-MergeMcpConfig` 会在保留用户原有全部其他 MCP 服务器的前提下，将 `~/.gemini/config/mcp_config.json` 与 `~/.cursor/mcp.json` 中的 `windows-mcp` 指向本地已打补丁的 `~/.pc-pilot/Windows-MCP`（带备份 `.bak-pc-pilot`）；
> - `install.ps1` 会将插件挂载至 Antigravity 原生插件目录 `~/.gemini/config/plugins/universal-pc-pilot/`，**绝不覆盖用户既有的 `~/.gemini/GEMINI.md` 个人守则**；
> - 如需复用用户本机已存在的 `Windows-MCP` 源码目录，可追加 `-WindowsMcpDir <目录路径>`。

---

## 第二步：核对其他端 MCP 配置（不覆盖用户现有配置）

安装完成后，脚本会按本机真实路径生成即用配置文件：
- JSON 格式：`~/.pc-pilot/mcp_config.ready.json`（含本地增强版 `windows-mcp`、`playwright-edge`、`context-mode`）
- TOML 格式：`~/.pc-pilot/codex_config.ready.toml`（供 OpenAI Codex 使用）
- Windows-MCP 控制参数：`~/.windows-mcp/config.toml`（`idle_timeout_seconds = 2.5`、`consent_countdown_seconds = 0`、`mouse_takeover_units = 40`）

若你当前运行的宿主不是 Antigravity 或 Cursor，请**在保留用户原有其他 MCP 服务器的前提下**，从上述就绪文件补全配置：

- **Google Antigravity**：`$env:USERPROFILE\.gemini\config\mcp_config.json`（传 `-MergeMcpConfig` 时已自动合并）
- **Cursor**：`$env:USERPROFILE\.cursor\mcp.json`（传 `-MergeMcpConfig` 时已自动合并）
- **Claude Code**：`$env:USERPROFILE\.claude.json`（或项目根目录 `.mcp.json`）
- **OpenAI Codex**：`$env:USERPROFILE\.codex\config.toml`

> 注意：若你的宿主环境运行在受限沙盒终端中（执行 `Get-Process | Where-Object MainWindowHandle -ne 0` 返回为空），则：
> - 普通 CLI（`office-cli`、`markitdown`、`cli-hub`、`git`、`gh` 等）直接走你的原生终端执行；
> - 桌面窗口操控脚本（`fast-act`、`focus-caller`）必须通过 `windows-mcp` 的 `PowerShell` 工具在交互式桌面会话中调用。

---

## 第三步：读取工具清单与规则开始工作

安装完成后，你可以直接读取以下文件掌握当前电脑的完整能力：
1. 本机实测探测到的全部 CLI 清单：`$env:USERPROFILE\.pc-pilot\MACHINE_TOOLS.md`
2. 路由与人机协同铁律：`$env:USERPROFILE\.pc-pilot\repo\rules\pc-pilot-routing.md`
3. 完整技能与 `fast-act` 参数手册：`$env:USERPROFILE\.pc-pilot\repo\skills\pc-pilot\SKILL.md`
4. 随后向用户汇报 `pc-doctor --json` 体检结果，并提示重启或重连 `windows-mcp`（使增强版补丁与原生插件立即生效）。
