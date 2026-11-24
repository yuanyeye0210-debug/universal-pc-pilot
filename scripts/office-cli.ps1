<#
.SYNOPSIS
    office-cli — Microsoft Office / 国产 WPS 双引擎静默办公文档命令行工具。
.DESCRIPTION
    自动优先调用 Microsoft Office COM；若本机仅安装 WPS Office，则自动回退到 WPS COM。
    支持：
      - to-pdf <输入文件> [输出PDF]
      - to-csv <输入Excel> [输出CSV] [--sheet <名称或1起始序号>]
      - info <输入文件> [--json]
#>

[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RawArgs
)

$ErrorActionPreference = 'Stop'

function Show-Help {
    @"
office-cli — Microsoft Office / WPS 双引擎静默命令行工具

用法:
  office-cli to-pdf <输入文件> [输出PDF路径]              将 Word / Excel / PPT 静默导出为 PDF
  office-cli to-csv <Excel文件> [输出CSV] [--sheet 1]     将 Excel 指定工作表导出为 UTF-8 CSV
  office-cli info <输入文件> [--json]                     查看文档结构、工作表列表与统计信息
  office-cli --help                                       显示本帮助信息

支持格式:
  - Word / WPS 文字:   .doc, .docx, .rtf, .wps
  - Excel / WPS 表格:  .xls, .xlsx, .xlsm, .csv, .et
  - PowerPoint / 演示: .ppt, .pptx, .dps
"@ | Write-Output
}

function Release-ComObjectSafely {
    param([object]$ComObj)
    if ($null -ne $ComObj) {
        try {
            [void][System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($ComObj)
        } catch {}
    }
}

function New-ComEngine {
    param([string[]]$ProgIds)
    foreach ($id in $ProgIds) {
        try {
            $app = New-Object -ComObject $id
            if ($null -ne $app) {
                return @{
                    App    = $app
                    Engine = $id
                }
            }
        } catch {}
    }
    throw "未检测到可用的 Microsoft Office 或 WPS Office COM 组件 (尝试过: $($ProgIds -join ', '))"
}

function Export-OfficeToPdf {
    param(
        [string]$InputPath,
        [string]$OutputPath
    )

    if (-not (Test-Path -LiteralPath $InputPath)) {
        throw "输入文件不存在: $InputPath"
    }

    $resolvedInput = (Resolve-Path -LiteralPath $InputPath).Path
    $ext = [System.IO.Path]::GetExtension($resolvedInput).ToLowerInvariant()

    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $OutputPath = [System.IO.Path]::ChangeExtension($resolvedInput, '.pdf')
    } else {
        $OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
    }

    $outDir = [System.IO.Path]::GetDirectoryName($OutputPath)
    if (-not (Test-Path -LiteralPath $outDir)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }

    $usedEngine = ""
    switch ($ext) {
        { $_ -in '.doc', '.docx', '.rtf', '.wps' } {
            $ctx = $null
            $doc = $null
            try {
                $ctx = New-ComEngine -ProgIds @('Word.Application', 'KWPS.Application', 'WPS.Application')
                $usedEngine = $ctx.Engine
                $word = $ctx.App
                $word.Visible = $false
                try { $word.DisplayAlerts = 0 } catch {}
                $doc = $word.Documents.Open($resolvedInput, $false, $true)
                # WdExportFormat.wdExportFormatPDF = 17
                $doc.ExportAsFixedFormat($OutputPath, 17)
            } finally {
                if ($null -ne $doc) { try { $doc.Close($false) } catch {}; Release-ComObjectSafely $doc }
                if ($null -ne $ctx -and $null -ne $ctx.App) { try { $ctx.App.Quit($false) } catch {}; Release-ComObjectSafely $ctx.App }
                [GC]::Collect()
                [GC]::WaitForPendingFinalizers()
            }
        }
        { $_ -in '.xls', '.xlsx', '.xlsm', '.csv', '.et' } {
            $ctx = $null
            $wb = $null
            try {
                $ctx = New-ComEngine -ProgIds @('Excel.Application', 'KET.Application', 'ET.Application')
                $usedEngine = $ctx.Engine
                $excel = $ctx.App
                $excel.Visible = $false
                try { $excel.DisplayAlerts = $false } catch {}
                $wb = $excel.Workbooks.Open($resolvedInput, 0, $true)
                # xlTypePDF = 0
                $wb.ExportAsFixedFormat(0, $OutputPath)
            } finally {
                if ($null -ne $wb) { try { $wb.Close($false) } catch {}; Release-ComObjectSafely $wb }
                if ($null -ne $ctx -and $null -ne $ctx.App) { try { $ctx.App.Quit() } catch {}; Release-ComObjectSafely $ctx.App }
                [GC]::Collect()
                [GC]::WaitForPendingFinalizers()
            }
        }
        { $_ -in '.ppt', '.pptx', '.dps' } {
            $ctx = $null
            $pres = $null
            try {
                $ctx = New-ComEngine -ProgIds @('PowerPoint.Application', 'KWPP.Application', 'WPP.Application')
                $usedEngine = $ctx.Engine
                $ppt = $ctx.App
                $pres = $ppt.Presentations.Open($resolvedInput, -1, 0, 0)
                # PpSaveAsFileType.ppSaveAsPDF = 32
                $pres.SaveAs($OutputPath, 32)
            } finally {
                if ($null -ne $pres) { try { $pres.Close() } catch {}; Release-ComObjectSafely $pres }
                if ($null -ne $ctx -and $null -ne $ctx.App) { try { $ctx.App.Quit() } catch {}; Release-ComObjectSafely $ctx.App }
                [GC]::Collect()
                [GC]::WaitForPendingFinalizers()
            }
        }
        default {
            throw "不支持的文件扩展名: $ext"
        }
    }

    if (-not (Test-Path -LiteralPath $OutputPath)) {
        throw "PDF 导出失败，未生成目标文件: $OutputPath"
    }

    Write-Output "导出成功 ($usedEngine): $OutputPath"
}

