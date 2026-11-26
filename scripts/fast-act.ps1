<#
.SYNOPSIS
    fast-act v2.0 — 极速高准度桌面批量操作引擎（通用跨 Agent 版）
.DESCRIPTION
    1. 自动记忆调用方宿主窗口句柄 (CallerHWND)，支持任何 Agent 终端/IDE 弹回
    2. 激活目标窗口并默认最大化全屏（-NoMaximize 可关闭最大化）
    3. 硬件级人机协同检测（GetCursorPos + GetLastInputInfo），触碰即让权并在停手 2.5 秒后截图接力
    4. 每步动作前强校验前台焦点仍在目标进程
    5. 支持相对坐标 (rx,ry) 防越界拦截 + clickName (UIA 直达) + scroll + drag + focusPopup
    6. 支持 STA 安全全类型剪贴板保护（文本/图片/文件）的 paste，以及特殊字符转义 typeText
    7. 支持 WinRT 本地毫秒级 OCR（assertOcr 拦截 + readOcr 纯文本回传）
    8. 核验截图 (-CapturePath) 内嵌 100px 相对坐标刻度尺与最后点击红点准星
#>
param(
    [string]$ProcessName = "",
    [string]$WindowTitle = "",
    [Parameter(Mandatory = $true)]
    [string]$ActionsJson,
    [string]$CapturePath = "",
    [switch]$NoMaximize,
    [switch]$NoRuler,
    [switch]$ReturnFocus,
    [string]$ReturnProcess = ""
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null = [Windows.Storage.Streams.InMemoryRandomAccessStream, Windows.Storage.Streams, ContentType = WindowsRuntime]
$null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics, ContentType = WindowsRuntime]
$null = [Windows.Graphics.Imaging.SoftwareBitmap, Windows.Graphics, ContentType = WindowsRuntime]
$null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
$null = [Windows.Globalization.Language, Windows.Foundation, ContentType = WindowsRuntime]

Add-Type @"
using System;
using System.Runtime.InteropServices;

public class FastWin32 {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT lpPoint);
    [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, uint dx, uint dy, int dwData, UIntPtr dwExtraInfo);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }

    [StructLayout(LayoutKind.Sequential)]
    public struct POINT { public int X; public int Y; }

    [StructLayout(LayoutKind.Sequential)]
    public struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }

    public const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    public const uint MOUSEEVENTF_LEFTUP = 0x0004;
    public const uint MOUSEEVENTF_RIGHTDOWN = 0x0008;
    public const uint MOUSEEVENTF_RIGHTUP = 0x0010;
    public const uint MOUSEEVENTF_WHEEL = 0x0800;
    public const int SW_MAXIMIZE = 3;
    public const int SW_RESTORE = 9;
    [DllImport("kernel32.dll")] public static extern uint GetTickCount();
}
"@

[FastWin32]::SetProcessDPIAware() | Out-Null

# 记录调用方宿主窗口句柄（在激活目标窗口前捕获）
$script:callerHwnd = [FastWin32]::GetForegroundWindow()

$targetProc = Get-Process | Where-Object {
    $_.MainWindowHandle -ne 0 -and
    ($ProcessName -eq "" -or $_.ProcessName -eq $ProcessName) -and
    ($WindowTitle -eq "" -or $_.MainWindowTitle -like "*$WindowTitle*")
} | Select-Object -First 1

if (-not $targetProc) {
    Write-Error "未找到目标窗口 (ProcessName='$ProcessName', WindowTitle='$WindowTitle')"
    exit 1
}

$script:targetHwnd = $targetProc.MainWindowHandle
$script:targetPid = [uint32]$targetProc.Id
$script:expectedCursor = New-Object FastWin32+POINT
$script:expectedInputTick = [uint32]0
$script:lastClickScreen = $null

