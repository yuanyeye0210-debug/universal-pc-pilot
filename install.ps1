<#
.SYNOPSIS
    Universal PC Pilot v2.1.0 一键安装与跨 Agent 自动挂载脚本。
.DESCRIPTION
    1. 按需安装 cli-anything-hub 与 markitdown
    2. 动态探测本机办公/编程/AI/虚拟化软件并在 ~/.local/bin 生成无污染 CLI 垫片
    3. 部署增强版 Windows-MCP（补丁 + ~/.windows-mcp/config.toml + 即用 MCP 模板）
    4. 挂载 Antigravity 原生插件目录 (~/.gemini/config/plugins/universal-pc-pilot) 及跨 Agent 技能/规则（默认不覆盖用户 GEMINI.md）
    5. 输出即用 MCP 配置指引
    6. 运行 pc-doctor 完成全链路自检
#>
param(
    [switch]$SkipPackages,
    [switch]$SkipWindowsMcp,
    [switch]$MergeMcpConfig,
    [switch]$NoGlobalRules,
    [switch]$LegacyGeminiMd,
    [string]$WindowsMcpDir = ""
)

$ErrorActionPreference = 'Stop'

$repoRoot = $PSScriptRoot
$pcPilotHome = Join-Path $env:USERPROFILE ".pc-pilot"
if (-not (Test-Path -LiteralPath $pcPilotHome)) {
    New-Item -ItemType Directory -Path $pcPilotHome -Force | Out-Null
}
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

Write-Output "=== [1/6] 检查基础 CLI 工具链 ==="
if (-not $SkipPackages) {
    $uvCmd = Get-Command uv -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($uvCmd) {
        $prevPref = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            if (-not (Get-Command cli-hub -ErrorAction SilentlyContinue)) {
                Write-Output "正在通过 uv 安装 cli-anything-hub (含 pip)..."
                & $uvCmd.Source tool install --with pip cli-anything-hub
            } else {
                Write-Output "已存在 cli-hub，跳过安装。"
            }
            if (-not (Get-Command markitdown -ErrorAction SilentlyContinue)) {
                Write-Output "正在通过 uv 安装 markitdown..."
                & $uvCmd.Source tool install "markitdown[docx,pptx,xlsx,pdf]"
            } else {
                Write-Output "已存在 markitdown，跳过安装。"
            }
        } finally {
            $ErrorActionPreference = $prevPref
        }
    } else {
        Write-Warning "未检测到 uv，跳过自动安装 cli-hub 与 markitdown（可先安装 uv 后重试）。"
    }
} else {
    Write-Output "已指定 -SkipPackages，跳过包安装。"
}

Write-Output "`n=== [2/6] 动态探测并挂载本机 CLI 垫片 ==="
$bootstrapScript = Join-Path $repoRoot "scripts\bootstrap-clis.ps1"
$manifestPath = Join-Path $pcPilotHome "MACHINE_TOOLS.md"
& $bootstrapScript -OutputDoc $manifestPath

Write-Output "`n=== [3/6] 部署增强版 Windows-MCP 与协同配置文件 ==="
$setupWinMcpScript = Join-Path $repoRoot "scripts\setup-windows-mcp.ps1"
$mcpReady = Join-Path $pcPilotHome "mcp_config.ready.json"
$codexReady = Join-Path $pcPilotHome "codex_config.ready.toml"
if (-not $SkipWindowsMcp -and (Test-Path -LiteralPath $setupWinMcpScript)) {
    $setupParams = @{}
    if (-not [string]::IsNullOrWhiteSpace($WindowsMcpDir)) {
        $setupParams['SourceDir'] = $WindowsMcpDir
    }
    if ($MergeMcpConfig) {
        $setupParams['MergeMcpConfig'] = $true
    }
    & $setupWinMcpScript @setupParams
} else {
    Write-Output "已跳过 Windows-MCP 仓库克隆/打补丁，仅写入通用配置模板..."
    $winMcpCfgDir = Join-Path $env:USERPROFILE ".windows-mcp"
    if (-not (Test-Path -LiteralPath $winMcpCfgDir)) {
        New-Item -ItemType Directory -Path $winMcpCfgDir -Force | Out-Null
    }
    Copy-Item -LiteralPath (Join-Path $repoRoot "templates\windows_mcp_config.toml") -Destination (Join-Path $winMcpCfgDir "config.toml") -Force
    Copy-Item -LiteralPath (Join-Path $repoRoot "templates\mcp_config.universal.json") -Destination $mcpReady -Force
    Copy-Item -LiteralPath (Join-Path $repoRoot "templates\codex_config.universal.toml") -Destination $codexReady -Force
}

Write-Output "`n=== [4/6] 挂载 Antigravity 原生插件与跨 Agent 技能/规则 ==="
$skillSrc = Join-Path $repoRoot "skills\pc-pilot"