function Export-ExcelToCsv {
    param(
        [string]$InputPath,
        [string]$OutputPath,
        [string]$SheetSelector = "1"
    )

    if (-not (Test-Path -LiteralPath $InputPath)) {
        throw "输入文件不存在: $InputPath"
    }
    $resolvedInput = (Resolve-Path -LiteralPath $InputPath).Path
    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $OutputPath = [System.IO.Path]::ChangeExtension($resolvedInput, '.csv')
    } else {
        $OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
    }

    $ctx = $null
    $wb = $null
    $ws = $null
    $used = $null
    try {
        $ctx = New-ComEngine -ProgIds @('Excel.Application', 'KET.Application', 'ET.Application')
        $excel = $ctx.App
        $excel.Visible = $false
        try { $excel.DisplayAlerts = $false } catch {}
        $wb = $excel.Workbooks.Open($resolvedInput, 0, $true)

        $idx = 0
        if ([int]::TryParse($SheetSelector, [ref]$idx)) {
            $ws = $wb.Worksheets.Item($idx)
        } else {
            $ws = $wb.Worksheets.Item($SheetSelector)
        }

        $used = $ws.UsedRange
        $val = $used.Value2
        $lines = New-Object System.Collections.Generic.List[string]

        if ($null -eq $val) {
            # 空工作表
        } elseif ($val -is [System.Array] -and $val.Rank -eq 2) {
            $rLow = $val.GetLowerBound(0)
            $rHigh = $val.GetUpperBound(0)
            $cLow = $val.GetLowerBound(1)
            $cHigh = $val.GetUpperBound(1)
            for ($r = $rLow; $r -le $rHigh; $r++) {
                $cells = New-Object System.Collections.Generic.List[string]
                for ($c = $cLow; $c -le $cHigh; $c++) {
                    $cellRaw = if ($null -eq $val[$r, $c]) { "" } else { [string]$val[$r, $c] }
                    $escaped = '"' + ($cellRaw -replace '"', '""') + '"'
                    [void]$cells.Add($escaped)
                }
                [void]$lines.Add(($cells -join ','))
            }
        } else {
            $escaped = '"' + (([string]$val) -replace '"', '""') + '"'
            [void]$lines.Add($escaped)
        }

        $outDir = [System.IO.Path]::GetDirectoryName($OutputPath)
        if (-not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
        $utf8Bom = New-Object System.Text.UTF8Encoding($true)
        [System.IO.File]::WriteAllLines($OutputPath, $lines, $utf8Bom)
        Write-Output "导出 CSV 成功 ($($ctx.Engine), 工作表='$($ws.Name)', 共 $($lines.Count) 行): $OutputPath"
    } finally {
        if ($null -ne $used) { Release-ComObjectSafely $used }
        if ($null -ne $ws) { Release-ComObjectSafely $ws }
        if ($null -ne $wb) { try { $wb.Close($false) } catch {}; Release-ComObjectSafely $wb }
        if ($null -ne $ctx -and $null -ne $ctx.App) { try { $ctx.App.Quit() } catch {}; Release-ComObjectSafely $ctx.App }
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
    }
}