function Invoke-StaClipboard {
    param(
        [scriptblock]$Action,
        [object]$Argument = $null
    )
    if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -eq [System.Threading.ApartmentState]::STA) {
        return (& $Action $Argument)
    }
    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = [System.Threading.ApartmentState]::STA
    $rs.ThreadOptions = [System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread
    $rs.Open()
    try {
        $ps = [powershell]::Create()
        $ps.Runspace = $rs
        [void]$ps.AddScript($Action.ToString())
        [void]$ps.AddArgument($Argument)
        return $ps.Invoke()
    } finally {
        if ($ps) { $ps.Dispose() }
        $rs.Close()
        $rs.Dispose()
    }
}

function Backup-ClipboardState {
    Invoke-StaClipboard -Action {
        param($unused)
        Add-Type -AssemblyName System.Windows.Forms
        if ([System.Windows.Forms.Clipboard]::ContainsText()) {
            return @{ Kind = 'Text'; Data = [System.Windows.Forms.Clipboard]::GetText() }
        }
        if ([System.Windows.Forms.Clipboard]::ContainsImage()) {
            return @{ Kind = 'Image'; Data = [System.Windows.Forms.Clipboard]::GetImage() }
        }
        if ([System.Windows.Forms.Clipboard]::ContainsFileDropList()) {
            return @{ Kind = 'Files'; Data = [System.Windows.Forms.Clipboard]::GetFileDropList() }
        }
        return @{ Kind = 'None'; Data = $null }
    }
}

function Restore-ClipboardState {
    param([hashtable]$State)
    if ($null -eq $State -or $State.Kind -eq 'None') { return }
    try {
        Invoke-StaClipboard -Argument $State -Action {
            param($st)
            Add-Type -AssemblyName System.Windows.Forms
            switch ($st.Kind) {
                'Text'  { [System.Windows.Forms.Clipboard]::SetText([string]$st.Data) }
                'Image' { [System.Windows.Forms.Clipboard]::SetImage($st.Data) }
                'Files' { [System.Windows.Forms.Clipboard]::SetFileDropList($st.Data) }
            }
        } | Out-Null
    } catch {}
}

function Set-ClipboardTextSafely {
    param([string]$Text)
    Invoke-StaClipboard -Argument $Text -Action {
        param($t)
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.Clipboard]::SetText([string]$t)
    } | Out-Null
}

function Get-LastInputTick {
    $lii = New-Object FastWin32+LASTINPUTINFO
    $lii.cbSize = [uint32][System.Runtime.InteropServices.Marshal]::SizeOf($lii)
    [FastWin32]::GetLastInputInfo([ref]$lii) | Out-Null
    return $lii.dwTime
}

function Update-ScriptInputBaseline {
    Start-Sleep -Milliseconds 25
    $pt = New-Object FastWin32+POINT
    [FastWin32]::GetCursorPos([ref]$pt) | Out-Null
    $script:expectedCursor = $pt
    $script:expectedInputTick = Get-LastInputTick
}

function Test-UserIntervened {
    $pt = New-Object FastWin32+POINT
    [FastWin32]::GetCursorPos([ref]$pt) | Out-Null
    $dx = [Math]::Abs($pt.X - $script:expectedCursor.X)
    $dy = [Math]::Abs($pt.Y - $script:expectedCursor.Y)
    $tick = Get-LastInputTick
    if ($dx -gt 4 -or $dy -gt 4 -or ($tick -ne $script:expectedInputTick -and [Math]::Abs([int64]$tick - [int64]$script:expectedInputTick) -gt 40)) {
        return $true
    }
    return $false
}

function Escape-SendKeysText([string]$raw) {
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $raw.ToCharArray()) {
        switch ($ch) {
            '+' { [void]$sb.Append("{+}") }
            '^' { [void]$sb.Append("{^}") }
            '%' { [void]$sb.Append("{%}") }
            '~' { [void]$sb.Append("{~}") }
            '(' { [void]$sb.Append("{(}") }
            ')' { [void]$sb.Append("{)}") }
            '{' { [void]$sb.Append("{{}") }
            '}' { [void]$sb.Append("{}}") }
            '[' { [void]$sb.Append("{[}") }
            ']' { [void]$sb.Append("{]}") }
            default { [void]$sb.Append($ch) }
        }
    }
    return $sb.ToString()
}

