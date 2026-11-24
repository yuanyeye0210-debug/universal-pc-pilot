<#
.SYNOPSIS
    bootstrap-clis.ps1 — 动态探测当前 Windows 电脑已安装的办公/编程/虚拟化/AI 软件原生 CLI，
    并在 ~/.local/bin 生成无污染 .cmd 垫片与当前机器工具清单 ~/.pc-pilot/MACHINE_TOOLS.md。
#>
param(
    [string]$BinDir = (Join-Path $env:USERPROFILE ".local\bin"),
    [string]$OutputDoc = (Join-Path $env:USERPROFILE ".pc-pilot\MACHINE_TOOLS.md")
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $BinDir)) {
    New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
}
$outParent = Split-Path -Parent $OutputDoc
if ($outParent -and -not (Test-Path -LiteralPath $outParent)) {
    New-Item -ItemType Directory -Path $outParent -Force | Out-Null
}

# 确保 ~/.local/bin 在用户级 PATH 中
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$pathParts = @()
if ($userPath) {
    $pathParts = $userPath -split ';' | Where-Object { $_ -and $_.Trim() -ne '' }
}
if ($pathParts -notcontains $BinDir) {
    $newUserPath = ($pathParts + $BinDir) -join ';'
    [Environment]::SetEnvironmentVariable('Path', $newUserPath, 'User')
    Write-Output "Added to User PATH: $BinDir"
}
if (($env:Path -split ';') -notcontains $BinDir) {
    $env:Path = "$BinDir;$env:Path"
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Write-CmdShim {
    param(
        [string]$ShimName,
        [string]$TargetPath,
        [switch]$IsPowerShellScript
    )
    $shimFile = Join-Path $BinDir "$ShimName.cmd"
    if ($IsPowerShellScript) {
        $content = "@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"$TargetPath`" %*`r`n"
    } elseif ($TargetPath.EndsWith('.bat', [System.StringComparison]::OrdinalIgnoreCase) -or $TargetPath.EndsWith('.cmd', [System.StringComparison]::OrdinalIgnoreCase)) {
        $content = "@echo off`r`ncall `"$TargetPath`" %*`r`n"
    } else {
        $content = "@echo off`r`n`"$TargetPath`" %*`r`n"
    }
    [System.IO.File]::WriteAllText($shimFile, $content, $utf8NoBom)
    return $shimFile
}

# 1. 挂载插件内置核心工具
$builtinShims = @(
    @{ Name = 'fast-act';     File = (Join-Path $PSScriptRoot 'fast-act.ps1') },
    @{ Name = 'focus-caller'; File = (Join-Path $PSScriptRoot 'focus-caller.ps1') },
    @{ Name = 'office-cli';   File = (Join-Path $PSScriptRoot 'office-cli.ps1') },
    @{ Name = 'pc-doctor';    File = (Join-Path $PSScriptRoot 'doctor.ps1') }
)
$mountedTools = New-Object System.Collections.Generic.List[object]
foreach ($b in $builtinShims) {
    if (Test-Path -LiteralPath $b.File) {
        $p = Write-CmdShim -ShimName $b.Name -TargetPath $b.File -IsPowerShellScript
        $mountedTools.Add([PSCustomObject]@{ Name = $b.Name; Source = $p; Category = 'core'; Origin = 'plugin' })
    }
}

# 2. 收集动态搜索根目录（全盘常规软件目录 + 用户目录）
$drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -match '^[A-Z]:\\$' } | Select-Object -ExpandProperty Root
$searchDirs = New-Object System.Collections.Generic.List[string]
foreach ($d in $drives) {
    foreach ($sub in @('Program Files', 'Program Files (x86)', 'App', 'Apps', 'Programs', 'Software', 'Tools', 'vscode', 'obsidian', 'ti', '微信web开发者工具')) {
        $cand = Join-Path $d $sub
        if (Test-Path -LiteralPath $cand) { [void]$searchDirs.Add($cand) }
    }
}
foreach ($u in @(
    (Join-Path $env:LOCALAPPDATA 'Programs'),
    (Join-Path $env:APPDATA 'uv\tools\cli-anything-hub\Scripts')
)) {
    if (Test-Path -LiteralPath $u) { [void]$searchDirs.Add($u) }
}

function Find-FirstExecutable {
    param(
        [string[]]$FileNames,
        [string[]]$KnownRelativePaths = @(),
        [int]$Depth = 3
    )
    foreach ($rel in $KnownRelativePaths) {
        foreach ($d in $drives) {
            $full = Join-Path $d $rel
            if (Test-Path -LiteralPath $full) { return $full }
        }
    }
    foreach ($dir in $searchDirs) {
        foreach ($fn in $FileNames) {
            $hit = Get-ChildItem -LiteralPath $dir -Filter $fn -Recurse -Depth $Depth -ErrorAction SilentlyContinue |
                Where-Object { -not $_.PSIsContainer } |
                Select-Object -First 1
            if ($hit) { return $hit.FullName }
        }
    }
    return $null
}

# 3. 探测并挂载常见办公/编程/AI/虚拟化 CLI（仅当不在系统原生 PATH 时生成垫片）
$probeSpecs = @(
    @{ Name = '7z';         Files = @('7z.exe');         Rels = @('Program Files\7-Zip\7z.exe', 'App\7-Zip\7z.exe'); Cat = 'system' },
    @{ Name = 'ollama';     Files = @('ollama.exe');     Rels = @('Apps\Ollama\ollama.exe', 'Program Files\Ollama\ollama.exe'); Cat = 'ai' },
    @{ Name = 'vswhere';    Files = @('vswhere.exe');    Rels = @('Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe'); Cat = 'dev' },
    @{ Name = 'pycharm';    Files = @('pycharm64.exe');  Rels = @(); Cat = 'dev' },
    @{ Name = 'idea';       Files = @('idea64.exe');     Rels = @(); Cat = 'dev' },
    @{ Name = 'clion';      Files = @('clion64.exe');    Rels = @(); Cat = 'dev' },
    @{ Name = 'vmrun';      Files = @('vmrun.exe');      Rels = @('Program Files (x86)\VMware\VMware Workstation\vmrun.exe'); Cat = 'vm' },
    @{ Name = 'vboxmanage'; Files = @('VBoxManage.exe'); Rels = @('Program Files\Oracle\VirtualBox\VBoxManage.exe'); Cat = 'vm' },
    @{ Name = 'typora';     Files = @('Typora.exe');     Rels = @('Program Files\Typora\Typora.exe', 'App\Typora\Typora.exe'); Cat = 'office' },
    @{ Name = 'wechat-cli'; Files = @('cli.bat');        Rels = @('微信web开发者工具\cli.bat'); Cat = 'dev' },
    @{ Name = 'ccs-cli';    Files = @('eclipsec.exe');   Rels = @('ti\ccs1281\ccs\eclipse\eclipsec.exe'); Cat = 'dev' },
    @{ Name = 'adb';        Files = @('adb.exe');        Rels = @(); Cat = 'dev' },
    @{ Name = 'ffmpeg';     Files = @('ffmpeg.exe');     Rels = @(); Cat = 'media' },
    @{ Name = 'pandoc';     Files = @('pandoc.exe');     Rels = @(); Cat = 'office' },
    @{ Name = 'soffice';    Files = @('soffice.exe');    Rels = @('Program Files\LibreOffice\program\soffice.exe'); Cat = 'office' }
)

foreach ($spec in $probeSpecs) {
    $existing = Get-Command $spec.Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($existing -and ($existing.Source -notlike "$BinDir*")) {
        $mountedTools.Add([PSCustomObject]@{ Name = $spec.Name; Source = $existing.Source; Category = $spec.Cat; Origin = 'system-path' })
        continue
    }
    $found = Find-FirstExecutable -FileNames $spec.Files -KnownRelativePaths $spec.Rels
    if ($found) {
        $p = Write-CmdShim -ShimName $spec.Name -TargetPath $found
        $mountedTools.Add([PSCustomObject]@{ Name = $spec.Name; Source = $found; Category = $spec.Cat; Origin = 'shim' })
    }
}

# 借助 vswhere 精确定位 msbuild 与 devenv
$vswhereCmd = Get-Command vswhere -ErrorAction SilentlyContinue | Select-Object -First 1
$vswherePath = if ($vswhereCmd) { $vswhereCmd.Source } else { Find-FirstExecutable -FileNames @('vswhere.exe') -KnownRelativePaths @('Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe') }
if ($vswherePath) {
    try {
        $msbuildHit = & $vswherePath -latest -find 'MSBuild\**\Bin\MSBuild.exe' 2>$null | Select-Object -First 1
        if ($msbuildHit -and (Test-Path -LiteralPath $msbuildHit)) {
            $null = Write-CmdShim -ShimName 'msbuild' -TargetPath $msbuildHit
            $mountedTools.Add([PSCustomObject]@{ Name = 'msbuild'; Source = $msbuildHit; Category = 'dev'; Origin = 'vswhere-shim' })
        }
        $vsInstall = & $vswherePath -latest -property installationPath 2>$null | Select-Object -First 1
        if ($vsInstall) {
            $devenvCom = Join-Path $vsInstall 'Common7\IDE\devenv.com'
            $devenvExe = Join-Path $vsInstall 'Common7\IDE\devenv.exe'
            $devenvHit = if (Test-Path -LiteralPath $devenvCom) { $devenvCom } elseif (Test-Path -LiteralPath $devenvExe) { $devenvExe } else { $null }
            if ($devenvHit) {
                $null = Write-CmdShim -ShimName 'devenv' -TargetPath $devenvHit
                $mountedTools.Add([PSCustomObject]@{ Name = 'devenv'; Source = $devenvHit; Category = 'dev'; Origin = 'vswhere-shim' })
            }
        }
    } catch {}
}

# 健康度探针校验 Conda（自动跳过损坏的残留安装）
foreach ($dir in $searchDirs) {
    $condaCandidates = Get-ChildItem -LiteralPath $dir -Filter 'conda.exe' -Recurse -Depth 2 -ErrorAction SilentlyContinue
    $mountedConda = $false
    foreach ($cc in $condaCandidates) {
        try {
            $null = & $cc.FullName --version 2>$null
            if ($LASTEXITCODE -eq 0) {
                $null = Write-CmdShim -ShimName 'conda' -TargetPath $cc.FullName
                $mountedTools.Add([PSCustomObject]@{ Name = 'conda'; Source = $cc.FullName; Category = 'dev'; Origin = 'health-checked-shim' })
                $jup = Join-Path $cc.DirectoryName 'jupyter.exe'
                if (Test-Path -LiteralPath $jup) {
                    $null = Write-CmdShim -ShimName 'jupyter-conda' -TargetPath $jup
                    $mountedTools.Add([PSCustomObject]@{ Name = 'jupyter-conda'; Source = $jup; Category = 'dev'; Origin = 'health-checked-shim' })
                }
                $mountedConda = $true
                break
            }
        } catch {}
    }
    if ($mountedConda) { break }
}

# 同步 cli-hub Scripts 下已装的 cli-anything-* 工具到 ~/.local/bin
$hubScripts = Join-Path $env:APPDATA 'uv\tools\cli-anything-hub\Scripts'
if (Test-Path -LiteralPath $hubScripts) {
    Get-ChildItem -LiteralPath $hubScripts -Filter 'cli-anything-*.exe' -ErrorAction SilentlyContinue | ForEach-Object {
        $base = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
        $null = Write-CmdShim -ShimName $base -TargetPath $_.FullName
        $mountedTools.Add([PSCustomObject]@{ Name = $base; Source = $_.FullName; Category = 'cli-anything'; Origin = 'cli-hub-shim' })
    }
}

# 检查常用已有原生 PATH 工具
foreach ($nativeName in @('cli-hub', 'markitdown', 'obsidian-agent', 'lark-cli', 'git', 'gh', 'code', 'python', 'uv', 'node', 'npm', 'pnpm', 'dotnet', 'sqlcmd', 'wsl', 'winget', 'choco', 'claude', 'codex', 'gemini')) {
    $c = Get-Command $nativeName -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($c -and -not ($mountedTools | Where-Object { $_.Name -eq $nativeName })) {
        $mountedTools.Add([PSCustomObject]@{ Name = $nativeName; Source = $c.Source; Category = 'native'; Origin = 'path' })
    }
}

# 生成当前机器专属的 MACHINE_TOOLS.md
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("# 本机已就绪 CLI 工具清单 (由 Universal PC Pilot 自动探测生成)")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("- 生成时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
[void]$sb.AppendLine("- 统一入口目录: ``$BinDir``")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("| 命令 | 类别 | 来源方式 | 实际路径 |")
[void]$sb.AppendLine("| :--- | :--- | :--- | :--- |")
foreach ($item in ($mountedTools | Sort-Object Name -Unique)) {
    [void]$sb.AppendLine("| ``$($item.Name)`` | $($item.Category) | $($item.Origin) | ``$($item.Source)`` |")
}

$utf8NoBom2 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($OutputDoc, $sb.ToString(), $utf8NoBom2)
Write-Output "BootstrapDone totalTools=$($mountedTools.Count) manifest=$OutputDoc"
