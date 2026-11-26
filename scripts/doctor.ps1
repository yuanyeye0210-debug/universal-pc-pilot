<#
.SYNOPSIS
    pc-doctor — Universal PC Pilot v2.1.0 全链路环境体检工具。
#>
param(
    [switch]$Json
)

$ErrorActionPreference = 'SilentlyContinue'

$binDir = Join-Path $env:USERPROFILE ".local\bin"
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$inUserPath = ($userPath -split ';') -contains $binDir

# 1. 核心引擎检查
$coreEngines = @('fast-act', 'focus-caller', 'office-cli', 'pc-doctor', 'cli-hub', 'markitdown')
$engineStatus = [ordered]@{}
foreach ($e in $coreEngines) {
    $cmd = Get-Command $e -ErrorAction SilentlyContinue | Select-Object -First 1
    $engineStatus[$e] = if ($cmd) { $cmd.Source } else { $null }
}

# 2. 注册表秒查 Office / WPS COM 组件（不启动重型进程）
$comCheck = [ordered]@{
    MicrosoftWord       = Test-Path 'Registry::HKEY_CLASSES_ROOT\Word.Application'
    MicrosoftExcel      = Test-Path 'Registry::HKEY_CLASSES_ROOT\Excel.Application'
    MicrosoftPowerPoint = Test-Path 'Registry::HKEY_CLASSES_ROOT\PowerPoint.Application'
    WpsWriter           = (Test-Path 'Registry::HKEY_CLASSES_ROOT\KWPS.Application') -or (Test-Path 'Registry::HKEY_CLASSES_ROOT\WPS.Application')
    WpsSpreadsheets     = (Test-Path 'Registry::HKEY_CLASSES_ROOT\KET.Application') -or (Test-Path 'Registry::HKEY_CLASSES_ROOT\ET.Application')
    WpsPresentation     = (Test-Path 'Registry::HKEY_CLASSES_ROOT\KWPP.Application') -or (Test-Path 'Registry::HKEY_CLASSES_ROOT\WPP.Application')
}

# 3. WinRT OCR 语言可用性
$ocrLanguages = @()
try {
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    $null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
    $ocrLanguages = @([Windows.Media.Ocr.OcrEngine]::AvailableRecognizerLanguages | ForEach-Object { $_.LanguageTag })
} catch {}

# 4. 各主流 Agent 挂载状态
$antigravityPluginDir = Join-Path $env:USERPROFILE '.gemini\config\plugins\universal-pc-pilot'
$agentIntegrations = [ordered]@{
    AntigravityPlugin = (Test-Path (Join-Path $antigravityPluginDir 'plugin.json')) -and (Test-Path (Join-Path $antigravityPluginDir 'rules\pc-pilot-routing.md'))
    AntigravityRules  = Test-Path (Join-Path $env:USERPROFILE '.gemini\GEMINI.md')
    AntigravitySkill  = Test-Path (Join-Path $env:USERPROFILE '.gemini\skills\pc-pilot\SKILL.md')
    ClaudeSkill       = Test-Path (Join-Path $env:USERPROFILE '.claude\skills\pc-pilot\SKILL.md')
    CodexSkill        = Test-Path (Join-Path $env:USERPROFILE '.codex\skills\pc-pilot\SKILL.md')
    UniversalAgents   = Test-Path (Join-Path $env:USERPROFILE '.agents\skills\pc-pilot\SKILL.md')
}

# 5. 增强版 Windows-MCP 配置与补丁状态检查
$winMcpToml = Join-Path $env:USERPROFILE '.windows-mcp\config.toml'
$tomlExists = Test-Path -LiteralPath $winMcpToml
$idleTimeoutVal = $null
if ($tomlExists) {
    $tomlRaw = Get-Content -LiteralPath $winMcpToml -Raw -ErrorAction SilentlyContinue
    if ($tomlRaw -match 'idle_timeout_seconds\s*=\s*([0-9]+(?:\.[0-9]+)?)') {
        $idleTimeoutVal = [double]$Matches[1]
    }
}

