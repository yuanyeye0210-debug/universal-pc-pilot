# Universal PC Pilot — Agent 通用操作规范 (v2.1.0)

在本项目或全局环境中操控 Windows 电脑、办公文档或开发工具链时，请优先阅读并遵循：
- 核心技能指南：[skills/pc-pilot/SKILL.md](./skills/pc-pilot/SKILL.md)
- 路由规则明细：[rules/pc-pilot-routing.md](./rules/pc-pilot-routing.md)

## 核心原则速览
1. **CLI 优先 → 垂直 MCP → 浏览器 MCP → `fast-act` / `windows-mcp` 桌面兜底**，大输出优先用 `context-mode` 本地压缩。
2. 办公文档提取用 `markitdown`，静默转 PDF / Excel 转 CSV 用 `office-cli`，当前机器已挂载的 CLI 清单见 `~/.pc-pilot/MACHINE_TOOLS.md`。
3. 需要桌面 GUI 操作时，使用增强版 `windows-mcp`（`WINDOWS_MCP_OVERLAY_MODE=spinner`、`WINDOWS_MCP_YIELD_ON_ANY_INPUT=1`、`WINDOWS_MCP_CONSENT_COUNTDOWN=0`、`WINDOWS_MCP_DISABLE_FLASH=1`，思考期显示 P 款 44px 灰白三点波浪动画并隐藏系统鼠标箭头）配合 `fast-act` 单轮批处理；勿在中间步骤传 `-ReturnFocus` 或中途弹回宿主窗口，仅任务全部完成时先 `ControlStatus(release=true)` 再弹回；优先 `readOcr` 替代全屏大图，通讯软件发消息必须带 `assertOcr` 顶栏校验；用户触碰键鼠 0ms 立即停手让权等满 2.5 秒，恢复前必须先 `Snapshot`/`Screenshot` 重查当前桌面状态再继续（未重查前底层返回 `RESCAN_REQUIRED` 硬拦截）。
4. **临时文件零残留**：过程核验截图复用单一临时路径覆盖写入，每次任务结束前必须删除全部 AI 生成的临时文件。
