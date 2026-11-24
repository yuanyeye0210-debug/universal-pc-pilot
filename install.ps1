<#
.SYNOPSIS
    Universal PC Pilot 一键安装与跨 Agent 自动挂载脚本。
.DESCRIPTION
    1. 按需安装 cli-anything-hub 与 markitdown
    2. 动态探测本机办公/编程/AI/虚拟化软件并在 ~/.local/bin 生成无污染 CLI 垫片
    3. 自动识别本机已安装的通用 Agent (~/.gemini, ~/.claude, ~/.codex, ~/.cursor, ~/.agents) 并挂载技能与全局规则
    4. 生成即拷即用的 MCP 配置模板 ~/.pc-pilot/mcp_config.ready.json
    5. 运行 pc-doctor 完成全链路自检
#>
param(
    [switch]$SkipPackages,
    [switch]$NoGlobalRules
)

$ErrorActionPreference = 'Stop'

$repoRoot = $PSScriptRoot
$pcPilotHome = Join-Path $env:USERPROFILE ".pc-pilot"
if (-not (Test-Path -LiteralPath $pcPilotHome)) {
    New-Item -ItemType Directory -Path $pcPilotHome -Force | Out-Null
}

Write-Output "=== [1/5] 检查基础 CLI 工具链 ==="
if (-not $SkipPackages) {
    $uvCmd = Get-Command uv -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($uvCmd) {
        if (-not (Get-Command cli-hub -ErrorAction SilentlyContinue)) {
            Write-Output "正在通过 uv 安装 cli-anything-hub (含 pip)..."
            uv tool install --with pip cli-anything-hub
        } else {
            Write-Output "已存在 cli-hub，跳过安装。"
        }
        if (-not (Get-Command markitdown -ErrorAction SilentlyContinue)) {
            Write-Output "正在通过 uv 安装 markitdown..."
            uv tool install "markitdown[docx,pptx,xlsx,pdf]"
        } else {
            Write-Output "已存在 markitdown，跳过安装。"
        }
    } else {
        Write-Warning "未检测到 uv，跳过自动安装 cli-hub 与 markitdown（可先安装 uv 后重试）。"
    }
} else {
    Write-Output "已指定 -SkipPackages，跳过包安装。"
}

Write-Output "`n=== [2/5] 动态探测并挂载本机 CLI 垫片 ==="
$bootstrapScript = Join-Path $repoRoot "scripts\bootstrap-clis.ps1"
$manifestPath = Join-Path $pcPilotHome "MACHINE_TOOLS.md"
& $bootstrapScript -OutputDoc $manifestPath

Write-Output "`n=== [3/5] 挂载跨 Agent 技能与全局规则 ==="
$skillSrc = Join-Path $repoRoot "skills\pc-pilot"
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

if (-not $NoGlobalRules) {
    $geminiDir = Join-Path $env:USERPROFILE ".gemini"
    if (Test-Path -LiteralPath $geminiDir) {
        $geminiMd = Join-Path $geminiDir "GEMINI.md"
        $bakMd = Join-Path $geminiDir "GEMINI.md.bak-pc-pilot"
        if ((Test-Path -LiteralPath $geminiMd) -and -not (Test-Path -LiteralPath $bakMd)) {
            Copy-Item -LiteralPath $geminiMd -Destination $bakMd -Force
        }
        $routingText = Get-Content -LiteralPath (Join-Path $repoRoot "rules\pc-pilot-routing.md") -Raw -Encoding UTF8
        $machineText = if (Test-Path -LiteralPath $manifestPath) { Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 } else { "" }
        $merged = $routingText.TrimEnd() + "`r`n`r`n---`r`n`r`n" + $machineText.TrimStart()
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($geminiMd, $merged, $utf8NoBom)
        Write-Output "Updated Antigravity global rules -> $geminiMd"
    }
}

Write-Output "`n=== [4/5] 生成通用 MCP 配置模板 ==="
$mcpReady = Join-Path $pcPilotHome "mcp_config.ready.json"
Copy-Item -LiteralPath (Join-Path $repoRoot "templates\mcp_config.universal.json") -Destination $mcpReady -Force
Write-Output "Ready MCP template -> $mcpReady"

Write-Output "`n=== [5/5] 运行全链路体检 (pc-doctor) ==="
$doctorScript = Join-Path $repoRoot "scripts\doctor.ps1"
& $doctorScript
