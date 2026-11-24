<#
.SYNOPSIS
    通用 Agent 宿主窗口记忆与置顶唤起脚本。
.DESCRIPTION
    优先级：
    1. 若指定 -TargetProcess，优先查找该进程主窗口；
    2. 否则若 -TargetHwnd 有效且窗口存在，直接唤起该调用方句柄；
    3. 否则按常见 AI Agent / IDE / 终端进程名列表顺序回退查找并置顶唤起。
#>
param(
    [int64]$TargetHwnd = 0,
    [string]$TargetProcess = "",
    [string[]]$FallbackProcesses = @(
        'Antigravity', 'Cursor', 'Windsurf', 'Trae',
        'WindowsTerminal', 'Code', 'Warp', 'pwsh', 'powershell'
    )
)

Add-Type @"
using System;
using System.Runtime.InteropServices;

public class Win32Focus {
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
    [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();

    public static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);
    public static readonly IntPtr HWND_NOTOPMOST = new IntPtr(-2);
    public const uint SWP_NOSIZE = 0x0001;
    public const uint SWP_NOMOVE = 0x0002;
    public const uint SWP_SHOWWINDOW = 0x0040;
    public const byte VK_MENU = 0x12;
    public const uint KEYEVENTF_EXTENDEDKEY = 0x0001;
    public const uint KEYEVENTF_KEYUP = 0x0002;
}
"@

$hwnd = [IntPtr]::Zero
$resolvedName = ""

if (-not [string]::IsNullOrWhiteSpace($TargetProcess)) {
    $proc = Get-Process -Name $TargetProcess -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne 0 } |
        Select-Object -First 1
    if ($proc) {
        $hwnd = $proc.MainWindowHandle
        $resolvedName = $proc.ProcessName
    }
}

if ($hwnd -eq [IntPtr]::Zero -and $TargetHwnd -ne 0) {
    $candidate = [IntPtr]$TargetHwnd
    if ([Win32Focus]::IsWindow($candidate)) {
        $hwnd = $candidate
        $resolvedName = "CallerHWND"
    }
}

if ($hwnd -eq [IntPtr]::Zero) {
    $allProcs = Get-Process | Where-Object { $_.MainWindowHandle -ne 0 }
    foreach ($name in $FallbackProcesses) {
        $match = $allProcs | Where-Object { $_.ProcessName -ieq $name } | Select-Object -First 1
        if ($match) {
            $hwnd = $match.MainWindowHandle
            $resolvedName = $match.ProcessName
            break
        }
    }
}

if ($hwnd -ne [IntPtr]::Zero) {
    $fg = [Win32Focus]::GetForegroundWindow()
    $pidOut = [uint32]0
    $fgThread = [Win32Focus]::GetWindowThreadProcessId($fg, [ref]$pidOut)
    $curThread = [Win32Focus]::GetCurrentThreadId()

    if ([Win32Focus]::IsIconic($hwnd)) {
        [Win32Focus]::ShowWindowAsync($hwnd, 9) | Out-Null
        Start-Sleep -Milliseconds 60
    }

    [Win32Focus]::AttachThreadInput($curThread, $fgThread, $true) | Out-Null
    [Win32Focus]::keybd_event([Win32Focus]::VK_MENU, 0, [Win32Focus]::KEYEVENTF_EXTENDEDKEY, [UIntPtr]::Zero)
    [Win32Focus]::keybd_event([Win32Focus]::VK_MENU, 0, [Win32Focus]::KEYEVENTF_EXTENDEDKEY -bor [Win32Focus]::KEYEVENTF_KEYUP, [UIntPtr]::Zero)
    [Win32Focus]::SetWindowPos($hwnd, [Win32Focus]::HWND_TOPMOST, 0, 0, 0, 0, [Win32Focus]::SWP_NOMOVE -bor [Win32Focus]::SWP_NOSIZE -bor [Win32Focus]::SWP_SHOWWINDOW) | Out-Null
    [Win32Focus]::SetForegroundWindow($hwnd) | Out-Null
    [Win32Focus]::BringWindowToTop($hwnd) | Out-Null
    [Win32Focus]::SetWindowPos($hwnd, [Win32Focus]::HWND_NOTOPMOST, 0, 0, 0, 0, [Win32Focus]::SWP_NOMOVE -bor [Win32Focus]::SWP_NOSIZE -bor [Win32Focus]::SWP_SHOWWINDOW) | Out-Null
    [Win32Focus]::AttachThreadInput($curThread, $fgThread, $false) | Out-Null

    Write-Output "FocusedCaller=$resolvedName HWND=$hwnd"
} else {
    Write-Output "FocusedCaller=None"
}
