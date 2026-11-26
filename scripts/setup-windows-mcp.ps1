<#
.SYNOPSIS
    setup-windows-mcp.ps1 — 自动部署或打补丁升级增强版 Windows-MCP（支持 0ms 触碰让权、2.5s 强制重查、P 款三点隐藏系统指针）。
.DESCRIPTION
    1. 写入或更新 ~/.windows-mcp/config.toml（idle_timeout_seconds=2.5, consent_countdown_seconds=0, mouse_takeover_units=40）。
    2. 复用 -SourceDir 或自动克隆 CursorTouch/Windows-MCP@dba6528 到 ~/.pc-pilot/Windows-MCP，并应用 patches/windows-mcp-handoff.patch。
    3. 按需执行 uv sync 完成依赖安装。
    4. 生成指向本地增强版 Windows-MCP 目录的 ~/.pc-pilot/mcp_config.ready.json 与 ~/.pc-pilot/codex_config.ready.toml。
    5. 若指定 -MergeMcpConfig，则安全合并到本机已有 ~/.gemini/config/mcp_config.json 与 ~/.cursor/mcp.json（保留其他全部 MCP 服务器）。
#>
param(
    [string]$InstallDir = (Join-Path $env:USERPROFILE ".pc-pilot\Windows-MCP"),
    [string]$SourceDir = "",
    [switch]$SkipSync,
    [switch]$MergeMcpConfig,
    [switch]$ForceReapplyPatch
)

$ErrorActionPreference = 'Stop'

$UpstreamRepo = "https://github.com/CursorTouch/Windows-MCP.git"
$BaseCommit = "dba65286242b93ec37a472dd4a8845fe156e80e5"

$repoRoot = Split-Path -Parent $PSScriptRoot
$pcPilotHome = Join-Path $env:USERPROFILE ".pc-pilot"
if (-not (Test-Path -LiteralPath $pcPilotHome)) {
    New-Item -ItemType Directory -Path $pcPilotHome -Force | Out-Null
}

$patchFile = Join-Path $repoRoot "patches\windows-mcp-handoff.patch"
$tomlTemplate = Join-Path $repoRoot "templates\windows_mcp_config.toml"
if (-not (Test-Path -LiteralPath $patchFile)) {
    throw "未找到 Windows-MCP 补丁文件: $patchFile"
}
if (-not (Test-Path -LiteralPath $tomlTemplate)) {
    throw "未找到 Windows-MCP 配置模板: $tomlTemplate"
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Invoke-NativeCommand {
    <#
    .SYNOPSIS
        安全调用外部命令行工具（避免 git/uv 进度信息写到 stderr 导致终止异常）。
    #>
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @(),
        [string]$WorkingDirectory = ""
    )
    $prevPref = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
            Push-Location $WorkingDirectory
        }
        & $FilePath @Arguments
        $code = $LASTEXITCODE
        if ($code -ne 0) {
            throw "命令执行失败 (exit=$code): $FilePath $($Arguments -join ' ')"
        }
    } finally {
        if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
            Pop-Location
        }
        $ErrorActionPreference = $prevPref
    }
}

# 1. 写入 ~/.windows-mcp/config.toml
$winMcpConfigDir = Join-Path $env:USERPROFILE ".windows-mcp"
$winMcpConfigPath = Join-Path $winMcpConfigDir "config.toml"
$winMcpConfigBak = Join-Path $winMcpConfigDir "config.toml.bak-pc-pilot"
if (-not (Test-Path -LiteralPath $winMcpConfigDir)) {
    New-Item -ItemType Directory -Path $winMcpConfigDir -Force | Out-Null
}
if ((Test-Path -LiteralPath $winMcpConfigPath) -and -not (Test-Path -LiteralPath $winMcpConfigBak)) {
    Copy-Item -LiteralPath $winMcpConfigPath -Destination $winMcpConfigBak -Force
}
$tomlContent = [System.IO.File]::ReadAllText($tomlTemplate, $utf8NoBom)
[System.IO.File]::WriteAllText($winMcpConfigPath, $tomlContent, $utf8NoBom)
Write-Output "Updated Windows-MCP config -> $winMcpConfigPath"