function Save-TargetCapture {
    param([IntPtr]$CaptureHwnd = [IntPtr]::Zero)
    if ($CapturePath -eq "") { return }
    $hwnd = if ($CaptureHwnd -ne [IntPtr]::Zero -and [FastWin32]::IsWindow($CaptureHwnd)) { $CaptureHwnd } else { $script:targetHwnd }
    $rect = New-Object FastWin32+RECT
    [FastWin32]::GetWindowRect($hwnd, [ref]$rect) | Out-Null
    $w = [Math]::Max(1, $rect.Right - $rect.Left)
    $h = [Math]::Max(1, $rect.Bottom - $rect.Top)
    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.CopyFromScreen($rect.Left, $rect.Top, 0, 0, (New-Object System.Drawing.Size($w, $h)))

    if (-not $NoRuler) {
        $font = New-Object System.Drawing.Font("Consolas", 9, [System.Drawing.FontStyle]::Bold)
        $bgBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(170, 0, 0, 0))
        $fgBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(240, 0, 255, 180))
        $tickPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(190, 0, 255, 180), 1)

        for ($rx = 100; $rx -lt $w; $rx += 100) {
            $g.DrawLine($tickPen, $rx, 0, $rx, 10)
            $g.FillRectangle($bgBrush, $rx + 2, 1, 34, 14)
            $g.DrawString("$rx", $font, $fgBrush, $rx + 2, 0)
        }
        for ($ry = 100; $ry -lt $h; $ry += 100) {
            $g.DrawLine($tickPen, 0, $ry, 10, $ry)
            $g.FillRectangle($bgBrush, 1, $ry + 2, 34, 14)
            $g.DrawString("$ry", $font, $fgBrush, 2, $ry + 1)
        }
        $originLabel = "Origin($($rect.Left),$($rect.Top))"
        $g.FillRectangle($bgBrush, 0, 0, 128, 16)
        $g.DrawString($originLabel, $font, $fgBrush, 2, 1)

        if ($null -ne $script:lastClickScreen) {
            $cx = $script:lastClickScreen[0] - $rect.Left
            $cy = $script:lastClickScreen[1] - $rect.Top
            if ($cx -ge 0 -and $cx -le $w -and $cy -ge 0 -and $cy -le $h) {
                $hitPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(230, 255, 40, 40), 2)
                $g.DrawEllipse($hitPen, $cx - 10, $cy - 10, 20, 20)
                $g.DrawLine($hitPen, $cx - 16, $cy, $cx + 16, $cy)
                $g.DrawLine($hitPen, $cx, $cy - 16, $cx, $cy + 16)
                $hitPen.Dispose()
            }
        }

        $tickPen.Dispose()
        $fgBrush.Dispose()
        $bgBrush.Dispose()
        $font.Dispose()
    }

    $dir = Split-Path -Parent $CapturePath
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $bmp.Save($CapturePath, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose()
    $bmp.Dispose()
    Write-Output "Captured=$CapturePath ($w x $h) Origin=($($rect.Left),$($rect.Top))"
}

