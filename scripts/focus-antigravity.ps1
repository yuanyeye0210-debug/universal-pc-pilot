<#
.SYNOPSIS
    向下兼容入口：调用通用 focus-caller.ps1 唤起 Antigravity 或当前宿主 Agent 窗口。
#>
param(
    [int64]$TargetHwnd = 0,
    [string]$TargetProcess = ""
)

$callerScript = Join-Path $PSScriptRoot "focus-caller.ps1"
if (Test-Path -LiteralPath $callerScript) {
    & $callerScript -TargetHwnd $TargetHwnd -TargetProcess $TargetProcess -FallbackProcesses @('Antigravity', 'Cursor', 'Windsurf', 'Trae', 'WindowsTerminal', 'Code')
}
