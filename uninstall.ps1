<#
.SYNOPSIS
    Universal PC Pilot 卸载脚本：清理插件生成的垫片、原生插件目录与标记规则块，绝不覆盖用户自写守则。
#>
param(
    [switch]$KeepToolShims
)

$ErrorActionPreference = 'SilentlyContinue'
$binDir = Join-Path $env:USERPROFILE ".local\bin"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

$coreShims = @('fast-act.cmd', 'focus-caller.cmd', 'office-cli.cmd', 'pc-doctor.cmd')
foreach ($s in $coreShims) {
    $p = Join-Path $binDir $s
    if (Test-Path -LiteralPath $p) {
        Remove-Item -LiteralPath $p -Force
        Write-Output "Removed core shim: $p"
    }
}

if (-not $KeepToolShims) {
    foreach ($s in @('7z.cmd','ollama.cmd','vswhere.cmd','pycharm.cmd','idea.cmd','clion.cmd','vmrun.cmd','vboxmanage.cmd','typora.cmd','wechat-cli.cmd','ccs-cli.cmd','adb.cmd','ffmpeg.cmd','pandoc.cmd','soffice.cmd','msbuild.cmd','devenv.cmd','conda.cmd','jupyter-conda.cmd')) {
        $p = Join-Path $binDir $s
        if (Test-Path -LiteralPath $p) {
            Remove-Item -LiteralPath $p -Force
            Write-Output "Removed tool shim: $p"
        }
    }
}

foreach ($sk in @(
    (Join-Path $env:USERPROFILE '.gemini\config\plugins\universal-pc-pilot'),
    (Join-Path $env:USERPROFILE '.gemini\skills\pc-pilot'),
    (Join-Path $env:USERPROFILE '.claude\skills\pc-pilot'),
    (Join-Path $env:USERPROFILE '.codex\skills\pc-pilot'),
    (Join-Path $env:USERPROFILE '.agents\skills\pc-pilot')
)) {
    if (Test-Path -LiteralPath $sk) {
        Remove-Item -LiteralPath $sk -Recurse -Force
        Write-Output "Removed plugin/skill: $sk"
    }
}

# 安全移除 GEMINI.md 中的插件规则标记块，保留用户自己的全部守则
$geminiMd = Join-Path $env:USERPROFILE '.gemini\GEMINI.md'
if (Test-Path -LiteralPath $geminiMd) {
    $startMarker = "<!-- UNIVERSAL-PC-PILOT:START -->"
    $endMarker = "<!-- UNIVERSAL-PC-PILOT:END -->"
    $mdContent = [System.IO.File]::ReadAllText($geminiMd, $utf8NoBom)
    $pattern = "(?s)(?:\r?\n---\r?\n\r?\n)?" + [regex]::Escape($startMarker) + ".*?" + [regex]::Escape($endMarker) + "\r?\n?"
    if ($mdContent -match [regex]::Escape($startMarker)) {
        $cleaned = [regex]::Replace($mdContent, $pattern, "").TrimEnd() + "`r`n"
        [System.IO.File]::WriteAllText($geminiMd, $cleaned, $utf8NoBom)
        Write-Output "Removed UNIVERSAL-PC-PILOT block from: $geminiMd"
    }
}

Write-Output "Uninstall completed."