function Wait-UserIdleAndYield([int]$currentStep) {
    Write-Output "UserInterventionDetected: 检测到用户触碰鼠标/键盘 (步骤 $currentStep)，立即让出控制权并等待用户停手 2.5 秒..."
    $idleTimer = [System.Diagnostics.Stopwatch]::StartNew()
    $lastPt = New-Object FastWin32+POINT
    [FastWin32]::GetCursorPos([ref]$lastPt) | Out-Null
    $lastTick = Get-LastInputTick

    while ($idleTimer.ElapsedMilliseconds -lt 2500) {
        Start-Sleep -Milliseconds 100
        $curPt = New-Object FastWin32+POINT
        [FastWin32]::GetCursorPos([ref]$curPt) | Out-Null
        $curTick = Get-LastInputTick
        if ([Math]::Abs($curPt.X - $lastPt.X) -gt 2 -or [Math]::Abs($curPt.Y - $lastPt.Y) -gt 2 -or $curTick -ne $lastTick) {
            $lastPt = $curPt
            $lastTick = $curTick
            $idleTimer.Restart()
        }
    }
    $fgNow = [FastWin32]::GetForegroundWindow()
    $fgPid = [uint32]0
    [FastWin32]::GetWindowThreadProcessId($fgNow, [ref]$fgPid) | Out-Null
    $fgProc = Get-Process -Id $fgPid -ErrorAction SilentlyContinue
    $fgProcName = if ($fgProc) { $fgProc.ProcessName } else { "Unknown" }
    $fgTitle = if ($fgProc) { $fgProc.MainWindowTitle } else { "" }
    Save-TargetCapture -CaptureHwnd $fgNow
    Write-Output "UserAssisted_IdleFor2500ms_PausedAtStep=$currentStep CurrentForegroundProcess=$fgProcName CurrentForegroundTitle='$fgTitle' (用户已介入操作，严禁按旧计划继续，请读取最新桌面/前景窗口状态后再重新规划下一步)"
}

function Test-UserActiveElsewhereBeforeStart {
    $fg = [FastWin32]::GetForegroundWindow()
    if ($fg -eq [IntPtr]::Zero -or $fg -eq $script:callerHwnd -or $fg -eq $script:targetHwnd) {
        return $false
    }
    $lastTick = Get-LastInputTick
    $nowTick = [FastWin32]::GetTickCount()
    $elapsed = [int64](($nowTick - $lastTick) -band 0xFFFFFFFF)
    return ($elapsed -ge 0 -and $elapsed -lt 2500)
}

function Activate-TargetWindow {
    $fg = [FastWin32]::GetForegroundWindow()
    $alreadyForeground = ($fg -eq $script:targetHwnd)
    $alreadyMaximized = [FastWin32]::IsZoomed($script:targetHwnd)

    if ($alreadyForeground -and ($NoMaximize -or $alreadyMaximized)) {
        Update-ScriptInputBaseline
        return
    }

    $pidOut = [uint32]0
    $fgThread = [FastWin32]::GetWindowThreadProcessId($fg, [ref]$pidOut)
    $curThread = [FastWin32]::GetCurrentThreadId()
    [FastWin32]::AttachThreadInput($curThread, $fgThread, $true) | Out-Null

    if ($NoMaximize) {
        if ([FastWin32]::IsIconic($script:targetHwnd)) {
            [FastWin32]::ShowWindowAsync($script:targetHwnd, [FastWin32]::SW_RESTORE) | Out-Null
        }
    } else {
        if (-not $alreadyMaximized) {
            [FastWin32]::ShowWindowAsync($script:targetHwnd, [FastWin32]::SW_MAXIMIZE) | Out-Null
        }
    }

    if (-not $alreadyForeground) {
        [FastWin32]::SetForegroundWindow($script:targetHwnd) | Out-Null
        [FastWin32]::BringWindowToTop($script:targetHwnd) | Out-Null
    }
    [FastWin32]::AttachThreadInput($curThread, $fgThread, $false) | Out-Null
    Start-Sleep -Milliseconds 150
    Update-ScriptInputBaseline
}

function Assert-TargetFocused {
    $fg = [FastWin32]::GetForegroundWindow()
    $fgPid = [uint32]0
    [FastWin32]::GetWindowThreadProcessId($fg, [ref]$fgPid) | Out-Null
    if ($fgPid -ne $script:targetPid) {
        Write-Error "焦点已离开目标进程 (当前前台 PID=$fgPid，预期 PID=$($script:targetPid))，已安全中止后续操作。"
        exit 2
    }
}

