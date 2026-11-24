<#
.SYNOPSIS
    Universal PC Pilot 卸载脚本：清理插件生成的垫片与规则挂载，并还原备份。
#>
param(
    [switch]$KeepToolShims
)

$ErrorActionPreference = 'SilentlyContinue'
$binDir = Join-Path $env:USERPROFILE ".local\bin"

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
    (Join-Path $env:USERPROFILE '.gemini\skills\pc-pilot'),
    (Join-Path $env:USERPROFILE '.claude\skills\pc-pilot'),
    (Join-Path $env:USERPROFILE '.codex\skills\pc-pilot'),
    (Join-Path $env:USERPROFILE '.agents\skills\pc-pilot')
)) {
    if (Test-Path -LiteralPath $sk) {
        Remove-Item -LiteralPath $sk -Recurse -Force
        Write-Output "Removed skill: $sk"
    }
}

$geminiMd = Join-Path $env:USERPROFILE '.gemini\GEMINI.md'
$bakMd = Join-Path $env:USERPROFILE '.gemini\GEMINI.md.bak-pc-pilot'
if (Test-Path -LiteralPath $bakMd) {
    Move-Item -LiteralPath $bakMd -Destination $geminiMd -Force
    Write-Output "Restored backup: $geminiMd"
}

Write-Output "Uninstall completed."