# 2. 确定目标 Windows-MCP 仓库目录并克隆基线
$targetDir = if (-not [string]::IsNullOrWhiteSpace($SourceDir)) { $SourceDir } else { $InstallDir }
$gitCmd = Get-Command git -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $gitCmd) {
    throw "未检测到 git，无法克隆或打补丁升级 Windows-MCP。"
}

if (-not (Test-Path -LiteralPath (Join-Path $targetDir ".git"))) {
    $parentDir = Split-Path -Parent $targetDir
    if ($parentDir -and -not (Test-Path -LiteralPath $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }
    Write-Output "正在克隆 CursorTouch/Windows-MCP 到 $targetDir ..."
    Invoke-NativeCommand -FilePath $gitCmd.Source -Arguments @("clone", $UpstreamRepo, $targetDir)
    Invoke-NativeCommand -FilePath $gitCmd.Source -Arguments @("-C", $targetDir, "checkout", $BaseCommit)
}

# 3. 检测并应用人机协同补丁
$controlPy = Join-Path $targetDir "src\windows_mcp\desktop\control.py"
$overlayArtPy = Join-Path $targetDir "src\windows_mcp\desktop\control_overlay_art.py"
$patchApplied = $false
if ((Test-Path -LiteralPath $controlPy) -and (Test-Path -LiteralPath $overlayArtPy)) {
    $controlText = [System.IO.File]::ReadAllText($controlPy, $utf8NoBom)
    $overlayArtText = [System.IO.File]::ReadAllText($overlayArtPy, $utf8NoBom)
    if (($controlText -match 'yield_on_any_input') -and ($overlayArtText -match 'def _spinner_frames\(')) {
        $patchApplied = $true
    }
}

if ($patchApplied -and -not $ForceReapplyPatch) {
    Write-Output "PatchAlreadyApplied -> $targetDir"
} else {
    if ($ForceReapplyPatch) {
        Write-Output "ForceReapplyPatch: 正在还原至基线 commit $BaseCommit ..."
        Invoke-NativeCommand -FilePath $gitCmd.Source -Arguments @("-C", $targetDir, "checkout", "--", ".")
        Invoke-NativeCommand -FilePath $gitCmd.Source -Arguments @("-C", $targetDir, "checkout", $BaseCommit)
    }
    Invoke-NativeCommand -FilePath $gitCmd.Source -Arguments @("-C", $targetDir, "apply", "--check", $patchFile)
    Invoke-NativeCommand -FilePath $gitCmd.Source -Arguments @("-C", $targetDir, "apply", $patchFile)
    Write-Output "Applied handoff patch -> $targetDir"
}

# 4. 运行 uv sync 安装依赖
if (-not $SkipSync) {
    $uvCmd = Get-Command uv -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($uvCmd) {
        Write-Output "正在执行 uv sync ..."
        Invoke-NativeCommand -FilePath $uvCmd.Source -Arguments @("sync") -WorkingDirectory $targetDir
    } else {
        Write-Warning "未检测到 uv，跳过 uv sync（请先安装 uv 后在 $targetDir 执行 uv sync）。"
    }
} else {
    Write-Output "已指定 -SkipSync，跳过 uv sync。"
}

# 5. 生成指向本地增强版目录的 MCP 配置模板
$resolvedTargetDir = (Resolve-Path -LiteralPath $targetDir).Path
$winMcpServerSpec = [ordered]@{
    command = "uv"
    args    = @(
        "--directory",
        $resolvedTargetDir,
        "run",
        "windows-mcp",
        "serve",
        "--control",
        "--control-idle-timeout",
        "2.5",
        "--control-policy",
        "balanced"
    )
    env     = [ordered]@{
        WINDOWS_MCP_DISABLE_FLASH     = "1"
        WINDOWS_MCP_OVERLAY_MODE      = "spinner"
        WINDOWS_MCP_YIELD_ON_ANY_INPUT = "1"
        WINDOWS_MCP_CONSENT_COUNTDOWN = "0"
    }
}

$readyJsonObj = [ordered]@{
    mcpServers = [ordered]@{
        "windows-mcp"     = $winMcpServerSpec
        "playwright-edge" = [ordered]@{
            command = "npx"
            args    = @("-y", "@playwright/mcp@latest", "--browser", "msedge")
        }
        "context-mode"    = [ordered]@{
            command = "npx"
            args    = @("-y", "context-mode", "server")
        }
    }
}
$mcpReadyPath = Join-Path $pcPilotHome "mcp_config.ready.json"
[System.IO.File]::WriteAllText($mcpReadyPath, ($readyJsonObj | ConvertTo-Json -Depth 10), $utf8NoBom)
Write-Output "Ready MCP JSON -> $mcpReadyPath"

# 使用单引号字面量写 Windows 路径，避免 TOML 转义错误
$tomlDirLiteral = $resolvedTargetDir.Replace("'", "''")
$codexReadyContent = @"
# Universal PC Pilot v2.1.0 — OpenAI Codex 本地增强版 MCP 配置
# 由 setup-windows-mcp.ps1 自动生成，可直接合并至 ~/.codex/config.toml

[mcp_servers.windows-mcp]
command = "uv"
args = ["--directory", '$tomlDirLiteral', "run", "windows-mcp", "serve", "--control", "--control-idle-timeout", "2.5", "--control-policy", "balanced"]

[mcp_servers.windows-mcp.env]
WINDOWS_MCP_DISABLE_FLASH = "1"
WINDOWS_MCP_OVERLAY_MODE = "spinner"
WINDOWS_MCP_YIELD_ON_ANY_INPUT = "1"
WINDOWS_MCP_CONSENT_COUNTDOWN = "0"

[mcp_servers.playwright-edge]
command = "npx"
args = ["-y", "@playwright/mcp@latest", "--browser", "msedge"]

[mcp_servers.context-mode]
command = "npx"
args = ["-y", "context-mode", "server"]
"@
$codexReadyPath = Join-Path $pcPilotHome "codex_config.ready.toml"
[System.IO.File]::WriteAllText($codexReadyPath, $codexReadyContent, $utf8NoBom)
Write-Output "Ready Codex TOML -> $codexReadyPath"

# 6. 按需安全合并进本机已存在的 MCP 配置
if ($MergeMcpConfig) {
    $mcpTargets = @(
        (Join-Path $env:USERPROFILE ".gemini\config\mcp_config.json"),
        (Join-Path $env:USERPROFILE ".cursor\mcp.json")
    )
    foreach ($cfgPath in $mcpTargets) {
        if (Test-Path -LiteralPath $cfgPath) {
            $bakPath = "$cfgPath.bak-pc-pilot"
            if (-not (Test-Path -LiteralPath $bakPath)) {
                Copy-Item -LiteralPath $cfgPath -Destination $bakPath -Force
            }
            $raw = [System.IO.File]::ReadAllText($cfgPath, $utf8NoBom)
            $cfgObj = if ([string]::IsNullOrWhiteSpace($raw)) { [PSCustomObject]@{} } else { $raw | ConvertFrom-Json }
            if (-not ($cfgObj.PSObject.Properties.Name -contains 'mcpServers') -or $null -eq $cfgObj.mcpServers) {
                $cfgObj | Add-Member -NotePropertyName 'mcpServers' -NotePropertyValue ([PSCustomObject]@{}) -Force
            }
            $cfgObj.mcpServers | Add-Member -NotePropertyName 'windows-mcp' -NotePropertyValue ([PSCustomObject]$winMcpServerSpec) -Force
            [System.IO.File]::WriteAllText($cfgPath, ($cfgObj | ConvertTo-Json -Depth 10), $utf8NoBom)
            Write-Output "Merged windows-mcp into -> $cfgPath"
        }
    }
}