function Get-OfficeInfo {
    param(
        [string]$InputPath,
        [bool]$AsJson
    )

    if (-not (Test-Path -LiteralPath $InputPath)) {
        throw "输入文件不存在: $InputPath"
    }

    $item = Get-Item -LiteralPath $InputPath
    $resolvedInput = $item.FullName
    $ext = $item.Extension.ToLowerInvariant()

    $result = [ordered]@{
        file      = $resolvedInput
        name      = $item.Name
        extension = $ext
        sizeBytes = $item.Length
    }

    switch ($ext) {
        { $_ -in '.doc', '.docx', '.rtf', '.wps' } {
            $ctx = $null
            $doc = $null
            try {
                $ctx = New-ComEngine -ProgIds @('Word.Application', 'KWPS.Application', 'WPS.Application')
                $word = $ctx.App
                $word.Visible = $false
                try { $word.DisplayAlerts = 0 } catch {}
                $doc = $word.Documents.Open($resolvedInput, $false, $true)
                $result['type'] = 'Word'
                $result['engine'] = $ctx.Engine
                $result['paragraphs'] = $doc.Paragraphs.Count
                $result['words'] = $doc.Words.Count
                $result['characters'] = $doc.Characters.Count
            } finally {
                if ($null -ne $doc) { try { $doc.Close($false) } catch {}; Release-ComObjectSafely $doc }
                if ($null -ne $ctx -and $null -ne $ctx.App) { try { $ctx.App.Quit($false) } catch {}; Release-ComObjectSafely $ctx.App }
                [GC]::Collect()
                [GC]::WaitForPendingFinalizers()
            }
        }
        { $_ -in '.xls', '.xlsx', '.xlsm', '.csv', '.et' } {
            $ctx = $null
            $wb = $null
            try {
                $ctx = New-ComEngine -ProgIds @('Excel.Application', 'KET.Application', 'ET.Application')
                $excel = $ctx.App
                $excel.Visible = $false
                try { $excel.DisplayAlerts = $false } catch {}
                $wb = $excel.Workbooks.Open($resolvedInput, 0, $true)
                $sheets = @()
                foreach ($ws in $wb.Worksheets) {
                    $used = $ws.UsedRange
                    $sheets += [ordered]@{
                        name    = $ws.Name
                        rows    = $used.Rows.Count
                        columns = $used.Columns.Count
                        address = $used.Address($false, $false)
                    }
                    Release-ComObjectSafely $used
                    Release-ComObjectSafely $ws
                }
                $result['type'] = 'Excel'
                $result['engine'] = $ctx.Engine
                $result['sheetCount'] = $sheets.Count
                $result['sheets'] = $sheets
            } finally {
                if ($null -ne $wb) { try { $wb.Close($false) } catch {}; Release-ComObjectSafely $wb }
                if ($null -ne $ctx -and $null -ne $ctx.App) { try { $ctx.App.Quit() } catch {}; Release-ComObjectSafely $ctx.App }
                [GC]::Collect()
                [GC]::WaitForPendingFinalizers()
            }
        }
        { $_ -in '.ppt', '.pptx', '.dps' } {
            $ctx = $null
            $pres = $null
            try {
                $ctx = New-ComEngine -ProgIds @('PowerPoint.Application', 'KWPP.Application', 'WPP.Application')
                $ppt = $ctx.App
                $pres = $ppt.Presentations.Open($resolvedInput, -1, 0, 0)
                $result['type'] = 'PowerPoint'
                $result['engine'] = $ctx.Engine
                $result['slides'] = $pres.Slides.Count
            } finally {
                if ($null -ne $pres) { try { $pres.Close() } catch {}; Release-ComObjectSafely $pres }
                if ($null -ne $ctx -and $null -ne $ctx.App) { try { $ctx.App.Quit() } catch {}; Release-ComObjectSafely $ctx.App }
                [GC]::Collect()
                [GC]::WaitForPendingFinalizers()
            }
        }
        default {
            throw "不支持的文件扩展名: $ext"
        }
    }

    if ($AsJson) {
        $result | ConvertTo-Json -Depth 5
    } else {
        Write-Output "文件: $($result.file)"
        Write-Output "类型: $($result.type) | 引擎: $($result.engine) ($($result.sizeBytes) bytes)"
        switch ($result.type) {
            'Word' {
                Write-Output "段落数: $($result.paragraphs) | 词数: $($result.words) | 字符数: $($result.characters)"
            }
            'Excel' {
                Write-Output "工作表数: $($result.sheetCount)"
                foreach ($s in $result.sheets) {
                    Write-Output "  - $($s.name): $($s.rows) 行 x $($s.columns) 列 ($($s.address))"
                }
            }
            'PowerPoint' {
                Write-Output "幻灯片页数: $($result.slides)"
            }
        }
    }
}