function Resolve-PointFromSpec($rxVal, $ryVal, $xVal, $yVal, [bool]$isRelative) {
    $rect = New-Object FastWin32+RECT
    [FastWin32]::GetWindowRect($script:targetHwnd, [ref]$rect) | Out-Null

    if ($null -ne $rxVal -and $null -ne $ryVal) {
        $x = $rect.Left + [int]$rxVal
        $y = $rect.Top + [int]$ryVal
    } elseif ($isRelative) {
        $x = $rect.Left + [int]$xVal
        $y = $rect.Top + [int]$yVal
    } else {
        $x = [int]$xVal
        $y = [int]$yVal
    }

    if ($x -lt $rect.Left -or $x -gt $rect.Right -or $y -lt $rect.Top -or $y -gt $rect.Bottom) {
        Write-Error "坐标 ($x, $y) 超出目标窗口范围 [$($rect.Left), $($rect.Top), $($rect.Right), $($rect.Bottom)]，已拦截防止误点！"
        exit 4
    }
    return @($x, $y)
}

function Resolve-ClickPoint($act) {
    return Resolve-PointFromSpec $act.rx $act.ry $act.x $act.y ($act.relative -eq $true)
}

function Invoke-WinRTAwait($asyncOp, [Type]$resultType) {
    $asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
    })[0]
    $asTask = $asTaskGeneric.MakeGenericMethod($resultType)
    $netTask = $asTask.Invoke($null, @($asyncOp))
    $netTask.Wait()
    return $netTask.Result
}

function Get-RegionOcrText($act) {
    $rect = New-Object FastWin32+RECT
    [FastWin32]::GetWindowRect($script:targetHwnd, [ref]$rect) | Out-Null
    $rx = if ($null -ne $act.rx) { [int]$act.rx } else { 520 }
    $ry = if ($null -ne $act.ry) { [int]$act.ry } else { 30 }
    $rw = if ($null -ne $act.w)  { [int]$act.w }  else { 500 }
    $rh = if ($null -ne $act.h)  { [int]$act.h }  else { 70 }

    $vs = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $sx = [Math]::Max($vs.Left, [Math]::Min($rect.Left + $rx, $vs.Right - 2))
    $sy = [Math]::Max($vs.Top,  [Math]::Min($rect.Top  + $ry, $vs.Bottom - 2))
    $cw = [Math]::Max(2, [Math]::Min($rw, $vs.Right - $sx))
    $ch = [Math]::Max(2, [Math]::Min($rh, $vs.Bottom - $sy))

    $bmp = New-Object System.Drawing.Bitmap(($cw * 2), ($ch * 2))
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $srcBmp = New-Object System.Drawing.Bitmap($cw, $ch)
    $srcG = [System.Drawing.Graphics]::FromImage($srcBmp)
    $srcG.CopyFromScreen($sx, $sy, 0, 0, (New-Object System.Drawing.Size($cw, $ch)))
    $g.DrawImage($srcBmp, 0, 0, ($cw * 2), ($ch * 2))
    $srcG.Dispose()
    $srcBmp.Dispose()
    $g.Dispose()

    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    $ms.Position = 0

    $ras = [System.IO.WindowsRuntimeStreamExtensions]::AsRandomAccessStream($ms)
    $decoder = Invoke-WinRTAwait ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($ras)) ([Windows.Graphics.Imaging.BitmapDecoder])
    $softBmp = Invoke-WinRTAwait ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
    $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
    if ($null -eq $engine) {
        $lang = [Windows.Globalization.Language]::new("en-US")
        $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage($lang)
    }
    if ($null -eq $engine) {
        $ms.Dispose()
        Write-Error "系统无可用的 WinRT OCR 语言包，无法执行本地文字识别。"
        exit 7
    }
    $ocrRes = Invoke-WinRTAwait ($engine.RecognizeAsync($softBmp)) ([Windows.Media.Ocr.OcrResult])
    $ms.Dispose()

    return [ordered]@{
        rx   = $rx
        ry   = $ry
        w    = $cw
        h    = $ch
        raw  = $ocrRes.Text
        flat = ($ocrRes.Text -replace '\s+', '')
    }
}