$geminiMcpCfgPath = Join-Path $env:USERPROFILE '.gemini\config\mcp_config.json'
$enhancedRepoDir = $null
$mcpFlagsOk = $false
if (Test-Path -LiteralPath $geminiMcpCfgPath) {
    try {
        $mcpObj = (Get-Content -LiteralPath $geminiMcpCfgPath -Raw) | ConvertFrom-Json
        $winMcpNode = $mcpObj.mcpServers.'windows-mcp'
        if ($winMcpNode) {
            if ($winMcpNode.args) {
                $argsList = @($winMcpNode.args)
                for ($i = 0; $i -lt ($argsList.Count - 1); $i++) {
                    if ($argsList[$i] -eq '--directory') {
                        $enhancedRepoDir = $argsList[$i + 1]
                        break
                    }
                }
            }
            if ($winMcpNode.env) {
                $yieldVal = $winMcpNode.env.WINDOWS_MCP_YIELD_ON_ANY_INPUT
                $modeVal = $winMcpNode.env.WINDOWS_MCP_OVERLAY_MODE
                if ("$yieldVal" -eq "1" -and "$modeVal" -eq "spinner") {
                    $mcpFlagsOk = $true
                }
            }
        }
    } catch {}
}

if ([string]::IsNullOrWhiteSpace($enhancedRepoDir)) {
    $defaultWinMcpDir = Join-Path $env:USERPROFILE '.pc-pilot\Windows-MCP'
    if (Test-Path -LiteralPath $defaultWinMcpDir) {
        $enhancedRepoDir = $defaultWinMcpDir
    }
}

$handoffPatched = $false
if (-not [string]::IsNullOrWhiteSpace($enhancedRepoDir) -and (Test-Path -LiteralPath $enhancedRepoDir)) {
    $ctrlFile = Join-Path $enhancedRepoDir 'src\windows_mcp\desktop\control.py'
    $ovFile = Join-Path $enhancedRepoDir 'src\windows_mcp\desktop\control_overlay.py'
    if ((Test-Path -LiteralPath $ctrlFile) -and (Test-Path -LiteralPath $ovFile)) {
        $ctrlTxt = Get-Content -LiteralPath $ctrlFile -Raw -ErrorAction SilentlyContinue
        $ovTxt = Get-Content -LiteralPath $ovFile -Raw -ErrorAction SilentlyContinue
        if (($ctrlTxt -match 'yield_on_any_input') -and ($ovTxt -match 'WINDOWS_MCP_OVERLAY_MODE')) {
            $handoffPatched = $true
        }
    }
}

$windowsMcpStatus = [ordered]@{
    configTomlExists      = $tomlExists
    idleTimeoutSeconds    = $idleTimeoutVal
    enhancedRepoDir       = $enhancedRepoDir
    handoffPatchDetected  = $handoffPatched
    mcpConfigControlFlags = $mcpFlagsOk
}

# 6. 已生成垫片统计
$shimCount = 0
if (Test-Path -LiteralPath $binDir) {
    $shimCount = (Get-ChildItem -LiteralPath $binDir -Filter '*.cmd' -ErrorAction SilentlyContinue).Count
}

$report = [ordered]@{
    binDir            = $binDir
    inUserPath        = $inUserPath
    shimCount         = $shimCount
    coreEngines       = $engineStatus
    officeComEngines  = $comCheck
    winrtOcrLanguages = $ocrLanguages
    agentIntegrations = $agentIntegrations
    windowsMcp        = $windowsMcpStatus
    machineManifest   = Test-Path (Join-Path $env:USERPROFILE '.pc-pilot\MACHINE_TOOLS.md')
}

if ($Json -or ($args -contains '--json')) {
    $report | ConvertTo-Json -Depth 5
} else {
    Write-Output "=== Universal PC Pilot 环境体检报告 ==="
    Write-Output "统一入口目录: $binDir (已加入用户 PATH: $inUserPath, .cmd 垫片数: $shimCount)"
    Write-Output "`n[核心引擎]"
    foreach ($kv in $engineStatus.GetEnumerator()) {
        $mark = if ($kv.Value) { "OK -> $($kv.Value)" } else { "MISSING" }
        Write-Output "  - $($kv.Key): $mark"
    }
    Write-Output "`n[Office / WPS COM 引擎]"
    foreach ($kv in $comCheck.GetEnumerator()) {
        Write-Output "  - $($kv.Key): $($kv.Value)"
    }
    Write-Output "`n[WinRT 本地 OCR 语言]"
    Write-Output ("  - " + $(if ($ocrLanguages.Count -gt 0) { $ocrLanguages -join ', ' } else { '未检测到可用语言包' }))
    Write-Output "`n[Agent 全局挂载状态]"
    foreach ($kv in $agentIntegrations.GetEnumerator()) {
        Write-Output "  - $($kv.Key): $($kv.Value)"
    }
    Write-Output "`n[增强版 Windows-MCP 状态]"
    foreach ($kv in $windowsMcpStatus.GetEnumerator()) {
        Write-Output "  - $($kv.Key): $($kv.Value)"
    }
}