if (-not $RawArgs -or $RawArgs.Count -eq 0 -or $RawArgs[0] -in @('--help', '-h', 'help')) {
    Show-Help
    exit 0
}

$cmd = $RawArgs[0].ToLowerInvariant()
switch ($cmd) {
    'to-pdf' {
        if ($RawArgs.Count -lt 2) {
            Write-Error "缺少输入文件路径。用法: office-cli to-pdf <输入文件> [输出PDF路径]"
            exit 1
        }
        $inFile = $RawArgs[1]
        $outFile = if ($RawArgs.Count -ge 3) { $RawArgs[2] } else { $null }
        Export-OfficeToPdf -InputPath $inFile -OutputPath $outFile
    }
    'to-csv' {
        if ($RawArgs.Count -lt 2) {
            Write-Error "缺少输入 Excel 文件路径。用法: office-cli to-csv <Excel文件> [输出CSV] [--sheet 1]"
            exit 1
        }
        $sheetSel = "1"
        $posArgs = New-Object System.Collections.Generic.List[string]
        for ($i = 1; $i -lt $RawArgs.Count; $i++) {
            if ($RawArgs[$i] -eq '--sheet' -and ($i + 1) -lt $RawArgs.Count) {
                $sheetSel = $RawArgs[$i + 1]
                $i++
            } else {
                [void]$posArgs.Add($RawArgs[$i])
            }
        }
        if ($posArgs.Count -lt 1) {
            Write-Error "缺少输入 Excel 文件路径。"
            exit 1
        }
        $inFile = $posArgs[0]
        $outFile = if ($posArgs.Count -ge 2) { $posArgs[1] } else { $null }
        Export-ExcelToCsv -InputPath $inFile -OutputPath $outFile -SheetSelector $sheetSel
    }
    'info' {
        if ($RawArgs.Count -lt 2) {
            Write-Error "缺少输入文件路径。用法: office-cli info <输入文件> [--json]"
            exit 1
        }
        $asJson = $RawArgs -contains '--json'
        $inFile = ($RawArgs | Select-Object -Skip 1 | Where-Object { $_ -ne '--json' } | Select-Object -First 1)
        if ([string]::IsNullOrWhiteSpace($inFile)) {
            Write-Error "缺少输入文件路径。"
            exit 1
        }
        Get-OfficeInfo -InputPath $inFile -AsJson $asJson
    }
    default {
        Write-Error "未知子命令: $cmd"
        Show-Help
        exit 1
    }
}