function Assert-RegionOcr($act) {
    $expected = [string]$act.contains
    $res = Get-RegionOcrText $act
    Write-Output "LocalOCR($($res.rx),$($res.ry),$($res.w)x$($res.h))='$($res.flat)'"
    if ($res.flat -notlike "*$expected*") {
        Write-Error "本地顶栏 OCR 校验未通过：识别结果 '$($res.flat)' 不包含目标 '$expected'，已当场拦截发送以防发错人！"
        exit 7
    }
}

function Resolve-UiaElementCenter([string]$name) {
    $root = [System.Windows.Automation.AutomationElement]::FromHandle($script:targetHwnd)
    if (-not $root) {
        Write-Error "无法获取目标窗口的 UIA 根节点 (HWND=$($script:targetHwnd))"
        exit 6
    }
    $cond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::NameProperty,
        $name
    )
    $el = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
    if (-not $el) {
        $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
        foreach ($item in $all) {
            try {
                if ($item.Current.Name -and $item.Current.Name.Contains($name) -and -not $item.Current.IsOffscreen) {
                    $el = $item
                    break
                }
            } catch {}
        }
    }
    if (-not $el) {
        Write-Error "未在目标窗口中找到名为 '$name' 的原生 UIA 控件"
        exit 6
    }
    $b = $el.Current.BoundingRectangle
    if ($b.IsEmpty -or $b.Width -le 0 -or $b.Height -le 0) {
        Write-Error "UIA 控件 '$name' 的边界矩形无效"
        exit 6
    }
    $cx = [int]($b.Left + $b.Width / 2)
    $cy = [int]($b.Top + $b.Height / 2)
    return @($cx, $cy)
}