# 4.1 挂载为标准 Antigravity 原生插件（不含 mcp_config.json，避免拉起双份 windows-mcp）
$geminiDir = Join-Path $env:USERPROFILE ".gemini"
if (Test-Path -LiteralPath $geminiDir) {
    $pluginDir = Join-Path $geminiDir "config\plugins\universal-pc-pilot"
    if (Test-Path -LiteralPath $pluginDir) {
        Remove-Item -LiteralPath $pluginDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path (Join-Path $pluginDir "rules") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $pluginDir "skills") -Force | Out-Null

    Copy-Item -LiteralPath (Join-Path $repoRoot "plugin.json") -Destination (Join-Path $pluginDir "plugin.json") -Force
    Copy-Item -LiteralPath (Join-Path $repoRoot "rules\pc-pilot-routing.md") -Destination (Join-Path $pluginDir "rules\pc-pilot-routing.md") -Force
    Copy-Item -LiteralPath $skillSrc -Destination (Join-Path $pluginDir "skills\pc-pilot") -Recurse -Force
    Write-Output "Mounted Antigravity native plugin -> $pluginDir"

    # 可选：仅当显式指定 -LegacyGeminiMd 时，才用区块标记安全合并进 ~/.gemini/GEMINI.md（绝不覆盖用户自有守则）
    if ($LegacyGeminiMd -and -not $NoGlobalRules) {
        $geminiMd = Join-Path $geminiDir "GEMINI.md"
        $bakMd = Join-Path $geminiDir "GEMINI.md.bak-pc-pilot"
        if ((Test-Path -LiteralPath $geminiMd) -and -not (Test-Path -LiteralPath $bakMd)) {
            Copy-Item -LiteralPath $geminiMd -Destination $bakMd -Force
        }
        $startMarker = "<!-- UNIVERSAL-PC-PILOT:START -->"
        $endMarker = "<!-- UNIVERSAL-PC-PILOT:END -->"
        $routingText = [System.IO.File]::ReadAllText((Join-Path $repoRoot "rules\pc-pilot-routing.md"), $utf8NoBom).Trim()
        $block = "$startMarker`r`n$routingText`r`n$endMarker"

        $existingMd = if (Test-Path -LiteralPath $geminiMd) { [System.IO.File]::ReadAllText($geminiMd, $utf8NoBom) } else { "" }
        $pattern = "(?s)" + [regex]::Escape($startMarker) + ".*?" + [regex]::Escape($endMarker)
        if ($existingMd -match $pattern) {
            $merged = [regex]::Replace($existingMd, $pattern, $block)
        } elseif ([string]::IsNullOrWhiteSpace($existingMd)) {
            $merged = $block
        } else {
            $merged = $existingMd.TrimEnd() + "`r`n`r`n---`r`n`r`n" + $block
        }
        [System.IO.File]::WriteAllText($geminiMd, $merged + "`r`n", $utf8NoBom)
        Write-Output "Merged marked rule block into -> $geminiMd"
    }
}

# 4.2 同步标准 skills 目录（兼容各 Agent 的技能发现与旧版路径引用）
$agentSkillTargets = @(
    @{ Name = 'Antigravity'; Root = (Join-Path $env:USERPROFILE '.gemini'); Skills = (Join-Path $env:USERPROFILE '.gemini\skills\pc-pilot') },
    @{ Name = 'ClaudeCode';  Root = (Join-Path $env:USERPROFILE '.claude'); Skills = (Join-Path $env:USERPROFILE '.claude\skills\pc-pilot') },
    @{ Name = 'Codex';       Root = (Join-Path $env:USERPROFILE '.codex');  Skills = (Join-Path $env:USERPROFILE '.codex\skills\pc-pilot') },
    @{ Name = 'Universal';   Root = (Join-Path $env:USERPROFILE '.agents'); Skills = (Join-Path $env:USERPROFILE '.agents\skills\pc-pilot') }
)

foreach ($t in $agentSkillTargets) {
    if ((Test-Path -LiteralPath $t.Root) -or $t.Name -eq 'Universal') {
        $parentSkill = Split-Path -Parent $t.Skills
        if (-not (Test-Path -LiteralPath $parentSkill)) { New-Item -ItemType Directory -Path $parentSkill -Force | Out-Null }
        if (Test-Path -LiteralPath $t.Skills) { Remove-Item -LiteralPath $t.Skills -Recurse -Force }
        Copy-Item -LiteralPath $skillSrc -Destination $t.Skills -Recurse -Force
        Write-Output "Mounted skill [$($t.Name)] -> $($t.Skills)"
    }
}

$cursorDir = Join-Path $env:USERPROFILE ".cursor"
if (Test-Path -LiteralPath $cursorDir) {
    $cursorRules = Join-Path $cursorDir "rules"
    if (-not (Test-Path -LiteralPath $cursorRules)) { New-Item -ItemType Directory -Path $cursorRules -Force | Out-Null }
    Copy-Item -LiteralPath (Join-Path $repoRoot ".cursor\rules\pc-pilot.mdc") -Destination (Join-Path $cursorRules "pc-pilot.mdc") -Force
    Write-Output "Mounted Cursor rule -> $cursorRules\pc-pilot.mdc"
}

Write-Output "`n=== [5/6] 就绪 MCP 配置输出 ==="
Write-Output "JSON 模板（Antigravity / Cursor / Claude Code）: $mcpReady"
Write-Output "TOML 模板（OpenAI Codex）: $codexReady"
if (-not $MergeMcpConfig) {
    Write-Output "提示：如需自动把增强版 windows-mcp 合并进本机 mcp_config.json，可附加参数 -MergeMcpConfig 重跑 install.ps1。"
}

Write-Output "`n=== [6/6] 运行全链路体检 (pc-doctor) ==="
$doctorScript = Join-Path $repoRoot "scripts\doctor.ps1"
& $doctorScript