function Invoke-MouseClick([int]$x, [int]$y, [string]$kind) {
    [FastWin32]::SetCursorPos($x, $y) | Out-Null
    $script:lastClickScreen = @($x, $y)
    Start-Sleep -Milliseconds 35
    if ($kind -eq "rightclick") {
        [FastWin32]::mouse_event([FastWin32]::MOUSEEVENTF_RIGHTDOWN, 0, 0, 0, [UIntPtr]::Zero)
        [FastWin32]::mouse_event([FastWin32]::MOUSEEVENTF_RIGHTUP, 0, 0, 0, [UIntPtr]::Zero)
    } elseif ($kind -eq "dblclick") {
        [FastWin32]::mouse_event([FastWin32]::MOUSEEVENTF_LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
        [FastWin32]::mouse_event([FastWin32]::MOUSEEVENTF_LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
        Start-Sleep -Milliseconds 60
        [FastWin32]::mouse_event([FastWin32]::MOUSEEVENTF_LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
        [FastWin32]::mouse_event([FastWin32]::MOUSEEVENTF_LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    } else {
        [FastWin32]::mouse_event([FastWin32]::MOUSEEVENTF_LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
        [FastWin32]::mouse_event([FastWin32]::MOUSEEVENTF_LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    }
    Update-ScriptInputBaseline
}

if (Test-UserActiveElsewhereBeforeStart) {
    Wait-UserIdleAndYield -currentStep 0
    exit 0
}

Activate-TargetWindow
Assert-TargetFocused

$actions = $ActionsJson | ConvertFrom-Json
if ($actions -isnot [System.Array]) { $actions = @($actions) }

$savedClipboard = Backup-ClipboardState
$usedClipboard = $false
$yieldedToUser = $false

$step = 0
try {
    foreach ($act in $actions) {
        $step++
        if (Test-UserIntervened) {
            Wait-UserIdleAndYield -currentStep $step
            $yieldedToUser = $true
            break
        }
        Assert-TargetFocused
        switch ($act.type) {
            "click" {
                $pt = Resolve-ClickPoint $act
                Invoke-MouseClick -x $pt[0] -y $pt[1] -kind "click"
            }
            "dblclick" {
                $pt = Resolve-ClickPoint $act
                Invoke-MouseClick -x $pt[0] -y $pt[1] -kind "dblclick"
            }
            "rightclick" {
                $pt = Resolve-ClickPoint $act
                Invoke-MouseClick -x $pt[0] -y $pt[1] -kind "rightclick"
            }
            "clickName" {
                $pt = Resolve-UiaElementCenter ([string]$act.name)
                $kind = if ($act.button -eq "right") { "rightclick" } elseif ($act.double -eq $true) { "dblclick" } else { "click" }
                Invoke-MouseClick -x $pt[0] -y $pt[1] -kind $kind
            }
            "scroll" {
                if ($null -ne $act.rx -or $null -ne $act.x) {
                    $pt = Resolve-ClickPoint $act
                } else {
                    $rect = New-Object FastWin32+RECT
                    [FastWin32]::GetWindowRect($script:targetHwnd, [ref]$rect) | Out-Null
                    $pt = @([int](($rect.Left + $rect.Right) / 2), [int](($rect.Top + $rect.Bottom) / 2))
                }
                [FastWin32]::SetCursorPos($pt[0], $pt[1]) | Out-Null
                Start-Sleep -Milliseconds 25
                $clicks = if ($null -ne $act.clicks) { [int]$act.clicks } else { -3 }
                [FastWin32]::mouse_event([FastWin32]::MOUSEEVENTF_WHEEL, 0, 0, ($clicks * 120), [UIntPtr]::Zero)
                Update-ScriptInputBaseline
            }
            "drag" {
                $fromPt = Resolve-PointFromSpec $act.fromRx $act.fromRy $act.fromX $act.fromY ($act.relative -eq $true)
                $toPt   = Resolve-PointFromSpec $act.toRx $act.toRy $act.toX $act.toY ($act.relative -eq $true)
                $steps  = if ($null -ne $act.steps -and [int]$act.steps -gt 0) { [int]$act.steps } else { 10 }

                [FastWin32]::SetCursorPos($fromPt[0], $fromPt[1]) | Out-Null
                Start-Sleep -Milliseconds 35
                [FastWin32]::mouse_event([FastWin32]::MOUSEEVENTF_LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
                for ($i = 1; $i -le $steps; $i++) {
                    if (Test-UserIntervened) {
                        [FastWin32]::mouse_event([FastWin32]::MOUSEEVENTF_LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
                        Wait-UserIdleAndYield -currentStep $step
                        $yieldedToUser = $true
                        break
                    }
                    $ix = [int]($fromPt[0] + ($toPt[0] - $fromPt[0]) * ($i / $steps))
                    $iy = [int]($fromPt[1] + ($toPt[1] - $fromPt[1]) * ($i / $steps))
                    [FastWin32]::SetCursorPos($ix, $iy) | Out-Null
                    Update-ScriptInputBaseline
                    Start-Sleep -Milliseconds 12
                }
                if (-not $yieldedToUser) {
                    [FastWin32]::mouse_event([FastWin32]::MOUSEEVENTF_LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
                    $script:lastClickScreen = @($toPt[0], $toPt[1])
                    Update-ScriptInputBaseline
                }
            }
            "paste" {
                $usedClipboard = $true
                if ($act.clear -ne $false) {
                    [System.Windows.Forms.SendKeys]::SendWait("^a{BACKSPACE}")
                    Start-Sleep -Milliseconds 35
                }
                Set-ClipboardTextSafely ([string]$act.text)
                Start-Sleep -Milliseconds 35
                [System.Windows.Forms.SendKeys]::SendWait("^v")
                Start-Sleep -Milliseconds 90
                Update-ScriptInputBaseline
            }
            "typeText" {
                if ($act.clear -eq $true) {
                    [System.Windows.Forms.SendKeys]::SendWait("^a{BACKSPACE}")
                    Start-Sleep -Milliseconds 35
                }
                $escaped = Escape-SendKeysText ([string]$act.text)
                [System.Windows.Forms.SendKeys]::SendWait($escaped)
                Start-Sleep -Milliseconds 60
                Update-ScriptInputBaseline
            }
            "key" {
                [System.Windows.Forms.SendKeys]::SendWait([string]$act.keys)
                Update-ScriptInputBaseline
            }
            "assertOcr" {
                Assert-RegionOcr $act
            }
            "readOcr" {
                $res = Get-RegionOcrText $act
                $label = if ($act.label) { [string]$act.label } else { "$($res.rx),$($res.ry)" }
                Write-Output "ReadOCR[$label]=$($res.raw)"
            }
            "focusPopup" {
                $fg = [FastWin32]::GetForegroundWindow()
                $fgPid = [uint32]0
                [FastWin32]::GetWindowThreadProcessId($fg, [ref]$fgPid) | Out-Null
                if ($fg -ne [IntPtr]::Zero -and $fg -ne $script:targetHwnd -and $fgPid -eq $script:targetPid) {
                    $script:targetHwnd = $fg
                    Write-Output "FocusedPopupHWND=$($script:targetHwnd)"
                }
            }
            "wait" {
                $totalWait = [int]$act.ms
                $waited = 0
                while ($waited -lt $totalWait) {
                    $slice = [Math]::Min(60, $totalWait - $waited)
                    Start-Sleep -Milliseconds $slice
                    $waited += $slice
                    if (Test-UserIntervened) {
                        Wait-UserIdleAndYield -currentStep $step
                        $yieldedToUser = $true
                        break
                    }
                }
            }
            "waitTitle" {
                $expected = [string]$act.title
                $timeoutMs = if ($act.timeoutMs) { [int]$act.timeoutMs } else { 3000 }
                $sw = [System.Diagnostics.Stopwatch]::StartNew()
                $found = $null
                while ($sw.ElapsedMilliseconds -lt $timeoutMs) {
                    if (Test-UserIntervened) {
                        Wait-UserIdleAndYield -currentStep $step
                        $yieldedToUser = $true
                        break
                    }
                    $found = Get-Process | Where-Object {
                        $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like "*$expected*"
                    } | Select-Object -First 1
                    if ($found) { break }
                    Start-Sleep -Milliseconds 100
                }
                if ($yieldedToUser) { break }
                if (-not $found) {
                    Write-Error "等待窗口标题 '*$expected*' 超时 (${timeoutMs}ms)，已中止后续操作防止盲点！"
                    exit 5
                }
                $script:targetHwnd = $found.MainWindowHandle
                $script:targetPid = [uint32]$found.Id
                Activate-TargetWindow
            }
            default {
                Write-Error "未知动作类型: $($act.type) (步骤 $step)"
                exit 3
            }
        }
        if ($yieldedToUser) { break }
        Start-Sleep -Milliseconds 50
    }
} finally {
    if ($usedClipboard) {
        Restore-ClipboardState -State $savedClipboard
    }
}

if (-not $yieldedToUser) {
    Start-Sleep -Milliseconds 150
    Save-TargetCapture
    if ($ReturnFocus) {
        Start-Sleep -Milliseconds 120
        $callerScript = Join-Path $PSScriptRoot "focus-caller.ps1"
        if (Test-Path -LiteralPath $callerScript) {
            $retHwnd = if ($script:callerHwnd -eq $script:targetHwnd) { 0 } else { [int64]$script:callerHwnd }
            & $callerScript -TargetHwnd $retHwnd -TargetProcess $ReturnProcess | Out-Null
        }
    }
    Write-Output "FastActDone steps=$step pid=$($script:targetPid)"
}
