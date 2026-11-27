param(
    [ValidateSet("Initialize","LoadFolders","Manage","AddFolder","RenameFolder","DeleteFolder","AddShortcut","RemoveShortcut","SetCustomIcon","ReorderShortcut","SetAnimation","ResetLayout","SyncMonitors")]
    [string]$Action = "Initialize",
    [string]$FolderId = "",
    [int]$FromIndex = -1,
    [int]$ToIndex = -1,
    [ValidateSet("ExpandCollapse","ElasticBounce","SubtlePop","Settle","VerticalBounce","Snap","Slide","Fade","None")]
    [string]$AnimStyle = "ExpandCollapse"
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class IconExtractor {
    [DllImport("shell32.dll", CharSet = CharSet.Auto)]
    public static extern uint ExtractIconEx(string szFileName, int nIconIndex, IntPtr[] phiconLarge, IntPtr[] phiconSmall, uint nIcons);
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool DestroyIcon(IntPtr hIcon);
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@ -ErrorAction SilentlyContinue

if (-not ([System.Management.Automation.PSTypeName]'MonitorMetricsHelper').Type) {
    Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;

public class MonitorMetricsInfo {
    public string Device;
    public bool IsPrimary;
    public int Dpi;
    public int ScreenX;
    public int ScreenY;
    public int ScreenW;
    public int ScreenH;
    public int WorkX;
    public int WorkY;
    public int WorkW;
    public int WorkH;
}

public class MonitorMetricsHelper {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct MONITORINFOEX {
        public int cbSize;
        public RECT rcMonitor;
        public RECT rcWork;
        public uint dwFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string szDevice;
    }

    private delegate bool MonitorEnumDelegate(IntPtr hMonitor, IntPtr hdcMonitor, ref RECT lprcMonitor, IntPtr dwData);

    [DllImport("user32.dll")]
    private static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr lprcClip, MonitorEnumDelegate lpfnEnum, IntPtr dwData);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern bool GetMonitorInfo(IntPtr hMonitor, ref MONITORINFOEX lpmi);

    [DllImport("user32.dll")]
    private static extern IntPtr SetThreadDpiAwarenessContext(IntPtr dpiContext);

    [DllImport("shcore.dll")]
    private static extern int GetDpiForMonitor(IntPtr hmonitor, int dpiType, out uint dpiX, out uint dpiY);

    [DllImport("shcore.dll")]
    private static extern int GetProcessDpiAwareness(IntPtr hprocess, out int awareness);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr OpenProcess(uint dwDesiredAccess, bool bInheritHandle, int dwProcessId);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr hObject);

    public static MonitorMetricsInfo[] GetMonitors() {
        var result = new List<MonitorMetricsInfo>();
        IntPtr prevCtx = IntPtr.Zero;
        try {
            // Switch only this thread temporarily to Per-Monitor-V2 to read true physical bounds & per-monitor DPI
            prevCtx = SetThreadDpiAwarenessContext(new IntPtr(-4));
        } catch { }

        try {
            EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, delegate(IntPtr hMon, IntPtr hdc, ref RECT rc, IntPtr data) {
                var mi = new MONITORINFOEX();
                mi.cbSize = Marshal.SizeOf(typeof(MONITORINFOEX));
                if (GetMonitorInfo(hMon, ref mi)) {
                    uint dpiX = 96, dpiY = 96;
                    try {
                        if (GetDpiForMonitor(hMon, 0, out dpiX, out dpiY) != 0 || dpiX == 0) {
                            dpiX = 96;
                        }
                    } catch {
                        dpiX = 96;
                    }
                    result.Add(new MonitorMetricsInfo {
                        Device = mi.szDevice ?? "",
                        IsPrimary = (mi.dwFlags & 1u) != 0,
                        Dpi = (int)dpiX,
                        ScreenX = mi.rcMonitor.Left,
                        ScreenY = mi.rcMonitor.Top,
                        ScreenW = mi.rcMonitor.Right - mi.rcMonitor.Left,
                        ScreenH = mi.rcMonitor.Bottom - mi.rcMonitor.Top,
                        WorkX = mi.rcWork.Left,
                        WorkY = mi.rcWork.Top,
                        WorkW = mi.rcWork.Right - mi.rcWork.Left,
                        WorkH = mi.rcWork.Bottom - mi.rcWork.Top
                    });
                }
                return true;
            }, IntPtr.Zero);
        } finally {
            if (prevCtx != IntPtr.Zero) {
                try { SetThreadDpiAwarenessContext(prevCtx); } catch { }
            }
        }
        return result.ToArray();
    }

    public static int GetRainmeterDpiAwareness() {
        Process[] procs = null;
        try {
            procs = Process.GetProcessesByName("Rainmeter");
            if (procs == null || procs.Length == 0) return -1;
            IntPtr hProc = OpenProcess(0x1000u, false, procs[0].Id);
            if (hProc == IntPtr.Zero) return -1;
            try {
                int awareness = -1;
                if (GetProcessDpiAwareness(hProc, out awareness) == 0) {
                    return awareness;
                }
            } finally {
                CloseHandle(hProc);
            }
        } catch { } finally {
            if (procs != null) {
                foreach (var p in procs) {
                    try { p.Dispose(); } catch { }
                }
            }
        }
        return -1;
    }
}
"@
}

# Hide the black console window while allowing Windows Forms GUI windows to display normally
$consoleHwnd = [IconExtractor]::GetConsoleWindow()
if ($consoleHwnd -ne [IntPtr]::Zero) {
    [void][IconExtractor]::ShowWindow($consoleHwnd, 0)
}
[System.Windows.Forms.Application]::EnableVisualStyles()

$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Resource = Join-Path $Root "@Resources"
$DataFile = Join-Path $Resource "Data.json"
$IconDir = Join-Path $Root "Icons"
if (!(Test-Path $IconDir)) {
    New-Item -ItemType Directory -Path $IconDir -Force | Out-Null
}
$FolderRoot = Join-Path $Root "Folders"
$FolderTemplate = Join-Path $Resource "FolderTemplate.inc"
$RainmeterExe = Join-Path $env:ProgramFiles "Rainmeter\Rainmeter.exe"
if (!(Test-Path $RainmeterExe)) {
    $RainmeterExe = Join-Path ${env:ProgramFiles(x86)} "Rainmeter\Rainmeter.exe"
}
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$MonitorMetricsFile = Join-Path $Resource "MonitorMetrics.lua"

function Normalize-HexColor([string]$HexColor) {
    if ([string]::IsNullOrWhiteSpace($HexColor)) { return "" }
    $clean = $HexColor.Trim().TrimStart('#')
    if ($clean -match '^[0-9A-Fa-f]{6}$') {
        return "#" + $clean.ToUpperInvariant()
    }
    return ""
}

function Blend-Rgb([int[]]$ColorA, [int[]]$ColorB, [double]$Weight) {
    $outR = [int][Math]::Round($ColorA[0] + (($ColorB[0] - $ColorA[0]) * $Weight))
    $outG = [int][Math]::Round($ColorA[1] + (($ColorB[1] - $ColorA[1]) * $Weight))
    $outB = [int][Math]::Round($ColorA[2] + (($ColorB[2] - $ColorA[2]) * $Weight))
    $outR = [Math]::Max(0, [Math]::Min(255, $outR))
    $outG = [Math]::Max(0, [Math]::Min(255, $outG))
    $outB = [Math]::Max(0, [Math]::Min(255, $outB))
    return "$outR,$outG,$outB"
}

function Get-FolderTintPalette([string]$AccentHex) {
    $norm = Normalize-HexColor $AccentHex
    if ([string]::IsNullOrEmpty($norm)) {
        return [ordered]@{
            FolderAccent        = ""
            FolderFillTopRGB    = "38,43,56"
            FolderFillRGB       = "30,34,44"
            FolderFillBotRGB    = "23,26,35"
            FolderBorderRGB     = "255,255,255"
            FolderBorderAlpha   = 65
            FolderGlowRGB       = "255,255,255"
            FolderGlowAlpha     = 65
            FolderOuterGlowA1   = 26
            FolderOuterGlowA2   = 10
            PopupFillTopRGB     = "28,32,43"
            PopupFillRGB        = "22,25,34"
            PopupFillBotRGB     = "17,20,28"
            PopupBorderRGB      = "255,255,255"
            PopupBorderAlpha    = 55
            PopupInnerGlowRGB   = "255,255,255"
            PopupInnerGlowAlpha = 65
            PopupGlowRGB        = "0,0,0"
            PopupGlowA1         = 34
            PopupGlowA2         = 21
            PopupGlowA3         = 11
            PopupGlowA4         = 5
            SelFillRGB          = "130,175,255"
            SelBorderRGB        = "140,190,255"
        }
    }

    $r = [Convert]::ToInt32($norm.Substring(1, 2), 16)
    $g = [Convert]::ToInt32($norm.Substring(3, 2), 16)
    $b = [Convert]::ToInt32($norm.Substring(5, 2), 16)
    $raw = @($r, $g, $b)
    $white = @(255, 255, 255)

    # Luminance-aware balancing keeps bright tints deep/legible and dark tints visibly rimmed
    $lum = ((0.299 * $r) + (0.587 * $g) + (0.114 * $b)) / 255.0
    $fillScale = if ($lum -gt 0.75) { 0.72 } elseif ($lum -gt 0.55) { 0.88 } else { 1.0 }
    $fillAccent = @(
        [int][Math]::Round($r * $fillScale),
        [int][Math]::Round($g * $fillScale),
        [int][Math]::Round($b * $fillScale)
    )

    $rimLift = if ($lum -lt 0.25) { 0.35 } else { 0.18 }
    $glowLift = if ($lum -lt 0.25) { 0.22 } else { 0.08 }
    $rimAccent = @(
        [int][Math]::Round($r + ((255 - $r) * $rimLift)),
        [int][Math]::Round($g + ((255 - $g) * $rimLift)),
        [int][Math]::Round($b + ((255 - $b) * $rimLift))
    )

    return [ordered]@{
        FolderAccent        = $norm
        FolderFillTopRGB    = (Blend-Rgb @(38, 43, 56) $fillAccent 0.34)
        FolderFillRGB       = (Blend-Rgb @(30, 34, 44) $fillAccent 0.27)
        FolderFillBotRGB    = (Blend-Rgb @(22, 25, 34) $fillAccent 0.20)
        FolderBorderRGB     = (Blend-Rgb $white $rimAccent 0.72)
        FolderBorderAlpha   = 125
        FolderGlowRGB       = (Blend-Rgb $white $rimAccent 0.42)
        FolderGlowAlpha     = 95
        FolderOuterGlowA1   = 38
        FolderOuterGlowA2   = 16
        PopupFillTopRGB     = (Blend-Rgb @(28, 32, 43) $fillAccent 0.18)
        PopupFillRGB        = (Blend-Rgb @(22, 25, 34) $fillAccent 0.13)
        PopupFillBotRGB     = (Blend-Rgb @(17, 20, 28) $fillAccent 0.09)
        PopupBorderRGB      = (Blend-Rgb $white $rimAccent 0.75)
        PopupBorderAlpha    = 115
        PopupInnerGlowRGB   = (Blend-Rgb $white $rimAccent 0.50)
        PopupInnerGlowAlpha = 90
        PopupGlowRGB        = (Blend-Rgb $raw $white $glowLift)
        PopupGlowA1         = 46
        PopupGlowA2         = 28
        PopupGlowA3         = 15
        PopupGlowA4         = 7
        SelFillRGB          = (Blend-Rgb $white $rimAccent 0.78)
        SelBorderRGB        = (Blend-Rgb $white $rimAccent 0.85)
    }
}

function Write-MonitorMetrics {
    try {
        $mons = @([MonitorMetricsHelper]::GetMonitors())
        if ($mons.Count -eq 0) { return }
        $awareness = [MonitorMetricsHelper]::GetRainmeterDpiAwareness()
        $primaryDpi = 96
        foreach ($m in $mons) {
            if ($m.IsPrimary -and $m.Dpi -gt 0) {
                $primaryDpi = [int]$m.Dpi
                break
            }
        }

        $lines = New-Object System.Collections.Generic.List[string]
        $lines.Add("-- Auto-generated by FolderManager.ps1 (Per-Monitor-V2 DPI & physical display metrics)")
        $lines.Add("return {")
        $lines.Add("    primaryDpi = $primaryDpi,")
        $lines.Add("    rainmeterDpiAwareness = $awareness,")
        $lines.Add("    monitors = {")
        foreach ($m in $mons) {
            $primStr = if ($m.IsPrimary) { "true" } else { "false" }
            $lines.Add("        { isPrimary = $primStr, dpi = $($m.Dpi), sx = $($m.ScreenX), sy = $($m.ScreenY), sw = $($m.ScreenW), sh = $($m.ScreenH), wx = $($m.WorkX), wy = $($m.WorkY), ww = $($m.WorkW), wh = $($m.WorkH) },")
        }
        $lines.Add("    }")
        $lines.Add("}")

        $newContent = ($lines -join "`r`n") + "`r`n"
        if (Test-Path $MonitorMetricsFile) {
            $oldContent = [IO.File]::ReadAllText($MonitorMetricsFile, $Utf8NoBom)
            if ($oldContent -eq $newContent) { return }
        }
        [IO.File]::WriteAllText($MonitorMetricsFile, $newContent, $Utf8NoBom)
    } catch {
        # Non-fatal: FolderPopup.lua falls back cleanly to live Rainmeter monitor variables
    }
}

function Invoke-RainmeterBangs([string[]]$Bangs) {
    if (!(Test-Path $RainmeterExe) -or !$Bangs -or $Bangs.Count -eq 0) { return }
    $sb = New-Object System.Text.StringBuilder
    foreach ($bang in $Bangs) {
        if ([string]::IsNullOrEmpty($bang)) { continue }
        if ($sb.Length -gt 0 -and ($sb.Length + $bang.Length) -gt 6000) {
            Start-Process -FilePath $RainmeterExe -ArgumentList $sb.ToString() -WindowStyle Hidden
            [void]$sb.Clear()
        }
        [void]$sb.Append($bang)
    }
    if ($sb.Length -gt 0) {
        Start-Process -FilePath $RainmeterExe -ArgumentList $sb.ToString() -WindowStyle Hidden
    }
}

function Load-UnlockedImage([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    $ms = New-Object IO.MemoryStream(,$bytes)
    try {
        $tmp = [Drawing.Image]::FromStream($ms)
        try {
            return New-Object Drawing.Bitmap($tmp)
        } finally {
            $tmp.Dispose()
        }
    } finally {
        $ms.Dispose()
    }
}

function Save-IconAsPng([string]$SourcePath, [string]$DestinationPath) {
    $bmp = Load-UnlockedImage $SourcePath
    try {
        $bmp.Save($DestinationPath, [Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $bmp.Dispose()
    }
}

function Add-ShortcutsToFolder($Folder, [string[]]$Paths) {
    if (!$Folder -or !$Paths -or $Paths.Count -eq 0) { return 0 }
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($existing in @($Folder.shortcuts)) { [void]$list.Add($existing) }

    $shell = $null
    $added = 0
    try {
        foreach ($path in $Paths) {
            if ([string]::IsNullOrWhiteSpace($path) -or !(Test-Path -LiteralPath $path)) { continue }
            if ($null -eq $shell -and [IO.Path]::GetExtension($path).Equals(".lnk", [StringComparison]::OrdinalIgnoreCase)) {
                $shell = New-Object -ComObject WScript.Shell
            }
            $defaultName = [IO.Path]::GetFileNameWithoutExtension($path)
            $iconFile = "app_" + [Guid]::NewGuid().ToString("N") + ".png"
            Extract-Icon $path (Join-Path $IconDir $iconFile) $shell
            $newApp = [pscustomobject]@{
                id   = [Guid]::NewGuid().ToString("N")
                name = $defaultName
                path = $path
                icon = $iconFile
            }
            [void]$list.Add($newApp)
            $added++
        }
    } finally {
        if ($null -ne $shell) {
            [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
        }
    }

    if ($added -gt 0) {
        $Folder.shortcuts = @($list)
    }
    return $added
}

function Remove-OrphanedIcons($Data, [string[]]$ExistingIconPaths = $null) {
    if (!(Test-Path $IconDir)) { return }
    $referenced = New-Object "System.Collections.Generic.HashSet[string]" ([StringComparer]::OrdinalIgnoreCase)
    foreach ($f in @($Data.folders)) {
        if ($f.PSObject.Properties['icon'] -and ![string]::IsNullOrWhiteSpace([string]$f.icon)) {
            [void]$referenced.Add([string]$f.icon)
        }
        foreach ($s in @($f.shortcuts)) {
            if ($s.PSObject.Properties['icon'] -and ![string]::IsNullOrWhiteSpace([string]$s.icon)) {
                [void]$referenced.Add([string]$s.icon)
            }
        }
    }

    $files = if ($null -ne $ExistingIconPaths) { $ExistingIconPaths } else { [IO.Directory]::GetFiles($IconDir) }
    foreach ($filePath in $files) {
        $fileName = [IO.Path]::GetFileName($filePath)
        if ($fileName -match '^(app|custom|folder)_.+\.png$' -and !$referenced.Contains($fileName)) {
            Remove-Item -LiteralPath $filePath -Force -ErrorAction SilentlyContinue
        }
    }
}


if (-not ([System.Management.Automation.PSTypeName]'ModernSlider').Type) {
    Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public static class ModernWin32 {
    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, string lParam);

    public static void SetDarkTitleBar(IntPtr hwnd, bool enabled) {
        if (hwnd == IntPtr.Zero) return;
        try {
            int val = enabled ? 1 : 0;
            if (DwmSetWindowAttribute(hwnd, 20, ref val, sizeof(int)) != 0) {
                DwmSetWindowAttribute(hwnd, 19, ref val, sizeof(int));
            }
        } catch { }
    }

    public static void SetCueBanner(IntPtr hwnd, string text) {
        if (hwnd == IntPtr.Zero) return;
        try {
            SendMessage(hwnd, 0x1501, new IntPtr(1), text ?? "");
        } catch { }
    }

    public static GraphicsPath CreateRoundRect(RectangleF rect, float radius) {
        GraphicsPath path = new GraphicsPath();
        if (radius <= 0.5f || rect.Width <= 1f || rect.Height <= 1f) {
            path.AddRectangle(rect);
            return path;
        }
        float d = Math.Min(radius * 2f, Math.Min(rect.Width, rect.Height));
        path.AddArc(rect.X, rect.Y, d, d, 180f, 90f);
        path.AddArc(rect.Right - d, rect.Y, d, d, 270f, 90f);
        path.AddArc(rect.Right - d, rect.Bottom - d, d, d, 0f, 90f);
        path.AddArc(rect.X, rect.Bottom - d, d, d, 90f, 90f);
        path.CloseFigure();
        return path;
    }
}

public class ModernListView : ListView {
    public ModernListView() {
        this.DoubleBuffered = true;
        this.SetStyle(ControlStyles.OptimizedDoubleBuffer | ControlStyles.EnableNotifyMessage, true);
    }
}

public class ModernCard : Panel {
    public int CornerRadius { get; set; }
    public Color OuterBackColor { get; set; }
    public Color CardBackColor { get; set; }
    public Color BorderColor { get; set; }
    public bool DrawBorder { get; set; }
    public bool DrawRightDivider { get; set; }

    public ModernCard() {
        this.DoubleBuffered = true;
        this.ResizeRedraw = true;
        this.CornerRadius = 10;
        this.DrawBorder = true;
        this.DrawRightDivider = false;
        this.OuterBackColor = Color.FromArgb(15, 18, 25);
        this.CardBackColor = Color.FromArgb(26, 31, 44);
        this.BorderColor = Color.FromArgb(41, 49, 69);
    }

    protected override void OnPaint(PaintEventArgs e) {
        Graphics g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        if (this.DrawRightDivider) {
            using (SolidBrush bg = new SolidBrush(this.CardBackColor)) {
                g.FillRectangle(bg, this.ClientRectangle);
            }
            using (Pen pen = new Pen(this.BorderColor, 1f)) {
                g.DrawLine(pen, this.Width - 1, 0, this.Width - 1, this.Height);
            }
            return;
        }

        using (SolidBrush outer = new SolidBrush(this.OuterBackColor)) {
            g.FillRectangle(outer, this.ClientRectangle);
        }

        RectangleF rect = new RectangleF(0.5f, 0.5f, Math.Max(1f, this.Width - 1.5f), Math.Max(1f, this.Height - 1.5f));
        using (GraphicsPath path = ModernWin32.CreateRoundRect(rect, this.CornerRadius)) {
            using (SolidBrush fill = new SolidBrush(this.CardBackColor)) {
                g.FillPath(fill, path);
            }
            if (this.DrawBorder) {
                using (Pen pen = new Pen(this.BorderColor, 1f)) {
                    g.DrawPath(pen, path);
                }
            }
        }
    }
}

public class ModernButton : Control {
    private bool _hover = false;
    private bool _pressed = false;
    private bool _isActive = false;
    private string _subtitle = "";

    public int CornerRadius { get; set; }
    public Color OuterBackColor { get; set; }
    public Color FillColor { get; set; }
    public Color HoverColor { get; set; }
    public Color PressColor { get; set; }
    public Color BorderColor { get; set; }
    public Color ActiveFillColor { get; set; }
    public Color ActiveBorderColor { get; set; }
    public Color ActiveTextColor { get; set; }
    public Color DisabledFillColor { get; set; }
    public Color DisabledTextColor { get; set; }
    public Color SubtitleColor { get; set; }
    public bool AlignLeft { get; set; }
    public bool ShowActiveBar { get; set; }
    public Color ActiveBarColor { get; set; }
    public int TextPaddingLeft { get; set; }

    public bool IsActive {
        get { return _isActive; }
        set {
            if (_isActive != value) {
                _isActive = value;
                this.Invalidate();
            }
        }
    }

    public string Subtitle {
        get { return _subtitle; }
        set {
            string v = value ?? "";
            if (_subtitle != v) {
                _subtitle = v;
                this.Invalidate();
            }
        }
    }

    public ModernButton() {
        this.SetStyle(
            ControlStyles.AllPaintingInWmPaint |
            ControlStyles.UserPaint |
            ControlStyles.OptimizedDoubleBuffer |
            ControlStyles.ResizeRedraw |
            ControlStyles.Selectable,
            true
        );
        this.CornerRadius = 7;
        this.TextPaddingLeft = 12;
        this.OuterBackColor = Color.FromArgb(15, 18, 25);
        this.FillColor = Color.FromArgb(35, 42, 59);
        this.HoverColor = Color.FromArgb(46, 55, 76);
        this.PressColor = Color.FromArgb(29, 35, 49);
        this.BorderColor = Color.FromArgb(54, 64, 88);
        this.ActiveFillColor = Color.FromArgb(37, 99, 235);
        this.ActiveBorderColor = Color.FromArgb(59, 130, 246);
        this.ActiveTextColor = Color.White;
        this.DisabledFillColor = Color.FromArgb(22, 26, 37);
        this.DisabledTextColor = Color.FromArgb(86, 97, 118);
        this.SubtitleColor = Color.FromArgb(148, 163, 184);
        this.ActiveBarColor = Color.FromArgb(59, 130, 246);
        this.ForeColor = Color.FromArgb(241, 245, 249);
        this.Cursor = Cursors.Hand;
    }

    public void PerformClick() {
        if (this.Enabled) {
            this.OnClick(EventArgs.Empty);
        }
    }

    protected override void OnEnabledChanged(EventArgs e) {
        base.OnEnabledChanged(e);
        this.Cursor = this.Enabled ? Cursors.Hand : Cursors.Default;
        if (!this.Enabled) {
            _hover = false;
            _pressed = false;
        }
        this.Invalidate();
    }

    protected override void OnTextChanged(EventArgs e) {
        base.OnTextChanged(e);
        this.Invalidate();
    }

    protected override void OnMouseEnter(EventArgs e) {
        base.OnMouseEnter(e);
        if (this.Enabled) { _hover = true; this.Invalidate(); }
    }

    protected override void OnMouseLeave(EventArgs e) {
        base.OnMouseLeave(e);
        _hover = false;
        _pressed = false;
        this.Invalidate();
    }

    protected override void OnMouseDown(MouseEventArgs e) {
        base.OnMouseDown(e);
        if (this.Enabled && e.Button == MouseButtons.Left) {
            _pressed = true;
            this.Focus();
            this.Invalidate();
        }
    }

    protected override void OnMouseUp(MouseEventArgs e) {
        base.OnMouseUp(e);
        if (_pressed) {
            _pressed = false;
            this.Invalidate();
            if (this.Enabled && e.Button == MouseButtons.Left && this.ClientRectangle.Contains(e.Location)) {
                this.OnClick(EventArgs.Empty);
            }
        }
    }

    protected override void OnKeyDown(KeyEventArgs e) {
        base.OnKeyDown(e);
        if (this.Enabled && (e.KeyCode == Keys.Space || e.KeyCode == Keys.Enter)) {
            this.OnClick(EventArgs.Empty);
            e.Handled = true;
        }
    }

    protected override void OnPaint(PaintEventArgs e) {
        Graphics g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;

        using (SolidBrush outer = new SolidBrush(this.OuterBackColor)) {
            g.FillRectangle(outer, this.ClientRectangle);
        }

        Color fill = this.FillColor;
        Color border = this.BorderColor;
        Color textCol = this.ForeColor;

        if (!this.Enabled) {
            fill = this.DisabledFillColor;
            border = (this.BorderColor.A > 0) ? Color.FromArgb(90, this.BorderColor) : Color.Transparent;
            textCol = this.DisabledTextColor;
        } else if (_isActive) {
            fill = _pressed ? this.PressColor : this.ActiveFillColor;
            border = this.ActiveBorderColor;
            textCol = this.ActiveTextColor;
        } else if (_pressed) {
            fill = this.PressColor;
        } else if (_hover) {
            fill = this.HoverColor;
        }

        RectangleF rect = new RectangleF(0.5f, 0.5f, Math.Max(1f, this.Width - 1.5f), Math.Max(1f, this.Height - 1.5f));
        using (GraphicsPath path = ModernWin32.CreateRoundRect(rect, this.CornerRadius)) {
            using (SolidBrush b = new SolidBrush(fill)) {
                g.FillPath(b, path);
            }
            if (border.A > 0) {
                using (Pen p = new Pen(border, _isActive ? 1.25f : 1f)) {
                    g.DrawPath(p, path);
                }
            }
        }

        if (_isActive && this.ShowActiveBar) {
            RectangleF barRect = new RectangleF(3f, 7f, 3.5f, Math.Max(6f, this.Height - 14f));
            using (GraphicsPath barPath = ModernWin32.CreateRoundRect(barRect, 2f)) {
                using (SolidBrush barBrush = new SolidBrush(this.ActiveBarColor)) {
                    g.FillPath(barBrush, barPath);
                }
            }
        }

        if (!string.IsNullOrEmpty(_subtitle)) {
            Rectangle titleRect = new Rectangle(10, 5, Math.Max(1, this.Width - 20), 18);
            Rectangle subRect = new Rectangle(10, 22, Math.Max(1, this.Width - 20), 16);
            TextFormatFlags tf = TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix;
            using (Font subFont = new Font(this.Font.FontFamily, 8f, FontStyle.Regular)) {
                TextRenderer.DrawText(g, this.Text, this.Font, titleRect, textCol, tf);
                Color sc = _isActive ? Color.FromArgb(215, textCol) : (this.Enabled ? this.SubtitleColor : this.DisabledTextColor);
                TextRenderer.DrawText(g, _subtitle, subFont, subRect, sc, tf);
            }
        } else {
            TextFormatFlags tf = TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix;
            Rectangle textRect;
            if (this.AlignLeft) {
                tf |= TextFormatFlags.Left;
                int padL = this.TextPaddingLeft;
                textRect = new Rectangle(padL, 0, Math.Max(1, this.Width - padL - 8), this.Height);
            } else {
                tf |= TextFormatFlags.HorizontalCenter;
                textRect = new Rectangle(4, 0, Math.Max(1, this.Width - 8), this.Height);
            }
            TextRenderer.DrawText(g, this.Text, this.Font, textRect, textCol, tf);
        }
    }
}

public class ModernSwatch : Control {
    private bool _hover = false;
    private bool _selected = false;

    public Color OuterBackColor { get; set; }
    public Color SwatchColor { get; set; }
    public Color RingColor { get; set; }
    public Color HoverRingColor { get; set; }
    public bool IsNeutralDefault { get; set; }

    public bool IsSelected {
        get { return _selected; }
        set {
            if (_selected != value) {
                _selected = value;
                this.Invalidate();
            }
        }
    }

    public ModernSwatch() {
        this.SetStyle(
            ControlStyles.AllPaintingInWmPaint |
            ControlStyles.UserPaint |
            ControlStyles.OptimizedDoubleBuffer |
            ControlStyles.ResizeRedraw,
            true
        );
        this.Size = new Size(24, 24);
        this.OuterBackColor = Color.FromArgb(26, 31, 44);
        this.SwatchColor = Color.FromArgb(59, 130, 246);
        this.RingColor = Color.White;
        this.HoverRingColor = Color.FromArgb(148, 163, 184);
        this.Cursor = Cursors.Hand;
    }

    protected override void OnEnabledChanged(EventArgs e) {
        base.OnEnabledChanged(e);
        this.Cursor = this.Enabled ? Cursors.Hand : Cursors.Default;
        this.Invalidate();
    }

    protected override void OnMouseEnter(EventArgs e) {
        base.OnMouseEnter(e);
        if (this.Enabled) { _hover = true; this.Invalidate(); }
    }

    protected override void OnMouseLeave(EventArgs e) {
        base.OnMouseLeave(e);
        _hover = false;
        this.Invalidate();
    }

    protected override void OnMouseUp(MouseEventArgs e) {
        base.OnMouseUp(e);
        if (this.Enabled && e.Button == MouseButtons.Left && this.ClientRectangle.Contains(e.Location)) {
            this.OnClick(EventArgs.Empty);
        }
    }

    protected override void OnPaint(PaintEventArgs e) {
        Graphics g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;

        using (SolidBrush outer = new SolidBrush(this.OuterBackColor)) {
            g.FillRectangle(outer, this.ClientRectangle);
        }

        float size = Math.Min(this.Width, this.Height) - 2f;
        float pad = 1f;

        if (_selected) {
            using (Pen ring = new Pen(this.RingColor, 2f)) {
                g.DrawEllipse(ring, pad + 0.5f, pad + 0.5f, size - 1f, size - 1f);
            }
        } else if (_hover && this.Enabled) {
            using (Pen ring = new Pen(this.HoverRingColor, 1.5f)) {
                g.DrawEllipse(ring, pad + 0.5f, pad + 0.5f, size - 1f, size - 1f);
            }
        }

        float inset = _selected ? 4f : 3f;
        RectangleF circle = new RectangleF(inset, inset, Math.Max(4f, this.Width - inset * 2f), Math.Max(4f, this.Height - inset * 2f));
        Color fillCol = this.Enabled ? this.SwatchColor : Color.FromArgb(110, this.SwatchColor);

        if (this.IsNeutralDefault) {
            Color topCol = Color.FromArgb(fillCol.A, Math.Min(255, fillCol.R + 40), Math.Min(255, fillCol.G + 44), Math.Min(255, fillCol.B + 54));
            using (LinearGradientBrush gb = new LinearGradientBrush(circle, topCol, fillCol, 135f)) {
                g.FillEllipse(gb, circle);
            }
        } else {
            using (SolidBrush sb = new SolidBrush(fillCol)) {
                g.FillEllipse(sb, circle);
            }
        }

        using (Pen edge = new Pen(Color.FromArgb(80, 0, 0, 0), 1f)) {
            g.DrawEllipse(edge, circle);
        }
    }
}

public class ModernSlider : Control {
    private int _min = 0;
    private int _max = 100;
    private int _val = 100;
    private bool _hover = false;
    private bool _dragging = false;

    public Color OuterBackColor { get; set; }
    public Color TrackColor { get; set; }
    public Color FillColor { get; set; }
    public Color ThumbColor { get; set; }
    public Color ThumbBorderColor { get; set; }

    public event EventHandler ValueChanged;
    public event EventHandler ValueCommitted;

    public int Minimum {
        get { return _min; }
        set { _min = value; if (_val < _min) _val = _min; this.Invalidate(); }
    }

    public int Maximum {
        get { return _max; }
        set { _max = value; if (_val > _max) _val = _max; this.Invalidate(); }
    }

    public int Value {
        get { return _val; }
        set {
            int clamped = Math.Max(_min, Math.Min(_max, value));
            if (_val != clamped) {
                _val = clamped;
                this.Invalidate();
            }
        }
    }

    public ModernSlider() {
        this.SetStyle(
            ControlStyles.AllPaintingInWmPaint |
            ControlStyles.UserPaint |
            ControlStyles.OptimizedDoubleBuffer |
            ControlStyles.ResizeRedraw |
            ControlStyles.Selectable,
            true
        );
        this.Height = 26;
        this.OuterBackColor = Color.FromArgb(26, 31, 44);
        this.TrackColor = Color.FromArgb(48, 57, 78);
        this.FillColor = Color.FromArgb(59, 130, 246);
        this.ThumbColor = Color.White;
        this.ThumbBorderColor = Color.FromArgb(59, 130, 246);
        this.Cursor = Cursors.Hand;
    }

    private void SetFromX(int mouseX) {
        int pad = 9;
        int trackW = Math.Max(1, this.Width - (pad * 2));
        double ratio = (double)(mouseX - pad) / (double)trackW;
        if (ratio < 0.0) ratio = 0.0;
        if (ratio > 1.0) ratio = 1.0;
        int nextVal = _min + (int)Math.Round(ratio * (_max - _min));
        if (nextVal != _val) {
            _val = nextVal;
            this.Invalidate();
            EventHandler h = ValueChanged;
            if (h != null) h(this, EventArgs.Empty);
        }
    }

    protected override void OnMouseEnter(EventArgs e) {
        base.OnMouseEnter(e);
        _hover = true;
        this.Invalidate();
    }

    protected override void OnMouseLeave(EventArgs e) {
        base.OnMouseLeave(e);
        _hover = false;
        this.Invalidate();
    }

    protected override void OnMouseDown(MouseEventArgs e) {
        base.OnMouseDown(e);
        if (e.Button == MouseButtons.Left) {
            _dragging = true;
            this.Focus();
            SetFromX(e.X);
            this.Invalidate();
        }
    }

    protected override void OnMouseMove(MouseEventArgs e) {
        base.OnMouseMove(e);
        if (_dragging) {
            SetFromX(e.X);
        }
    }

    protected override void OnMouseUp(MouseEventArgs e) {
        base.OnMouseUp(e);
        if (_dragging) {
            _dragging = false;
            SetFromX(e.X);
            this.Invalidate();
            EventHandler h = ValueCommitted;
            if (h != null) h(this, EventArgs.Empty);
        }
    }

    protected override bool IsInputKey(Keys keyData) {
        if (keyData == Keys.Left || keyData == Keys.Right) return true;
        return base.IsInputKey(keyData);
    }

    protected override void OnKeyDown(KeyEventArgs e) {
        base.OnKeyDown(e);
        int delta = 0;
        if (e.KeyCode == Keys.Left) delta = -2;
        else if (e.KeyCode == Keys.Right) delta = 2;
        if (delta != 0) {
            int nextVal = Math.Max(_min, Math.Min(_max, _val + delta));
            if (nextVal != _val) {
                _val = nextVal;
                this.Invalidate();
                EventHandler h1 = ValueChanged;
                if (h1 != null) h1(this, EventArgs.Empty);
                EventHandler h2 = ValueCommitted;
                if (h2 != null) h2(this, EventArgs.Empty);
            }
            e.Handled = true;
        }
    }

    protected override void OnPaint(PaintEventArgs e) {
        Graphics g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;

        using (SolidBrush outer = new SolidBrush(this.OuterBackColor)) {
            g.FillRectangle(outer, this.ClientRectangle);
        }

        int pad = 9;
        float trackW = Math.Max(4f, this.Width - (pad * 2f));
        float trackH = 5f;
        float trackY = (this.Height - trackH) / 2f;

        RectangleF trackRect = new RectangleF(pad, trackY, trackW, trackH);
        using (GraphicsPath tp = ModernWin32.CreateRoundRect(trackRect, 2.5f)) {
            using (SolidBrush tb = new SolidBrush(this.TrackColor)) {
                g.FillPath(tb, tp);
            }
        }

        float ratio = (_max > _min) ? (float)(_val - _min) / (float)(_max - _min) : 0f;
        float thumbX = pad + (ratio * trackW);
        float fillW = Math.Max(0f, thumbX - pad);

        if (fillW > 1f) {
            RectangleF fillRect = new RectangleF(pad, trackY, fillW, trackH);
            using (GraphicsPath fp = ModernWin32.CreateRoundRect(fillRect, 2.5f)) {
                using (SolidBrush fb = new SolidBrush(this.FillColor)) {
                    g.FillPath(fb, fp);
                }
            }
        }

        float thumbR = (_dragging || _hover) ? 7.5f : 6.5f;
        if (_hover || _dragging) {
            float haloR = thumbR + 3.5f;
            using (SolidBrush hb = new SolidBrush(Color.FromArgb(45, this.FillColor))) {
                g.FillEllipse(hb, thumbX - haloR, (this.Height / 2f) - haloR, haloR * 2f, haloR * 2f);
            }
        }

        RectangleF thumbRect = new RectangleF(thumbX - thumbR, (this.Height / 2f) - thumbR, thumbR * 2f, thumbR * 2f);
        using (SolidBrush thb = new SolidBrush(this.ThumbColor)) {
            g.FillEllipse(thb, thumbRect);
        }
        using (Pen thp = new Pen(this.ThumbBorderColor, 2f)) {
            g.DrawEllipse(thp, thumbRect);
        }
    }
}
"@
}

function Show-TextPrompt([string]$Title, [string]$Prompt, [string]$Default = "") {
    $form = New-Object Windows.Forms.Form
    $form.Text = $Title; $form.Width = 420; $form.Height = 155
    $form.TopMost = $true
    $form.StartPosition = "CenterScreen"; $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false; $form.MinimizeBox = $false
    $label = New-Object Windows.Forms.Label
    $label.Text = $Prompt; $label.Left = 12; $label.Top = 12; $label.Width = 380; $label.Height = 22
    $box = New-Object Windows.Forms.TextBox
    $box.Left = 12; $box.Top = 40; $box.Width = 380; $box.Text = $Default
    $ok = New-Object Windows.Forms.Button
    $ok.Text = "OK"; $ok.Left = 226; $ok.Top = 76; $ok.Width = 78; $ok.DialogResult = "OK"
    $cancel = New-Object Windows.Forms.Button
    $cancel.Text = "Cancel"; $cancel.Left = 314; $cancel.Top = 76; $cancel.Width = 78; $cancel.DialogResult = "Cancel"
    $form.Controls.AddRange(@($label,$box,$ok,$cancel))
    $form.AcceptButton = $ok; $form.CancelButton = $cancel
    $result = $form.ShowDialog()
    $value = if ($result -eq "OK") { $box.Text.Trim() } else { $null }
    $form.Dispose()
    return $value
}

function Select-Item([string]$Title, [string[]]$Items) {
    if (!$Items -or $Items.Count -eq 0) { [Windows.Forms.MessageBox]::Show("Nothing to select yet.","Android Launcher") | Out-Null; return $null }
    $form = New-Object Windows.Forms.Form
    $form.Text = $Title; $form.Width = 430; $form.Height = 155
    $form.TopMost = $true
    $form.StartPosition = "CenterScreen"; $form.FormBorderStyle = "FixedDialog"
    $label = New-Object Windows.Forms.Label
    $label.Text = "Choose an item:"; $label.Left = 12; $label.Top = 12; $label.Width = 390
    $combo = New-Object Windows.Forms.ComboBox
    $combo.Left = 12; $combo.Top = 38; $combo.Width = 390
    $combo.DropDownStyle = "DropDownList"
    [void]$combo.Items.AddRange([object[]]$Items)
    $combo.SelectedIndex = 0
    $ok = New-Object Windows.Forms.Button
    $ok.Text = "OK"; $ok.Left = 236; $ok.Top = 76; $ok.Width = 78; $ok.DialogResult = "OK"
    $cancel = New-Object Windows.Forms.Button
    $cancel.Text = "Cancel"; $cancel.Left = 324; $cancel.Top = 76; $cancel.Width = 78; $cancel.DialogResult = "Cancel"
    $form.Controls.AddRange(@($label,$combo,$ok,$cancel))
    $form.AcceptButton = $ok; $form.CancelButton = $cancel
    $result = $form.ShowDialog()
    $value = if ($result -eq "OK") { [string]$combo.SelectedItem } else { $null }
    $form.Dispose()
    return $value
}

function Show-FolderManager([ref]$Data) {
    Write-MonitorMetrics

    $script:isDarkMode = $true
    if ($Data.Value.PSObject.Properties['darkMode'] -and $null -ne $Data.Value.darkMode) {
        $script:isDarkMode = [bool]$Data.Value.darkMode
    }
    $script:activePage = "Folders" # "Folders" or "Appearance"
    $script:selectedFolderId = $null
    $script:suppressListEvent = $false
    $script:dragHoverFolderIdx = -1

    # --- FONTS (Disposed cleanly on exit) ---
    $fontBase      = New-Object Drawing.Font("Segoe UI", 9.5)
    $fontTitle     = New-Object Drawing.Font("Segoe UI Semibold", 13.5)
    $fontBrand     = New-Object Drawing.Font("Segoe UI Semibold", 11.5)
    $fontSection   = New-Object Drawing.Font("Segoe UI Semibold", 10)
    $fontCaption   = New-Object Drawing.Font("Segoe UI", 8.5)
    $fontSmallBold = New-Object Drawing.Font("Segoe UI", 8, [Drawing.FontStyle]::Bold)
    $fontNav       = New-Object Drawing.Font("Segoe UI Semibold", 9.5)
    $fontBtn       = New-Object Drawing.Font("Segoe UI Semibold", 9)
    $fontPlus      = New-Object Drawing.Font("Segoe UI", 12, [Drawing.FontStyle]::Bold)
    $fontList      = New-Object Drawing.Font("Segoe UI", 9.5)
    $fontListBold  = New-Object Drawing.Font("Segoe UI Semibold", 9.5)
    $fontBadge     = New-Object Drawing.Font("Segoe UI", 8)

    # --- THEME PALETTE HELPER ---
    function script:Get-Theme([bool]$Dark) {
        if ($Dark) {
            return @{
                Canvas         = [Drawing.Color]::FromArgb(15, 18, 25)
                Sidebar        = [Drawing.Color]::FromArgb(21, 25, 35)
                Card           = [Drawing.Color]::FromArgb(26, 31, 44)
                Border         = [Drawing.Color]::FromArgb(41, 49, 69)
                Divider        = [Drawing.Color]::FromArgb(38, 46, 65)
                InputBg        = [Drawing.Color]::FromArgb(17, 21, 31)
                InputBorder    = [Drawing.Color]::FromArgb(52, 62, 86)
                BtnFill        = [Drawing.Color]::FromArgb(35, 42, 59)
                BtnHover       = [Drawing.Color]::FromArgb(46, 55, 76)
                BtnPress       = [Drawing.Color]::FromArgb(29, 35, 49)
                BtnBorder      = [Drawing.Color]::FromArgb(54, 64, 88)
                BtnDisFill     = [Drawing.Color]::FromArgb(22, 26, 37)
                BtnDisText     = [Drawing.Color]::FromArgb(86, 97, 118)
                Accent         = [Drawing.Color]::FromArgb(59, 130, 246)
                AccentHover    = [Drawing.Color]::FromArgb(37, 99, 235)
                AccentPress    = [Drawing.Color]::FromArgb(29, 78, 216)
                AccentSoft     = [Drawing.Color]::FromArgb(30, 46, 78)
                AccentSoftText = [Drawing.Color]::FromArgb(147, 197, 253)
                DangerFill     = [Drawing.Color]::FromArgb(44, 24, 32)
                DangerHover    = [Drawing.Color]::FromArgb(62, 30, 40)
                DangerPress    = [Drawing.Color]::FromArgb(36, 19, 26)
                DangerBorder   = [Drawing.Color]::FromArgb(98, 42, 56)
                DangerText     = [Drawing.Color]::FromArgb(248, 113, 113)
                TextPrimary    = [Drawing.Color]::FromArgb(241, 245, 249)
                TextMuted      = [Drawing.Color]::FromArgb(148, 163, 184)
                BadgeBg        = [Drawing.Color]::FromArgb(36, 44, 62)
                DragHoverBg    = [Drawing.Color]::FromArgb(34, 58, 102)
                DragHoverText  = [Drawing.Color]::FromArgb(191, 219, 254)
                SliderTrack    = [Drawing.Color]::FromArgb(48, 57, 78)
                SliderThumb    = [Drawing.Color]::FromArgb(248, 250, 252)
                SwatchRing     = [Drawing.Color]::FromArgb(241, 245, 249)
            }
        } else {
            return @{
                Canvas         = [Drawing.Color]::FromArgb(244, 246, 250)
                Sidebar        = [Drawing.Color]::FromArgb(236, 240, 247)
                Card           = [Drawing.Color]::FromArgb(255, 255, 255)
                Border         = [Drawing.Color]::FromArgb(218, 225, 236)
                Divider        = [Drawing.Color]::FromArgb(214, 221, 233)
                InputBg        = [Drawing.Color]::FromArgb(248, 250, 252)
                InputBorder    = [Drawing.Color]::FromArgb(198, 208, 223)
                BtnFill        = [Drawing.Color]::FromArgb(241, 245, 249)
                BtnHover       = [Drawing.Color]::FromArgb(226, 232, 240)
                BtnPress       = [Drawing.Color]::FromArgb(203, 213, 225)
                BtnBorder      = [Drawing.Color]::FromArgb(203, 213, 225)
                BtnDisFill     = [Drawing.Color]::FromArgb(246, 248, 251)
                BtnDisText     = [Drawing.Color]::FromArgb(156, 166, 182)
                Accent         = [Drawing.Color]::FromArgb(37, 99, 235)
                AccentHover    = [Drawing.Color]::FromArgb(29, 78, 216)
                AccentPress    = [Drawing.Color]::FromArgb(30, 64, 175)
                AccentSoft     = [Drawing.Color]::FromArgb(219, 234, 254)
                AccentSoftText = [Drawing.Color]::FromArgb(29, 78, 216)
                DangerFill     = [Drawing.Color]::FromArgb(254, 242, 242)
                DangerHover    = [Drawing.Color]::FromArgb(254, 226, 226)
                DangerPress    = [Drawing.Color]::FromArgb(252, 202, 202)
                DangerBorder   = [Drawing.Color]::FromArgb(252, 165, 165)
                DangerText     = [Drawing.Color]::FromArgb(220, 38, 38)
                TextPrimary    = [Drawing.Color]::FromArgb(15, 23, 42)
                TextMuted      = [Drawing.Color]::FromArgb(100, 116, 139)
                BadgeBg        = [Drawing.Color]::FromArgb(226, 232, 240)
                DragHoverBg    = [Drawing.Color]::FromArgb(219, 234, 254)
                DragHoverText  = [Drawing.Color]::FromArgb(30, 64, 175)
                SliderTrack    = [Drawing.Color]::FromArgb(214, 221, 233)
                SliderThumb    = [Drawing.Color]::FromArgb(255, 255, 255)
                SwatchRing     = [Drawing.Color]::FromArgb(30, 41, 59)
            }
        }
    }

    function script:Style-Btn($Btn, $Theme, [string]$Variant = "Secondary", $OuterColor = $null) {
        $outer = if ($null -ne $OuterColor) { $OuterColor } else { $Theme.Card }
        $Btn.OuterBackColor = $outer
        $Btn.DisabledFillColor = $Theme.BtnDisFill
        $Btn.DisabledTextColor = $Theme.BtnDisText
        $Btn.SubtitleColor = $Theme.TextMuted
        $Btn.ActiveBarColor = $Theme.Accent

        if ($Variant -eq "Primary") {
            $Btn.FillColor = $Theme.Accent
            $Btn.HoverColor = $Theme.AccentHover
            $Btn.PressColor = $Theme.AccentPress
            $Btn.BorderColor = $Theme.Accent
            $Btn.ForeColor = [Drawing.Color]::White
            $Btn.ActiveFillColor = $Theme.Accent
            $Btn.ActiveBorderColor = $Theme.Accent
            $Btn.ActiveTextColor = [Drawing.Color]::White
        } elseif ($Variant -eq "Danger") {
            $Btn.FillColor = $Theme.DangerFill
            $Btn.HoverColor = $Theme.DangerHover
            $Btn.PressColor = $Theme.DangerPress
            $Btn.BorderColor = $Theme.DangerBorder
            $Btn.ForeColor = $Theme.DangerText
            $Btn.ActiveFillColor = $Theme.DangerHover
            $Btn.ActiveBorderColor = $Theme.DangerBorder
            $Btn.ActiveTextColor = $Theme.DangerText
        } elseif ($Variant -eq "Nav") {
            $Btn.FillColor = $Theme.Sidebar
            $Btn.HoverColor = $Theme.BtnHover
            $Btn.PressColor = $Theme.BtnPress
            $Btn.BorderColor = [Drawing.Color]::Transparent
            $Btn.ForeColor = $Theme.TextPrimary
            $Btn.ActiveFillColor = $Theme.AccentSoft
            $Btn.ActiveBorderColor = [Drawing.Color]::Transparent
            $Btn.ActiveTextColor = $Theme.AccentSoftText
        } elseif ($Variant -eq "Segment") {
            $Btn.FillColor = $Theme.BtnFill
            $Btn.HoverColor = $Theme.BtnHover
            $Btn.PressColor = $Theme.BtnPress
            $Btn.BorderColor = $Theme.BtnBorder
            $Btn.ForeColor = $Theme.TextPrimary
            $Btn.ActiveFillColor = $Theme.AccentSoft
            $Btn.ActiveBorderColor = $Theme.Accent
            $Btn.ActiveTextColor = $Theme.AccentSoftText
        } else {
            $Btn.FillColor = $Theme.BtnFill
            $Btn.HoverColor = $Theme.BtnHover
            $Btn.PressColor = $Theme.BtnPress
            $Btn.BorderColor = $Theme.BtnBorder
            $Btn.ForeColor = $Theme.TextPrimary
            $Btn.ActiveFillColor = $Theme.AccentSoft
            $Btn.ActiveBorderColor = $Theme.Accent
            $Btn.ActiveTextColor = $Theme.AccentSoftText
        }
        $Btn.Invalidate()
    }

    function script:New-InputWrap([int]$X, [int]$Y, [int]$W, [int]$H) {
        $wrap = New-Object ModernCard
        $wrap.Location = New-Object Drawing.Point($X, $Y)
        $wrap.Size = New-Object Drawing.Size($W, $H)
        $wrap.CornerRadius = 6
        $wrap.Padding = New-Object Windows.Forms.Padding(8, 6, 8, 4)
        $wrap.Cursor = [Windows.Forms.Cursors]::IBeam

        $tb = New-Object Windows.Forms.TextBox
        $tb.BorderStyle = "None"
        $tb.Dock = "Top"
        $tb.Font = $fontBase
        $wrap.Tag = $tb
        $wrap.Add_Click({ param($s, $e) if ($null -ne $s.Tag -and $s.Tag.Enabled) { $s.Tag.Focus() } })
        $wrap.Controls.Add($tb)
        return @{ Wrap = $wrap; Box = $tb }
    }

    # --- MAIN FORM ---
    $form = New-Object Windows.Forms.Form
    $form.Size = New-Object Drawing.Size(1020, 680)
    $form.MinimumSize = New-Object Drawing.Size(900, 600)
    $form.Text = "AndroidIconGroups - Settings"
    $form.AutoScaleMode = "Dpi"
    $form.StartPosition = "CenterScreen"
    $form.TopMost = $false
    $form.Font = $fontBase

    $uiToolTip = New-Object Windows.Forms.ToolTip

    # =========================================================================
    # LEFT SIDEBAR
    # =========================================================================
    $sidebar = New-Object ModernCard
    $sidebar.Dock = "Left"
    $sidebar.Width = 248
    $sidebar.Padding = New-Object Windows.Forms.Padding(16, 16, 17, 14)
    $sidebar.DrawRightDivider = $true

    $sidebarTop = New-Object Windows.Forms.Panel
    $sidebarTop.Dock = "Top"
    $sidebarTop.Height = 202

    $brandLabel = New-Object Windows.Forms.Label
    $brandLabel.Text = "Icon Folders"
    $brandLabel.Location = New-Object Drawing.Point(2, 2)
    $brandLabel.Size = New-Object Drawing.Size(142, 26)
    $brandLabel.Font = $fontBrand

    $themeToggleBtn = New-Object ModernButton
    $themeToggleBtn.Text = "Light"
    $themeToggleBtn.Location = New-Object Drawing.Point(150, 2)
    $themeToggleBtn.Size = New-Object Drawing.Size(64, 26)
    $themeToggleBtn.CornerRadius = 13
    $themeToggleBtn.Font = $fontCaption
    $uiToolTip.SetToolTip($themeToggleBtn, "Switch between Dark and Light mode")

    $navOverviewBtn = New-Object ModernButton
    $navOverviewBtn.Text = "All Folders"
    $navOverviewBtn.Location = New-Object Drawing.Point(0, 40)
    $navOverviewBtn.Size = New-Object Drawing.Size(214, 34)
    $navOverviewBtn.CornerRadius = 7
    $navOverviewBtn.Font = $fontNav
    $navOverviewBtn.AlignLeft = $true
    $navOverviewBtn.ShowActiveBar = $true
    $navOverviewBtn.TextPaddingLeft = 14

    $navAppearanceBtn = New-Object ModernButton
    $navAppearanceBtn.Text = "Global Appearance"
    $navAppearanceBtn.Location = New-Object Drawing.Point(0, 78)
    $navAppearanceBtn.Size = New-Object Drawing.Size(214, 34)
    $navAppearanceBtn.CornerRadius = 7
    $navAppearanceBtn.Font = $fontNav
    $navAppearanceBtn.AlignLeft = $true
    $navAppearanceBtn.ShowActiveBar = $true
    $navAppearanceBtn.TextPaddingLeft = 14

    $sideDivider = New-Object Windows.Forms.Panel
    $sideDivider.Location = New-Object Drawing.Point(2, 124)
    $sideDivider.Size = New-Object Drawing.Size(210, 1)

    $sidebarTitle = New-Object Windows.Forms.Label
    $sidebarTitle.Text = "FOLDERS"
    $sidebarTitle.Location = New-Object Drawing.Point(4, 134)
    $sidebarTitle.Size = New-Object Drawing.Size(130, 16)
    $sidebarTitle.Font = $fontSmallBold

    $folderCountLabel = New-Object Windows.Forms.Label
    $folderCountLabel.Text = "0"
    $folderCountLabel.Location = New-Object Drawing.Point(150, 134)
    $folderCountLabel.Size = New-Object Drawing.Size(60, 16)
    $folderCountLabel.Font = $fontSmallBold
    $folderCountLabel.TextAlign = "MiddleRight"

    $newFolderInput = New-InputWrap 0 158 172 30
    $newFolderWrap = $newFolderInput.Wrap
    $newFolderName = $newFolderInput.Box

    $newFolderButton = New-Object ModernButton
    $newFolderButton.Text = "+"
    $newFolderButton.Location = New-Object Drawing.Point(178, 158)
    $newFolderButton.Size = New-Object Drawing.Size(36, 30)
    $newFolderButton.CornerRadius = 6
    $newFolderButton.Font = $fontPlus
    $uiToolTip.SetToolTip($newFolderButton, "Create new folder")

    $sidebarTop.Controls.AddRange(@(
        $brandLabel, $themeToggleBtn,
        $navOverviewBtn, $navAppearanceBtn,
        $sideDivider, $sidebarTitle, $folderCountLabel,
        $newFolderWrap, $newFolderButton
    ))

    $sidebarBottom = New-Object Windows.Forms.Label
    $sidebarBottom.Dock = "Bottom"
    $sidebarBottom.Height = 22
    $sidebarBottom.Font = $fontCaption
    $sidebarBottom.TextAlign = "BottomLeft"
    $sidebarBottom.Text = "Drag shortcuts onto folders to move"

    $folderList = New-Object Windows.Forms.ListBox
    $folderList.Dock = "Fill"
    $folderList.IntegralHeight = $false
    $folderList.BorderStyle = "None"
    $folderList.Font = $fontList
    $folderList.Cursor = [Windows.Forms.Cursors]::Hand
    $folderList.DrawMode = [Windows.Forms.DrawMode]::OwnerDrawFixed
    $folderList.ItemHeight = [Math]::Max(34, [Windows.Forms.TextRenderer]::MeasureText("Ag", $fontList).Height + 14)

    $folderTextFlags = [Windows.Forms.TextFormatFlags]::Left -bor [Windows.Forms.TextFormatFlags]::VerticalCenter -bor [Windows.Forms.TextFormatFlags]::EndEllipsis -bor [Windows.Forms.TextFormatFlags]::NoPrefix
    $folderBadgeFlags = [Windows.Forms.TextFormatFlags]::HorizontalCenter -bor [Windows.Forms.TextFormatFlags]::VerticalCenter -bor [Windows.Forms.TextFormatFlags]::NoPrefix

    $folderList.Add_DrawItem({
        param($sender, $e)
        if ($e.Index -lt 0 -or $e.Index -ge $folderList.Items.Count) { return }
        $t = $script:currentTheme
        $g = $e.Graphics
        $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias

        $isDragTarget = ($e.Index -eq $script:dragHoverFolderIdx)
        $isSelected = (($script:activePage -eq "Folders") -and (($e.State -band [Windows.Forms.DrawItemState]::Selected) -ne 0))

        $bgBrush = New-Object Drawing.SolidBrush($t.Sidebar)
        try { $g.FillRectangle($bgBrush, $e.Bounds) } finally { $bgBrush.Dispose() }

        $pillRect = New-Object Drawing.RectangleF(($e.Bounds.X + 1), ($e.Bounds.Y + 2), [Math]::Max(4, $e.Bounds.Width - 3), [Math]::Max(4, $e.Bounds.Height - 4))
        $fg = $t.TextPrimary
        $rowFont = $fontList

        if ($isDragTarget) {
            $path = [ModernWin32]::CreateRoundRect($pillRect, 7)
            $hb = New-Object Drawing.SolidBrush($t.DragHoverBg)
            $hp = New-Object Drawing.Pen($t.Accent, 1.4)
            try {
                $g.FillPath($hb, $path)
                $g.DrawPath($hp, $path)
            } finally { $hb.Dispose(); $hp.Dispose(); $path.Dispose() }
            $fg = $t.DragHoverText
            $rowFont = $fontListBold
        } elseif ($isSelected) {
            $path = [ModernWin32]::CreateRoundRect($pillRect, 7)
            $sb = New-Object Drawing.SolidBrush($t.AccentSoft)
            $barRect = New-Object Drawing.RectangleF(($e.Bounds.X + 3), ($e.Bounds.Y + 8), 3.5, [Math]::Max(6, $e.Bounds.Height - 16))
            $barPath = [ModernWin32]::CreateRoundRect($barRect, 2)
            $barB = New-Object Drawing.SolidBrush($t.Accent)
            try {
                $g.FillPath($sb, $path)
                $g.FillPath($barB, $barPath)
            } finally { $sb.Dispose(); $path.Dispose(); $barB.Dispose(); $barPath.Dispose() }
            $fg = $t.AccentSoftText
            $rowFont = $fontListBold
        }

        $foldersArr = @($Data.Value.folders)
        $hex = ""
        $itemCount = 0
        if ($e.Index -lt $foldersArr.Count) {
            $fItem = $foldersArr[$e.Index]
            if ($fItem) {
                if ($fItem.PSObject.Properties['accentColor']) { $hex = Normalize-HexColor ([string]$fItem.accentColor) }
                $itemCount = @($fItem.shortcuts).Count
            }
        }

        $dotColor = if (![string]::IsNullOrEmpty($hex)) {
            try { [Drawing.ColorTranslator]::FromHtml($hex) } catch { $t.TextMuted }
        } else {
            [Drawing.Color]::FromArgb(130, 145, 168)
        }
        $dotY = $e.Bounds.Y + [Math]::Floor(($e.Bounds.Height - 10) / 2)
        $db = New-Object Drawing.SolidBrush($dotColor)
        $dp = New-Object Drawing.Pen([Drawing.Color]::FromArgb(90, 0, 0, 0), 1)
        try {
            $g.FillEllipse($db, ($e.Bounds.X + 13), $dotY, 10, 10)
            $g.DrawEllipse($dp, ($e.Bounds.X + 13), $dotY, 10, 10)
        } finally { $db.Dispose(); $dp.Dispose() }

        $badgeW = 26
        $badgeH = 18
        $badgeX = $e.Bounds.Right - $badgeW - 8
        $badgeY = $e.Bounds.Y + [Math]::Floor(($e.Bounds.Height - $badgeH) / 2)
        $badgeRectF = New-Object Drawing.RectangleF($badgeX, $badgeY, $badgeW, $badgeH)
        $badgeRect = New-Object Drawing.Rectangle($badgeX, $badgeY, $badgeW, $badgeH)
        $bp = [ModernWin32]::CreateRoundRect($badgeRectF, 9)
        $bb = New-Object Drawing.SolidBrush($t.BadgeBg)
        try {
            $g.FillPath($bb, $bp)
        } finally { $bb.Dispose(); $bp.Dispose() }
        [Windows.Forms.TextRenderer]::DrawText($g, [string]$itemCount, $fontBadge, $badgeRect, $t.TextMuted, $folderBadgeFlags)

        $textRect = New-Object Drawing.Rectangle(($e.Bounds.X + 30), $e.Bounds.Y, [Math]::Max(1, $badgeX - ($e.Bounds.X + 34)), $e.Bounds.Height)
        [Windows.Forms.TextRenderer]::DrawText($g, [string]$folderList.Items[$e.Index], $rowFont, $textRect, $fg, $folderTextFlags)
    })

    $sidebar.Controls.Add($folderList)
    $sidebar.Controls.Add($sidebarBottom)
    $sidebar.Controls.Add($sidebarTop)

    # =========================================================================
    # RIGHT MAIN HOST
    # =========================================================================
    $mainHost = New-Object Windows.Forms.Panel
    $mainHost.Dock = "Fill"
    $mainHost.Padding = New-Object Windows.Forms.Padding(24, 18, 24, 12)

    $statusBar = New-Object Windows.Forms.Panel
    $statusBar.Dock = "Bottom"
    $statusBar.Height = 26

    $statusLabel = New-Object Windows.Forms.Label
    $statusLabel.Dock = "Fill"
    $statusLabel.Font = $fontCaption
    $statusLabel.TextAlign = "BottomLeft"
    $statusLabel.Text = "Ready. Select a folder on the left or open Global Appearance."
    $statusBar.Controls.Add($statusLabel)

    $contentHost = New-Object Windows.Forms.Panel
    $contentHost.Dock = "Fill"

    # =========================================================================
    # VIEW 1: FOLDERS & SHORTCUTS WORKSPACE
    # =========================================================================
    $foldersView = New-Object Windows.Forms.Panel
    $foldersView.Dock = "Fill"

    $folderHeader = New-Object Windows.Forms.Panel
    $folderHeader.Dock = "Top"
    $folderHeader.Height = 46

    $backButton = New-Object ModernButton
    $backButton.Text = "< Back"
    $backButton.Location = New-Object Drawing.Point(0, 6)
    $backButton.Size = New-Object Drawing.Size(70, 30)
    $backButton.CornerRadius = 7
    $backButton.Font = $fontBtn
    $backButton.Visible = $false

    $breadcrumb = New-Object Windows.Forms.Label
    $breadcrumb.Location = New-Object Drawing.Point(0, 6)
    $breadcrumb.Size = New-Object Drawing.Size(360, 30)
    $breadcrumb.Font = $fontTitle
    $breadcrumb.TextAlign = "MiddleLeft"
    $breadcrumb.Text = "All Folders"

    $addShortcutButton = New-Object ModernButton
    $addShortcutButton.Text = "+ Add Shortcuts"
    $addShortcutButton.Size = New-Object Drawing.Size(130, 32)
    $addShortcutButton.CornerRadius = 7
    $addShortcutButton.Font = $fontBtn
    $addShortcutButton.Visible = $false

    $deleteFolderButton = New-Object ModernButton
    $deleteFolderButton.Text = "Delete Folder"
    $deleteFolderButton.Size = New-Object Drawing.Size(106, 32)
    $deleteFolderButton.CornerRadius = 7
    $deleteFolderButton.Font = $fontBtn
    $deleteFolderButton.Enabled = $false

    $folderHeader.Controls.AddRange(@($backButton, $breadcrumb, $addShortcutButton, $deleteFolderButton))

    function script:Layout-FolderHeader {
        $w = $folderHeader.ClientSize.Width
        $rightX = $w
        if ($deleteFolderButton.Visible) {
            $rightX -= $deleteFolderButton.Width
            $deleteFolderButton.Location = New-Object Drawing.Point($rightX, 5)
            $rightX -= 8
        }
        if ($addShortcutButton.Visible) {
            $rightX -= $addShortcutButton.Width
            $addShortcutButton.Location = New-Object Drawing.Point($rightX, 5)
            $rightX -= 10
        }
        $leftX = if ($backButton.Visible) { 80 } else { 0 }
        $breadcrumb.Location = New-Object Drawing.Point($leftX, 5)
        $breadcrumb.Size = New-Object Drawing.Size([Math]::Max(120, $rightX - $leftX), 32)
    }
    $folderHeader.Add_Resize({ Layout-FolderHeader })

    # --- Per-Folder Settings Card (Always visible to prevent layout shift; disabled until a folder is selected) ---
    $folderCard = New-Object ModernCard
    $folderCard.Dock = "Top"
    $folderCard.Height = 96
    $folderCard.CornerRadius = 10

    $renameLabel = New-Object Windows.Forms.Label
    $renameLabel.Text = "Folder"
    $renameLabel.Location = New-Object Drawing.Point(14, 17)
    $renameLabel.Size = New-Object Drawing.Size(54, 20)
    $renameLabel.Font = $fontCaption

    $renameInput = New-InputWrap 72 12 206 30
    $renameWrap = $renameInput.Wrap
    $renameBox = $renameInput.Box

    $renameButton = New-Object ModernButton
    $renameButton.Text = "Save"
    $renameButton.Location = New-Object Drawing.Point(284, 12)
    $renameButton.Size = New-Object Drawing.Size(60, 30)
    $renameButton.CornerRadius = 6
    $renameButton.Font = $fontBtn

    $folderCardDiv = New-Object Windows.Forms.Panel
    $folderCardDiv.Location = New-Object Drawing.Point(356, 15)
    $folderCardDiv.Size = New-Object Drawing.Size(1, 24)

    $customFolderIconBtn = New-Object ModernButton
    $customFolderIconBtn.Text = "Folder Icon..."
    $customFolderIconBtn.Location = New-Object Drawing.Point(369, 12)
    $customFolderIconBtn.Size = New-Object Drawing.Size(104, 30)
    $customFolderIconBtn.CornerRadius = 6
    $customFolderIconBtn.Font = $fontBtn

    $restoreFolderIconBtn = New-Object ModernButton
    $restoreFolderIconBtn.Text = "Reset Icon"
    $restoreFolderIconBtn.Location = New-Object Drawing.Point(479, 12)
    $restoreFolderIconBtn.Size = New-Object Drawing.Size(86, 30)
    $restoreFolderIconBtn.CornerRadius = 6
    $restoreFolderIconBtn.Font = $fontBtn

    $tintLabel = New-Object Windows.Forms.Label
    $tintLabel.Text = "Glass Tint"
    $tintLabel.Location = New-Object Drawing.Point(14, 58)
    $tintLabel.Size = New-Object Drawing.Size(62, 20)
    $tintLabel.Font = $fontCaption

    $tintPresets = @(
        @{ Name = "Default Neutral Glass"; Hex = "";        Rgb = @(52, 60, 78);   Neutral = $true },
        @{ Name = "Crimson Glass";         Hex = "#E11D48"; Rgb = @(225, 29, 72);  Neutral = $false },
        @{ Name = "Amber Glass";           Hex = "#D97706"; Rgb = @(217, 119, 6);  Neutral = $false },
        @{ Name = "Emerald Glass";         Hex = "#10B981"; Rgb = @(16, 185, 129); Neutral = $false },
        @{ Name = "Cyan Glass";            Hex = "#06B6D4"; Rgb = @(6, 182, 212);  Neutral = $false },
        @{ Name = "Sapphire Glass";        Hex = "#3B82F6"; Rgb = @(59, 130, 246); Neutral = $false },
        @{ Name = "Violet Glass";          Hex = "#8B5CF6"; Rgb = @(139, 92, 246); Neutral = $false },
        @{ Name = "Rose Glass";            Hex = "#EC4899"; Rgb = @(236, 72, 153); Neutral = $false }
    )
    $tintPresetButtons = New-Object System.Collections.Generic.List[ModernSwatch]
    $swatchX = 80
    foreach ($preset in $tintPresets) {
        $sw = New-Object ModernSwatch
        $sw.Location = New-Object Drawing.Point($swatchX, 55)
        $sw.Size = New-Object Drawing.Size(24, 24)
        $sw.SwatchColor = [Drawing.Color]::FromArgb($preset.Rgb[0], $preset.Rgb[1], $preset.Rgb[2])
        $sw.IsNeutralDefault = [bool]$preset.Neutral
        $sw.Tag = [string]$preset.Hex
        $uiToolTip.SetToolTip($sw, $preset.Name)
        [void]$tintPresetButtons.Add($sw)
        $swatchX += 28
    }

    $customTintBtn = New-Object ModernButton
    $customTintBtn.Text = "Custom..."
    $customTintBtn.Location = New-Object Drawing.Point(($swatchX + 8), 53)
    $customTintBtn.Size = New-Object Drawing.Size(80, 28)
    $customTintBtn.CornerRadius = 6
    $customTintBtn.Font = $fontBtn

    $clearTintBtn = New-Object ModernButton
    $clearTintBtn.Text = "Reset"
    $clearTintBtn.Location = New-Object Drawing.Point(($swatchX + 94), 53)
    $clearTintBtn.Size = New-Object Drawing.Size(60, 28)
    $clearTintBtn.CornerRadius = 6
    $clearTintBtn.Font = $fontBtn

    $tintHexLabel = New-Object Windows.Forms.Label
    $tintHexLabel.Text = "Neutral"
    $tintHexLabel.Location = New-Object Drawing.Point(($swatchX + 162), 58)
    $tintHexLabel.Size = New-Object Drawing.Size(88, 20)
    $tintHexLabel.Font = $fontCaption

    $folderCard.Controls.AddRange(@(
        $renameLabel, $renameWrap, $renameButton, $folderCardDiv,
        $customFolderIconBtn, $restoreFolderIconBtn,
        $tintLabel, $customTintBtn, $clearTintBtn, $tintHexLabel
    ))
    foreach ($sw in $tintPresetButtons) { $folderCard.Controls.Add($sw) }

    $folderCardSpacer = New-Object Windows.Forms.Panel
    $folderCardSpacer.Dock = "Top"
    $folderCardSpacer.Height = 12

    # --- Shortcuts / Overview Grid Card ---
    $gridCard = New-Object ModernCard
    $gridCard.Dock = "Fill"
    $gridCard.CornerRadius = 10
    $gridCard.Padding = New-Object Windows.Forms.Padding(12, 10, 12, 12)

    $shortcutBar = New-Object Windows.Forms.Panel
    $shortcutBar.Dock = "Top"
    $shortcutBar.Height = 36

    $gridHintLabel = New-Object Windows.Forms.Label
    $gridHintLabel.Dock = "Fill"
    $gridHintLabel.Font = $fontCaption
    $gridHintLabel.TextAlign = "MiddleLeft"
    $gridHintLabel.Text = "Double-click a folder to open it, or click once to customize its tint and icon."

    $shortcutActionsPanel = New-Object Windows.Forms.Panel
    $shortcutActionsPanel.Dock = "Fill"
    $shortcutActionsPanel.Visible = $false

    $shortcutLbl = New-Object Windows.Forms.Label
    $shortcutLbl.Text = "Shortcut"
    $shortcutLbl.Location = New-Object Drawing.Point(0, 7)
    $shortcutLbl.Size = New-Object Drawing.Size(56, 20)
    $shortcutLbl.Font = $fontCaption

    $shortcutRenameInput = New-InputWrap 60 2 204 28
    $shortcutRenameWrap = $shortcutRenameInput.Wrap
    $shortcutRenameBox = $shortcutRenameInput.Box

    $shortcutRenameBtn = New-Object ModernButton
    $shortcutRenameBtn.Text = "Save"
    $shortcutRenameBtn.Location = New-Object Drawing.Point(270, 2)
    $shortcutRenameBtn.Size = New-Object Drawing.Size(58, 28)
    $shortcutRenameBtn.CornerRadius = 6
    $shortcutRenameBtn.Font = $fontBtn

    $customIconButton = New-Object ModernButton
    $customIconButton.Text = "Change Icon"
    $customIconButton.Location = New-Object Drawing.Point(336, 2)
    $customIconButton.Size = New-Object Drawing.Size(98, 28)
    $customIconButton.CornerRadius = 6
    $customIconButton.Font = $fontBtn

    $removeButton = New-Object ModernButton
    $removeButton.Text = "Remove"
    $removeButton.Location = New-Object Drawing.Point(440, 2)
    $removeButton.Size = New-Object Drawing.Size(76, 28)
    $removeButton.CornerRadius = 6
    $removeButton.Font = $fontBtn

    $shortcutActionsPanel.Controls.AddRange(@(
        $shortcutLbl, $shortcutRenameWrap, $shortcutRenameBtn, $customIconButton, $removeButton
    ))

    $shortcutBar.Controls.Add($shortcutActionsPanel)
    $shortcutBar.Controls.Add($gridHintLabel)

    $gridBarDivider = New-Object Windows.Forms.Panel
    $gridBarDivider.Dock = "Top"
    $gridBarDivider.Height = 1

    $gridPadWrap = New-Object Windows.Forms.Panel
    $gridPadWrap.Dock = "Fill"
    $gridPadWrap.Padding = New-Object Windows.Forms.Padding(0, 8, 0, 0)

    $grid = New-Object ModernListView
    $grid.Dock = "Fill"
    $grid.View = "LargeIcon"
    $grid.LargeImageList = New-Object Windows.Forms.ImageList
    $grid.LargeImageList.ImageSize = New-Object Drawing.Size(48, 48)
    $grid.LargeImageList.ColorDepth = "Depth32Bit"
    # Materialize native HIMAGELIST handle before Refresh-UI adds & disposes Bitmaps
    [void]$grid.LargeImageList.Handle
    $grid.BorderStyle = "None"
    $grid.MultiSelect = $false
    $grid.AllowDrop = $true
    $grid.Font = $fontBase
    $gridPadWrap.Controls.Add($grid)

    $gridCard.Controls.Add($gridPadWrap)
    $gridCard.Controls.Add($gridBarDivider)
    $gridCard.Controls.Add($shortcutBar)

    $foldersView.Controls.Add($gridCard)
    $foldersView.Controls.Add($folderCardSpacer)
    $foldersView.Controls.Add($folderCard)
    $foldersView.Controls.Add($folderHeader)

    # =========================================================================
    # VIEW 2: GLOBAL APPEARANCE PAGE (Clean Card Layout)
    # =========================================================================
    $appearanceView = New-Object Windows.Forms.Panel
    $appearanceView.Dock = "Fill"
    $appearanceView.AutoScroll = $true
    $appearanceView.Visible = $false

    $appHeaderTitle = New-Object Windows.Forms.Label
    $appHeaderTitle.Text = "Global Appearance"
    $appHeaderTitle.Location = New-Object Drawing.Point(0, 2)
    $appHeaderTitle.Size = New-Object Drawing.Size(400, 26)
    $appHeaderTitle.Font = $fontTitle

    $appHeaderSub = New-Object Windows.Forms.Label
    $appHeaderSub.Text = "Applies across all desktop folders. Opacity and animations update live."
    $appHeaderSub.Location = New-Object Drawing.Point(1, 30)
    $appHeaderSub.Size = New-Object Drawing.Size(520, 18)
    $appHeaderSub.Font = $fontCaption

    # --- Card 1: Popup Animation ---
    $animCard = New-Object ModernCard
    $animCard.Location = New-Object Drawing.Point(0, 58)
    $animCard.Size = New-Object Drawing.Size(680, 188)
    $animCard.CornerRadius = 10

    $animCardTitle = New-Object Windows.Forms.Label
    $animCardTitle.Text = "Open & Close Animation"
    $animCardTitle.Location = New-Object Drawing.Point(16, 13)
    $animCardTitle.Size = New-Object Drawing.Size(260, 20)
    $animCardTitle.Font = $fontSection

    $animDefs = @(
        @{ Id = "ExpandCollapse"; Sub = "Smooth corner zoom" },
        @{ Id = "ElasticBounce";  Sub = "Spring overshoot" },
        @{ Id = "SubtlePop";      Sub = "Gentle center pop" },
        @{ Id = "Settle";         Sub = "Oversized land-in" },
        @{ Id = "VerticalBounce"; Sub = "Gravity drop" },
        @{ Id = "Snap";           Sub = "Fast fade + nudge" },
        @{ Id = "Slide";          Sub = "Directional glide" },
        @{ Id = "Fade";           Sub = "Pure crossfade" },
        @{ Id = "None";           Sub = "Instant open" }
    )
    $animButtons = New-Object System.Collections.Generic.List[ModernButton]
    foreach ($def in $animDefs) {
        $ab = New-Object ModernButton
        $ab.Text = $def.Id
        $ab.Subtitle = $def.Sub
        $ab.Tag = $def.Id
        $ab.CornerRadius = 7
        $ab.Font = $fontBtn
        [void]$animButtons.Add($ab)
        $animCard.Controls.Add($ab)
    }
    $animCard.Controls.Add($animCardTitle)

    # --- Card 2: Grid Layout & Density ---
    $layoutCard = New-Object ModernCard
    $layoutCard.Location = New-Object Drawing.Point(0, 258)
    $layoutCard.Size = New-Object Drawing.Size(680, 96)
    $layoutCard.CornerRadius = 10

    $layoutCardTitle = New-Object Windows.Forms.Label
    $layoutCardTitle.Text = "Popup Grid Layout"
    $layoutCardTitle.Location = New-Object Drawing.Point(16, 13)
    $layoutCardTitle.Size = New-Object Drawing.Size(260, 20)
    $layoutCardTitle.Font = $fontSection

    $colsLabel = New-Object Windows.Forms.Label
    $colsLabel.Text = "Columns"
    $colsLabel.Location = New-Object Drawing.Point(16, 48)
    $colsLabel.Size = New-Object Drawing.Size(60, 22)
    $colsLabel.Font = $fontCaption
    $colsLabel.TextAlign = "MiddleLeft"

    $colButtons = New-Object System.Collections.Generic.List[ModernButton]
    $cx = 80
    foreach ($cVal in @(3, 4, 5)) {
        $cb = New-Object ModernButton
        $cb.Text = "$cVal Cols"
        $cb.Tag = $cVal
        $cb.Location = New-Object Drawing.Point($cx, 44)
        $cb.Size = New-Object Drawing.Size(72, 32)
        $cb.CornerRadius = 7
        $cb.Font = $fontBtn
        [void]$colButtons.Add($cb)
        $layoutCard.Controls.Add($cb)
        $cx += 78
    }

    $layoutDivider = New-Object Windows.Forms.Panel
    $layoutDivider.Location = New-Object Drawing.Point(326, 46)
    $layoutDivider.Size = New-Object Drawing.Size(1, 28)

    $densityLabel = New-Object Windows.Forms.Label
    $densityLabel.Text = "Spacing"
    $densityLabel.Location = New-Object Drawing.Point(344, 48)
    $densityLabel.Size = New-Object Drawing.Size(56, 22)
    $densityLabel.Font = $fontCaption
    $densityLabel.TextAlign = "MiddleLeft"

    $densityButtons = New-Object System.Collections.Generic.List[ModernButton]
    $dx = 404
    foreach ($dVal in @("Standard", "Compact")) {
        $db = New-Object ModernButton
        $db.Text = $dVal
        $db.Tag = $dVal
        $db.Location = New-Object Drawing.Point($dx, 44)
        $db.Size = New-Object Drawing.Size(92, 32)
        $db.CornerRadius = 7
        $db.Font = $fontBtn
        [void]$densityButtons.Add($db)
        $layoutCard.Controls.Add($db)
        $dx += 98
    }

    $layoutCard.Controls.AddRange(@($layoutCardTitle, $colsLabel, $layoutDivider, $densityLabel))

    # --- Card 3: Liquid Glass Opacity ---
    $opacityCard = New-Object ModernCard
    $opacityCard.Location = New-Object Drawing.Point(0, 366)
    $opacityCard.Size = New-Object Drawing.Size(680, 178)
    $opacityCard.CornerRadius = 10

    $opacityCardTitle = New-Object Windows.Forms.Label
    $opacityCardTitle.Text = "Liquid Glass Opacity"
    $opacityCardTitle.Location = New-Object Drawing.Point(16, 14)
    $opacityCardTitle.Size = New-Object Drawing.Size(260, 20)
    $opacityCardTitle.Font = $fontSection

    $resetOpacityBtn = New-Object ModernButton
    $resetOpacityBtn.Text = "Reset Defaults"
    $resetOpacityBtn.Size = New-Object Drawing.Size(106, 26)
    $resetOpacityBtn.CornerRadius = 6
    $resetOpacityBtn.Font = $fontCaption

    $initFOp   = if ($Data.Value.PSObject.Properties['folderOpacity']  -and $null -ne $Data.Value.folderOpacity)  { [int]$Data.Value.folderOpacity }  else { 100 }
    $initPopOp = if ($Data.Value.PSObject.Properties['popupOpacity']   -and $null -ne $Data.Value.popupOpacity)   { [int]$Data.Value.popupOpacity }   else { 100 }
    $initPOp   = if ($Data.Value.PSObject.Properties['previewOpacity'] -and $null -ne $Data.Value.previewOpacity) { [int]$Data.Value.previewOpacity } else { 92 }

    $folderOpLabel = New-Object Windows.Forms.Label
    $folderOpLabel.Text = "Folder Squircle"
    $folderOpLabel.Location = New-Object Drawing.Point(16, 54)
    $folderOpLabel.Size = New-Object Drawing.Size(130, 22)
    $folderOpLabel.Font = $fontBase
    $folderOpLabel.TextAlign = "MiddleLeft"

    $folderOpSlider = New-Object ModernSlider
    $folderOpSlider.Minimum = 10; $folderOpSlider.Maximum = 100
    $folderOpSlider.Value = [Math]::Max(10, [Math]::Min(100, $initFOp))

    $folderOpVal = New-Object Windows.Forms.Label
    $folderOpVal.Text = "$($folderOpSlider.Value)%"
    $folderOpVal.Size = New-Object Drawing.Size(44, 22)
    $folderOpVal.Font = $fontBtn
    $folderOpVal.TextAlign = "MiddleRight"

    $popupOpLabel = New-Object Windows.Forms.Label
    $popupOpLabel.Text = "Expanded Popup"
    $popupOpLabel.Location = New-Object Drawing.Point(16, 94)
    $popupOpLabel.Size = New-Object Drawing.Size(130, 22)
    $popupOpLabel.Font = $fontBase
    $popupOpLabel.TextAlign = "MiddleLeft"

    $popupOpSlider = New-Object ModernSlider
    $popupOpSlider.Minimum = 10; $popupOpSlider.Maximum = 100
    $popupOpSlider.Value = [Math]::Max(10, [Math]::Min(100, $initPopOp))

    $popupOpVal = New-Object Windows.Forms.Label
    $popupOpVal.Text = "$($popupOpSlider.Value)%"
    $popupOpVal.Size = New-Object Drawing.Size(44, 22)
    $popupOpVal.Font = $fontBtn
    $popupOpVal.TextAlign = "MiddleRight"

    $prevOpLabel = New-Object Windows.Forms.Label
    $prevOpLabel.Text = "Preview Icons"
    $prevOpLabel.Location = New-Object Drawing.Point(16, 134)
    $prevOpLabel.Size = New-Object Drawing.Size(130, 22)
    $prevOpLabel.Font = $fontBase
    $prevOpLabel.TextAlign = "MiddleLeft"

    $prevOpSlider = New-Object ModernSlider
    $prevOpSlider.Minimum = 0; $prevOpSlider.Maximum = 100
    $prevOpSlider.Value = [Math]::Max(0, [Math]::Min(100, $initPOp))

    $prevOpVal = New-Object Windows.Forms.Label
    $prevOpVal.Text = "$($prevOpSlider.Value)%"
    $prevOpVal.Size = New-Object Drawing.Size(44, 22)
    $prevOpVal.Font = $fontBtn
    $prevOpVal.TextAlign = "MiddleRight"

    $opacityCard.Controls.AddRange(@(
        $opacityCardTitle, $resetOpacityBtn,
        $folderOpLabel, $folderOpSlider, $folderOpVal,
        $popupOpLabel,  $popupOpSlider,  $popupOpVal,
        $prevOpLabel,   $prevOpSlider,   $prevOpVal
    ))

    $appearanceView.Controls.AddRange(@($appHeaderTitle, $appHeaderSub, $animCard, $layoutCard, $opacityCard))

    function script:Layout-AppearanceCards {
        $availW = [Math]::Max(580, $appearanceView.ClientSize.Width - 6)
        $animCard.Width = $availW
        $layoutCard.Width = $availW
        $opacityCard.Width = $availW

        $padX = 16
        $gapX = 10
        $gapY = 8
        $tileW = [Math]::Floor(($availW - ($padX * 2) - ($gapX * 2)) / 3)
        $tileH = 42
        for ($idx = 0; $idx -lt $animButtons.Count; $idx++) {
            $c = $idx % 3
            $r = [Math]::Floor($idx / 3)
            $animButtons[$idx].Location = New-Object Drawing.Point(($padX + ($c * ($tileW + $gapX))), (42 + ($r * ($tileH + $gapY))))
            $animButtons[$idx].Size = New-Object Drawing.Size($tileW, $tileH)
        }

        $resetOpacityBtn.Location = New-Object Drawing.Point(($availW - $resetOpacityBtn.Width - 16), 11)
        $sliderX = 152
        $valX = $availW - 60
        $sliderW = [Math]::Max(180, $valX - $sliderX - 10)

        $folderOpSlider.Location = New-Object Drawing.Point($sliderX, 52)
        $folderOpSlider.Size = New-Object Drawing.Size($sliderW, 26)
        $folderOpVal.Location = New-Object Drawing.Point($valX, 54)

        $popupOpSlider.Location = New-Object Drawing.Point($sliderX, 92)
        $popupOpSlider.Size = New-Object Drawing.Size($sliderW, 26)
        $popupOpVal.Location = New-Object Drawing.Point($valX, 94)

        $prevOpSlider.Location = New-Object Drawing.Point($sliderX, 132)
        $prevOpSlider.Size = New-Object Drawing.Size($sliderW, 26)
        $prevOpVal.Location = New-Object Drawing.Point($valX, 134)
    }
    $appearanceView.Add_Resize({ Layout-AppearanceCards })

    # Assemble view hierarchy
    $contentHost.Controls.Add($foldersView)
    $contentHost.Controls.Add($appearanceView)

    $mainHost.Controls.Add($contentHost)
    $mainHost.Controls.Add($statusBar)

    $form.Controls.Add($mainHost)
    $form.Controls.Add($sidebar)

    # =========================================================================
    # THEME APPLICATION
    # =========================================================================
    function script:Apply-Theme([bool]$Dark) {
        $script:isDarkMode = $Dark
        $t = Get-Theme $Dark
        $script:currentTheme = $t

        if ($form.IsHandleCreated) {
            [ModernWin32]::SetDarkTitleBar($form.Handle, $Dark)
        }

        $form.BackColor = $t.Canvas
        $form.ForeColor = $t.TextPrimary
        $mainHost.BackColor = $t.Canvas
        $contentHost.BackColor = $t.Canvas
        $foldersView.BackColor = $t.Canvas
        $appearanceView.BackColor = $t.Canvas
        $folderHeader.BackColor = $t.Canvas
        $folderCardSpacer.BackColor = $t.Canvas
        $statusBar.BackColor = $t.Canvas

        # Sidebar
        $sidebar.CardBackColor = $t.Sidebar
        $sidebar.BorderColor = $t.Border
        $sidebar.BackColor = $t.Sidebar
        $sidebarTop.BackColor = $t.Sidebar
        $sidebarBottom.BackColor = $t.Sidebar
        $sidebarBottom.ForeColor = $t.TextMuted
        $brandLabel.BackColor = $t.Sidebar
        $brandLabel.ForeColor = $t.TextPrimary
        $sideDivider.BackColor = $t.Divider
        $sidebarTitle.BackColor = $t.Sidebar
        $sidebarTitle.ForeColor = $t.TextMuted
        $folderCountLabel.BackColor = $t.Sidebar
        $folderCountLabel.ForeColor = $t.TextMuted
        $folderList.BackColor = $t.Sidebar
        $folderList.ForeColor = $t.TextPrimary

        $themeToggleBtn.Text = if ($Dark) { "Light" } else { "Dark" }
        Style-Btn $themeToggleBtn $t "Secondary" $t.Sidebar
        Style-Btn $navOverviewBtn $t "Nav" $t.Sidebar
        Style-Btn $navAppearanceBtn $t "Nav" $t.Sidebar
        Style-Btn $newFolderButton $t "Primary" $t.Sidebar

        $newFolderWrap.OuterBackColor = $t.Sidebar
        $newFolderWrap.CardBackColor = $t.InputBg
        $newFolderWrap.BorderColor = $t.InputBorder
        $newFolderWrap.BackColor = $t.InputBg
        $newFolderName.BackColor = $t.InputBg
        $newFolderName.ForeColor = $t.TextPrimary

        # Folder Workspace
        $breadcrumb.BackColor = $t.Canvas
        $breadcrumb.ForeColor = $t.TextPrimary
        Style-Btn $backButton $t "Secondary" $t.Canvas
        Style-Btn $addShortcutButton $t "Primary" $t.Canvas
        Style-Btn $deleteFolderButton $t "Danger" $t.Canvas

        $folderCard.OuterBackColor = $t.Canvas
        $folderCard.CardBackColor = $t.Card
        $folderCard.BorderColor = $t.Border
        $folderCard.BackColor = $t.Card
        $renameLabel.BackColor = $t.Card; $renameLabel.ForeColor = $t.TextMuted
        $tintLabel.BackColor = $t.Card;   $tintLabel.ForeColor = $t.TextMuted
        $tintHexLabel.BackColor = $t.Card; $tintHexLabel.ForeColor = $t.TextMuted
        $folderCardDiv.BackColor = $t.Divider

        $renameWrap.OuterBackColor = $t.Card
        $renameWrap.CardBackColor = $t.InputBg
        $renameWrap.BorderColor = $t.InputBorder
        $renameWrap.BackColor = $t.InputBg
        $renameBox.BackColor = $t.InputBg
        $renameBox.ForeColor = $t.TextPrimary

        Style-Btn $renameButton $t "Secondary" $t.Card
        Style-Btn $customFolderIconBtn $t "Secondary" $t.Card
        Style-Btn $restoreFolderIconBtn $t "Secondary" $t.Card
        Style-Btn $customTintBtn $t "Secondary" $t.Card
        Style-Btn $clearTintBtn $t "Secondary" $t.Card

        foreach ($sw in $tintPresetButtons) {
            $sw.OuterBackColor = $t.Card
            $sw.RingColor = $t.SwatchRing
            $sw.HoverRingColor = $t.TextMuted
            $sw.Invalidate()
        }

        # Grid Card
        $gridCard.OuterBackColor = $t.Canvas
        $gridCard.CardBackColor = $t.Card
        $gridCard.BorderColor = $t.Border
        $gridCard.BackColor = $t.Card
        $shortcutBar.BackColor = $t.Card
        $shortcutActionsPanel.BackColor = $t.Card
        $gridHintLabel.BackColor = $t.Card; $gridHintLabel.ForeColor = $t.TextMuted
        $shortcutLbl.BackColor = $t.Card;   $shortcutLbl.ForeColor = $t.TextMuted
        $gridBarDivider.BackColor = $t.Divider
        $gridPadWrap.BackColor = $t.Card
        $grid.BackColor = $t.Card
        $grid.ForeColor = $t.TextPrimary

        $shortcutRenameWrap.OuterBackColor = $t.Card
        $shortcutRenameWrap.CardBackColor = $t.InputBg
        $shortcutRenameWrap.BorderColor = $t.InputBorder
        $shortcutRenameWrap.BackColor = $t.InputBg
        $shortcutRenameBox.BackColor = $t.InputBg
        $shortcutRenameBox.ForeColor = $t.TextPrimary

        Style-Btn $shortcutRenameBtn $t "Secondary" $t.Card
        Style-Btn $customIconButton $t "Secondary" $t.Card
        Style-Btn $removeButton $t "Danger" $t.Card

        # Appearance Page
        $appHeaderTitle.BackColor = $t.Canvas; $appHeaderTitle.ForeColor = $t.TextPrimary
        $appHeaderSub.BackColor = $t.Canvas;   $appHeaderSub.ForeColor = $t.TextMuted

        foreach ($card in @($animCard, $layoutCard, $opacityCard)) {
            $card.OuterBackColor = $t.Canvas
            $card.CardBackColor = $t.Card
            $card.BorderColor = $t.Border
            $card.BackColor = $t.Card
            $card.Invalidate()
        }

        $animCardTitle.BackColor = $t.Card;    $animCardTitle.ForeColor = $t.TextPrimary
        $layoutCardTitle.BackColor = $t.Card;  $layoutCardTitle.ForeColor = $t.TextPrimary
        $opacityCardTitle.BackColor = $t.Card; $opacityCardTitle.ForeColor = $t.TextPrimary
        $colsLabel.BackColor = $t.Card;        $colsLabel.ForeColor = $t.TextMuted
        $densityLabel.BackColor = $t.Card;     $densityLabel.ForeColor = $t.TextMuted
        $layoutDivider.BackColor = $t.Divider

        foreach ($ab in $animButtons) { Style-Btn $ab $t "Segment" $t.Card }
        foreach ($cb in $colButtons) { Style-Btn $cb $t "Segment" $t.Card }
        foreach ($db in $densityButtons) { Style-Btn $db $t "Segment" $t.Card }
        Style-Btn $resetOpacityBtn $t "Secondary" $t.Card

        foreach ($lbl in @($folderOpLabel, $popupOpLabel, $prevOpLabel)) {
            $lbl.BackColor = $t.Card; $lbl.ForeColor = $t.TextPrimary
        }
        foreach ($valLbl in @($folderOpVal, $popupOpVal, $prevOpVal)) {
            $valLbl.BackColor = $t.Card; $valLbl.ForeColor = $t.AccentSoftText
        }
        foreach ($sl in @($folderOpSlider, $popupOpSlider, $prevOpSlider)) {
            $sl.OuterBackColor = $t.Card
            $sl.TrackColor = $t.SliderTrack
            $sl.FillColor = $t.Accent
            $sl.ThumbColor = $t.SliderThumb
            $sl.ThumbBorderColor = $t.Accent
            $sl.Invalidate()
        }

        $statusLabel.BackColor = $t.Canvas
        $statusLabel.ForeColor = $t.TextMuted

        Update-FolderCard
        $sidebar.Invalidate()
        $folderList.Invalidate()
        $folderCard.Invalidate()
        $gridCard.Invalidate()
    }

    # =========================================================================
    # STATE & BUSINESS LOGIC HELPERS
    # =========================================================================
    function script:Commit-ManagerChanges([string]$ForceFolderId = "") {
        Save-Data $Data.Value
        $sync = Write-Launcher $Data.Value
        $targets = New-Object System.Collections.Generic.List[string]
        foreach ($name in @($sync.Changed)) {
            if (!$targets.Contains($name)) { [void]$targets.Add($name) }
        }
        if (![string]::IsNullOrEmpty($ForceFolderId)) {
            $foldersArr = @($Data.Value.folders)
            $dirNames = @(Get-FolderDirectoryNames $foldersArr)
            for ($i = 0; $i -lt $foldersArr.Count; $i++) {
                if ([string]$foldersArr[$i].id -eq $ForceFolderId) {
                    if (!$targets.Contains($dirNames[$i])) { [void]$targets.Add($dirNames[$i]) }
                    break
                }
            }
        }
        Refresh-Skin $Data.Value -TargetFolders @($targets) -RemovedFolders @($sync.Removed)
    }

    function script:Get-TargetFolder {
        $targetId = $script:selectedFolderId
        if ([string]::IsNullOrEmpty($targetId) -and $grid.SelectedItems.Count -gt 0) {
            $tag = $grid.SelectedItems[0].Tag
            if ($tag -is [string]) {
                $targetId = $tag
            } elseif ($null -ne $tag -and $tag.PSObject.Properties['id']) {
                $targetId = [string]$tag.id
            }
        }
        if ([string]::IsNullOrEmpty($targetId)) { return $null }
        return @($Data.Value.folders | Where-Object { [string]$_.id -eq $targetId })[0]
    }

    function script:Update-FolderCard {
        $target = Get-TargetFolder
        $hasTarget = ($null -ne $target)
        $isInsideFolder = ![string]::IsNullOrEmpty($script:selectedFolderId)

        $backButton.Visible = $isInsideFolder
        $addShortcutButton.Visible = $isInsideFolder
        $deleteFolderButton.Enabled = $hasTarget
        Layout-FolderHeader

        $t = $script:currentTheme
        if ($hasTarget) {
            $renameBox.Text = [string]$target.name
            $renameBox.Enabled = $true
            $renameWrap.Cursor = [Windows.Forms.Cursors]::IBeam
            if ($null -ne $t) {
                $renameWrap.CardBackColor = $t.InputBg
                $renameWrap.BorderColor = $t.InputBorder
                $renameWrap.BackColor = $t.InputBg
                $renameBox.BackColor = $t.InputBg
                $renameBox.ForeColor = $t.TextPrimary
                $renameWrap.Invalidate()
            }
            $renameButton.Enabled = $true
            $customFolderIconBtn.Enabled = $true

            $hasCustomIcon = ($target.PSObject.Properties['icon'] -and ![string]::IsNullOrWhiteSpace([string]$target.icon))
            $restoreFolderIconBtn.Enabled = $hasCustomIcon

            $activeHex = ""
            if ($target.PSObject.Properties['accentColor']) {
                $activeHex = Normalize-HexColor ([string]$target.accentColor)
            }
            $customTintBtn.Enabled = $true
            $clearTintBtn.Enabled = ![string]::IsNullOrEmpty($activeHex)
            $tintHexLabel.Text = if ([string]::IsNullOrEmpty($activeHex)) { "Neutral Glass" } else { $activeHex }

            foreach ($sw in $tintPresetButtons) {
                $sw.Enabled = $true
                $sw.IsSelected = ([string]$sw.Tag -eq $activeHex)
            }
        } else {
            $renameBox.Text = ""
            $renameBox.Enabled = $false
            $renameWrap.Cursor = [Windows.Forms.Cursors]::Default
            if ($null -ne $t) {
                $renameWrap.CardBackColor = $t.BtnDisFill
                $renameWrap.BorderColor = $t.Border
                $renameWrap.BackColor = $t.BtnDisFill
                $renameBox.BackColor = $t.BtnDisFill
                $renameBox.ForeColor = $t.BtnDisText
                $renameWrap.Invalidate()
            }
            $renameButton.Enabled = $false
            $customFolderIconBtn.Enabled = $false
            $restoreFolderIconBtn.Enabled = $false
            $customTintBtn.Enabled = $false
            $clearTintBtn.Enabled = $false
            $tintHexLabel.Text = "No selection"

            foreach ($sw in $tintPresetButtons) {
                $sw.Enabled = $false
                $sw.IsSelected = $false
            }
        }

        if ($isInsideFolder) {
            $hasAppSel = ($grid.SelectedItems.Count -gt 0)
            $shortcutActionsPanel.Visible = $hasAppSel
            $gridHintLabel.Visible = !$hasAppSel
            if ($hasAppSel) {
                $shortcutRenameBox.Text = $grid.SelectedItems[0].Text
            } else {
                $gridHintLabel.Text = "Drag shortcuts to reorder, drag to sidebar to move, or drop files from Explorer."
            }
        } else {
            $shortcutActionsPanel.Visible = $false
            $gridHintLabel.Visible = $true
            $gridHintLabel.Text = "Double-click a folder to manage its shortcuts, or click once to customize its tint and icon."
        }
    }

    function script:Sync-AppearanceSelections {
        $curAnim = if ($Data.Value.animation) { [string]$Data.Value.animation } else { "ExpandCollapse" }
        foreach ($ab in $animButtons) {
            $ab.IsActive = ([string]$ab.Tag -eq $curAnim)
        }

        $curCols = if ($Data.Value.PSObject.Properties['gridColumns'] -and $null -ne $Data.Value.gridColumns) { [int]$Data.Value.gridColumns } else { 4 }
        foreach ($cb in $colButtons) {
            $cb.IsActive = ([int]$cb.Tag -eq $curCols)
        }

        $curDensity = if ($Data.Value.PSObject.Properties['gridDensity'] -and $Data.Value.gridDensity) { [string]$Data.Value.gridDensity } else { "Standard" }
        foreach ($db in $densityButtons) {
            $db.IsActive = ([string]$db.Tag -eq $curDensity)
        }
    }

    function script:Switch-Page([string]$PageName) {
        $script:activePage = $PageName
        $isApp = ($PageName -eq "Appearance")
        $foldersView.Visible = !$isApp
        $appearanceView.Visible = $isApp

        $navAppearanceBtn.IsActive = $isApp
        $navOverviewBtn.IsActive = (!$isApp -and [string]::IsNullOrEmpty($script:selectedFolderId))

        if ($isApp) {
            Sync-AppearanceSelections
            Layout-AppearanceCards
        } else {
            Layout-FolderHeader
        }
        $folderList.Invalidate()
    }

    function script:Apply-FolderTint([string]$AccentHex) {
        $folder = Get-TargetFolder
        if (!$folder) { return }
        $norm = Normalize-HexColor $AccentHex

        if ($folder.PSObject.Properties['accentColor']) { $folder.accentColor = $norm }
        else { $folder | Add-Member -NotePropertyName "accentColor" -NotePropertyValue $norm -Force }

        $foldersArr = @($Data.Value.folders)
        $dirNames = @(Get-FolderDirectoryNames $foldersArr)
        $folderDirName = ""
        for ($i = 0; $i -lt $foldersArr.Count; $i++) {
            if ([string]$foldersArr[$i].id -eq [string]$folder.id) {
                $folderDirName = $dirNames[$i]
                break
            }
        }

        $iniPath = if ($folderDirName) { Join-Path $FolderRoot "$folderDirName\Folder.ini" } else { "" }
        $hasLiveTintVars = $false
        if ($iniPath -and (Test-Path $iniPath)) {
            $existingIni = [IO.File]::ReadAllText($iniPath, $Utf8NoBom)
            if ($existingIni -match '(?m)^FolderFillRGB=' -and $existingIni -match '(?m)^PopupGlowRGB=') {
                $hasLiveTintVars = $true
            }
        }

        Save-Data $Data.Value
        $sync = Write-Launcher $Data.Value

        if ($hasLiveTintVars -and $folderDirName) {
            $skinName = Split-Path -Leaf $Root
            $cfg = "$skinName\Folders\$folderDirName"
            $palette = Get-FolderTintPalette $norm
            $bangs = New-Object System.Collections.Generic.List[string]
            foreach ($key in $palette.Keys) {
                $val = [string]$palette[$key]
                $bangs.Add("[!SetVariable $key `"$val`" `"$cfg`"]")
            }
            $bangs.Add("[!UpdateMeter * `"$cfg`"][!Redraw `"$cfg`"]")
            Invoke-RainmeterBangs @($bangs)
        } else {
            Refresh-Skin $Data.Value -TargetFolders @($sync.Changed) -RemovedFolders @($sync.Removed)
        }

        $folderList.Invalidate()
        Update-FolderCard
        if ([string]::IsNullOrEmpty($norm)) {
            $statusLabel.Text = "Reset glass tint to neutral glass for '$($folder.name)'."
        } else {
            $statusLabel.Text = "Applied $norm glass tint & expanded glow to '$($folder.name)'."
        }
    }

    function script:Refresh-UI {
        $script:suppressListEvent = $true
        $foldersArr = @($Data.Value.folders)
        $folderCountLabel.Text = "$($foldersArr.Count)"

        $folderList.BeginUpdate()
        $folderList.Items.Clear()
        $selIdx = -1
        for ($i = 0; $i -lt $foldersArr.Count; $i++) {
            [void]$folderList.Items.Add([string]$foldersArr[$i].name)
            if ([string]$foldersArr[$i].id -eq $script:selectedFolderId) { $selIdx = $i }
        }
        if ($selIdx -ge 0) { $folderList.SelectedIndex = $selIdx }
        $folderList.EndUpdate()

        $grid.BeginUpdate()
        $grid.Items.Clear()
        $grid.LargeImageList.Images.Clear()
        if (!$grid.LargeImageList.HandleCreated) {
            [void]$grid.LargeImageList.Handle
        }

        $folderIconPath = Join-Path $IconDir "folder.png"
        if (!(Test-Path $folderIconPath)) { $folderIconPath = Join-Path $IconDir "app_default.png" }
        if (Test-Path $folderIconPath) {
            $fImg = Load-UnlockedImage $folderIconPath
            try {
                $grid.LargeImageList.Images.Add("folder", $fImg)
            } finally {
                $fImg.Dispose()
            }
        }

        if ([string]::IsNullOrEmpty($script:selectedFolderId)) {
            $breadcrumb.Text = "All Folders  ($($foldersArr.Count))"
            foreach ($f in $foldersArr) {
                $imgKey = "folder"
                if ($f.PSObject.Properties['icon'] -and ![string]::IsNullOrWhiteSpace([string]$f.icon)) {
                    $customFolderPath = Join-Path $IconDir ([string]$f.icon)
                    if (Test-Path $customFolderPath) {
                        $cKey = "ficon_" + [string]$f.id
                        if (!$grid.LargeImageList.Images.ContainsKey($cKey)) {
                            try {
                                $cfImg = Load-UnlockedImage $customFolderPath
                                try { $grid.LargeImageList.Images.Add($cKey, $cfImg) } finally { $cfImg.Dispose() }
                            } catch {}
                        }
                        if ($grid.LargeImageList.Images.ContainsKey($cKey)) { $imgKey = $cKey }
                    }
                }
                $item = New-Object Windows.Forms.ListViewItem([string]$f.name)
                $item.Tag = [string]$f.id
                $item.ImageKey = $imgKey
                [void]$grid.Items.Add($item)
            }
        } else {
            $folder = @($foldersArr | Where-Object { [string]$_.id -eq $script:selectedFolderId })[0]
            if ($null -eq $folder) {
                $script:selectedFolderId = $null
                $grid.EndUpdate()
                Refresh-UI
                return
            }
            $appsCount = @($folder.shortcuts).Count
            $breadcrumb.Text = [string]$folder.name + "  ($appsCount)"

            foreach ($s in @($folder.shortcuts)) {
                $iconName = [string]$s.icon
                $iconPath = Join-Path $IconDir $iconName
                if (!$iconName -or !(Test-Path $iconPath)) { $iconPath = Join-Path $IconDir "app_default.png" }
                $imgKey = "app_" + [string]$s.id
                if ((Test-Path $iconPath) -and !$grid.LargeImageList.Images.ContainsKey($imgKey)) {
                    try {
                        $sImg = Load-UnlockedImage $iconPath
                        try {
                            $grid.LargeImageList.Images.Add($imgKey, $sImg)
                        } finally {
                            $sImg.Dispose()
                        }
                    } catch {}
                }
                $item = New-Object Windows.Forms.ListViewItem([string]$s.name)
                $item.Tag = [string]$s.id
                $item.ImageKey = $imgKey
                [void]$grid.Items.Add($item)
            }
        }
        $grid.EndUpdate()

        $navOverviewBtn.IsActive = ($script:activePage -eq "Folders" -and [string]::IsNullOrEmpty($script:selectedFolderId))
        $navAppearanceBtn.IsActive = ($script:activePage -eq "Appearance")

        Sync-AppearanceSelections
        Update-FolderCard
        $grid.Invalidate()
        $folderList.Invalidate()
        $script:suppressListEvent = $false
    }

    # =========================================================================
    # NAVIGATION & THEME EVENTS
    # =========================================================================
    $themeToggleBtn.Add_Click({
        $nextDark = !$script:isDarkMode
        if ($Data.Value.PSObject.Properties['darkMode']) { $Data.Value.darkMode = $nextDark }
        else { $Data.Value | Add-Member -NotePropertyName "darkMode" -NotePropertyValue $nextDark -Force }
        Save-Data $Data.Value
        Apply-Theme $nextDark
        $modeText = if ($nextDark) { "Dark" } else { "Light" }
        $statusLabel.Text = "Switched settings dashboard to $modeText mode."
    })

    $navOverviewBtn.Add_Click({
        $script:selectedFolderId = $null
        $folderList.ClearSelected()
        Switch-Page "Folders"
        Refresh-UI
    })

    $navAppearanceBtn.Add_Click({
        Switch-Page "Appearance"
    })

    $backButton.Add_Click({
        $script:selectedFolderId = $null
        $folderList.ClearSelected()
        Switch-Page "Folders"
        Refresh-UI
    })

    $folderList.Add_SelectedIndexChanged({
        if ($script:suppressListEvent -or $folderList.SelectedIndex -lt 0) { return }
        $foldersArr = @($Data.Value.folders)
        $script:selectedFolderId = [string]$foldersArr[$folderList.SelectedIndex].id
        Switch-Page "Folders"
        Refresh-UI
    })

    $folderList.Add_Click({
        if ($script:activePage -ne "Folders" -and $folderList.SelectedIndex -ge 0) {
            $foldersArr = @($Data.Value.folders)
            if ($folderList.SelectedIndex -lt $foldersArr.Count) {
                $script:selectedFolderId = [string]$foldersArr[$folderList.SelectedIndex].id
                Switch-Page "Folders"
                Refresh-UI
            }
        }
    })

    $grid.Add_SelectedIndexChanged({
        Update-FolderCard
    })

    $grid.Add_DoubleClick({
        if ($grid.SelectedItems.Count -eq 0) { return }
        if ([string]::IsNullOrEmpty($script:selectedFolderId)) {
            $script:selectedFolderId = [string]$grid.SelectedItems[0].Tag
            Switch-Page "Folders"
            Refresh-UI
        } else {
            $folder = @($Data.Value.folders | Where-Object { [string]$_.id -eq $script:selectedFolderId })[0]
            $shortcut = @($folder.shortcuts | Where-Object { [string]$_.id -eq [string]$grid.SelectedItems[0].Tag })[0]
            if ($shortcut -and (Test-Path ([string]$shortcut.path))) { Start-Process ([string]$shortcut.path) }
        }
    })

    # =========================================================================
    # FOLDER & SHORTCUT CRUD EVENTS
    # =========================================================================
    $newFolderButton.Add_Click({
        $name = $newFolderName.Text.Trim()
        if (!$name) { $statusLabel.Text = "Type a new folder name in the sidebar input first."; $newFolderName.Focus(); return }
        if (@($Data.Value.folders | Where-Object { [string]$_.name -eq $name }).Count -gt 0) {
            $statusLabel.Text = "A folder named '$name' already exists."; return
        }
        $newId = "f_" + [Guid]::NewGuid().ToString("N").Substring(0,8)
        $newObj = [pscustomobject]@{ id = $newId; name = $name; shortcuts = @(); icon = ""; accentColor = "" }
        $Data.Value.folders = @($Data.Value.folders) + @($newObj)
        $newFolderName.Text = ""
        $script:selectedFolderId = $newId
        Switch-Page "Folders"
        Commit-ManagerChanges
        Refresh-UI
        $statusLabel.Text = "Created folder '$name'."
    })

    $newFolderName.Add_KeyDown({
        if ($_.KeyCode -eq "Enter") {
            $newFolderButton.PerformClick()
            $_.SuppressKeyPress = $true
        }
    })

    $addShortcutButton.Add_Click({
        if ([string]::IsNullOrEmpty($script:selectedFolderId)) { return }
        $folder = @($Data.Value.folders | Where-Object { [string]$_.id -eq $script:selectedFolderId })[0]
        if (!$folder) { return }
        $dialog = New-Object Windows.Forms.OpenFileDialog
        try {
            $dialog.Title = "Select Application(s), Shortcut(s), or File(s)"
            $dialog.Filter = "All files (*.*)|*.*"
            $dialog.DereferenceLinks = $false
            $dialog.Multiselect = $true
            if ($dialog.ShowDialog() -ne "OK") { return }
            $added = Add-ShortcutsToFolder $folder @($dialog.FileNames)
            if ($added -gt 0) {
                Commit-ManagerChanges
                Refresh-UI
                $statusLabel.Text = "Added $added shortcut(s) to '$($folder.name)'."
            }
        } finally {
            $dialog.Dispose()
        }
    })

    $renameButton.Add_Click({
        $newName = $renameBox.Text.Trim()
        if (!$newName) { return }
        $folder = Get-TargetFolder
        if (!$folder) { return }
        if ([string]$folder.name -eq $newName) { return }
        $folder.name = $newName
        Commit-ManagerChanges
        Refresh-UI
        $statusLabel.Text = "Renamed folder to '$newName'."
    })

    $renameBox.Add_KeyDown({
        if ($_.KeyCode -eq "Enter") {
            $renameButton.PerformClick()
            $_.SuppressKeyPress = $true
        }
    })

    $shortcutRenameBtn.Add_Click({
        $newName = $shortcutRenameBox.Text.Trim()
        if (!$newName -or [string]::IsNullOrEmpty($script:selectedFolderId) -or $grid.SelectedItems.Count -eq 0) { return }
        $folder = @($Data.Value.folders | Where-Object { [string]$_.id -eq $script:selectedFolderId })[0]
        if (!$folder) { return }
        $appId = [string]$grid.SelectedItems[0].Tag
        $app = @($folder.shortcuts | Where-Object { [string]$_.id -eq $appId })[0]
        if ($app -and [string]$app.name -ne $newName) {
            $app.name = $newName
            Commit-ManagerChanges
            Refresh-UI
            $statusLabel.Text = "Renamed shortcut to '$newName'."
        }
    })

    $shortcutRenameBox.Add_KeyDown({
        if ($_.KeyCode -eq "Enter") {
            $shortcutRenameBtn.PerformClick()
            $_.SuppressKeyPress = $true
        }
    })

    $customFolderIconBtn.Add_Click({
        $folder = Get-TargetFolder
        if (!$folder) { return }
        $dlg = New-Object Windows.Forms.OpenFileDialog
        try {
            $dlg.Title = "Choose Custom Folder Icon"
            $dlg.Filter = "Images (*.png;*.ico;*.jpg;*.bmp)|*.png;*.ico;*.jpg;*.bmp"
            if ($dlg.ShowDialog() -eq "OK") {
                $customName = "folder_" + $folder.id + ".png"
                Save-IconAsPng $dlg.FileName (Join-Path $IconDir $customName)

                if ($folder.PSObject.Properties['icon']) { $folder.icon = $customName }
                else { $folder | Add-Member -NotePropertyName "icon" -NotePropertyValue $customName -Force }

                Commit-ManagerChanges -ForceFolderId ([string]$folder.id)
                Refresh-UI
                $statusLabel.Text = "Applied custom folder icon to '$($folder.name)'."
            }
        } finally {
            $dlg.Dispose()
        }
    })

    $restoreFolderIconBtn.Add_Click({
        $folder = Get-TargetFolder
        if (!$folder) { return }
        if ($folder.PSObject.Properties['icon']) { $folder.icon = "" }
        $customName = "folder_" + $folder.id + ".png"
        $filePath = Join-Path $IconDir $customName
        if (Test-Path $filePath) { Remove-Item $filePath -Force -ErrorAction SilentlyContinue }

        Commit-ManagerChanges
        Refresh-UI
        $statusLabel.Text = "Restored default 2x2 icon preview for '$($folder.name)'."
    })

    foreach ($sw in $tintPresetButtons) {
        $sw.Add_Click({
            param($sender, $e)
            Apply-FolderTint ([string]$sender.Tag)
        })
    }

    $customTintBtn.Add_Click({
        $folder = Get-TargetFolder
        if (!$folder) { return }
        $cd = New-Object Windows.Forms.ColorDialog
        try {
            $cd.FullOpen = $true
            $cd.AnyColor = $true
            $curHex = if ($folder.PSObject.Properties['accentColor']) { Normalize-HexColor ([string]$folder.accentColor) } else { "" }
            if (![string]::IsNullOrEmpty($curHex)) {
                try { $cd.Color = [Drawing.ColorTranslator]::FromHtml($curHex) } catch {}
            }
            if ($cd.ShowDialog() -eq "OK") {
                $pickedHex = "#{0:X2}{1:X2}{2:X2}" -f $cd.Color.R, $cd.Color.G, $cd.Color.B
                Apply-FolderTint $pickedHex
            }
        } finally {
            $cd.Dispose()
        }
    })

    $clearTintBtn.Add_Click({
        Apply-FolderTint ""
    })

    $customIconButton.Add_Click({
        if ([string]::IsNullOrEmpty($script:selectedFolderId) -or $grid.SelectedItems.Count -eq 0) { return }
        $appId = [string]$grid.SelectedItems[0].Tag
        $folder = @($Data.Value.folders | Where-Object { [string]$_.id -eq $script:selectedFolderId })[0]
        $app = @($folder.shortcuts | Where-Object { [string]$_.id -eq $appId })[0]
        if (!$app) { return }
        $dlg = New-Object Windows.Forms.OpenFileDialog
        try {
            $dlg.Title = "Choose Custom Icon"
            $dlg.Filter = "Images (*.png;*.ico;*.jpg;*.bmp)|*.png;*.ico;*.jpg;*.bmp"
            if ($dlg.ShowDialog() -eq "OK") {
                $customName = "custom_" + [Guid]::NewGuid().ToString("N") + ".png"
                Save-IconAsPng $dlg.FileName (Join-Path $IconDir $customName)
                $app.icon = $customName
                Commit-ManagerChanges
                Refresh-UI
                $statusLabel.Text = "Updated icon for '$($app.name)'."
            }
        } finally {
            $dlg.Dispose()
        }
    })

    $removeButton.Add_Click({
        if ([string]::IsNullOrEmpty($script:selectedFolderId) -or $grid.SelectedItems.Count -eq 0) { return }
        $appId = [string]$grid.SelectedItems[0].Tag
        $folder = @($Data.Value.folders | Where-Object { [string]$_.id -eq $script:selectedFolderId })[0]
        $folder.shortcuts = @($folder.shortcuts | Where-Object { [string]$_.id -ne $appId })
        Commit-ManagerChanges
        Refresh-UI
        $statusLabel.Text = "Removed shortcut."
    })

    $deleteFolderButton.Add_Click({
        $folder = Get-TargetFolder
        if (!$folder) { return }
        $confirm = [Windows.Forms.MessageBox]::Show(
            "Delete folder '$($folder.name)'? (Your original files and shortcuts on disk will not be deleted.)",
            "Delete Folder",
            [Windows.Forms.MessageBoxButtons]::YesNo,
            [Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($confirm -ne [Windows.Forms.DialogResult]::Yes) { return }

        $Data.Value.folders = @($Data.Value.folders | Where-Object { [string]$_.id -ne [string]$folder.id })
        if ($script:selectedFolderId -eq [string]$folder.id) {
            $script:selectedFolderId = $null
        }

        Commit-ManagerChanges
        Refresh-UI
        $statusLabel.Text = "Deleted folder '$($folder.name)'."
    })

    # =========================================================================
    # GLOBAL APPEARANCE EVENTS
    # =========================================================================
    foreach ($ab in $animButtons) {
        $ab.Add_Click({
            param($sender, $e)
            $chosenAnim = [string]$sender.Tag
            if (!$chosenAnim) { return }
            $currentAnim = if ($Data.Value.PSObject.Properties['animation']) { [string]$Data.Value.animation } else { "" }
            if ($currentAnim -eq $chosenAnim) { return }

            if ($Data.Value.PSObject.Properties['animation']) { $Data.Value.animation = $chosenAnim }
            else { $Data.Value | Add-Member -NotePropertyName "animation" -NotePropertyValue $chosenAnim -Force }

            Save-Data $Data.Value

            $skinName = Split-Path -Leaf $Root
            $folderNames = @(Get-FolderDirectoryNames $Data.Value.folders)
            $bangList = New-Object System.Collections.Generic.List[string]

            foreach ($folderName in $folderNames) {
                $iniPath = Join-Path $FolderRoot "$folderName\Folder.ini"
                if (Test-Path $iniPath) {
                    $raw = [IO.File]::ReadAllText($iniPath, $Utf8NoBom)
                    $updated = [Regex]::Replace($raw, '(?m)^AnimStyle=.*$', "AnimStyle=$chosenAnim")
                    if ($updated -ne $raw) {
                        [IO.File]::WriteAllText($iniPath, $updated, $Utf8NoBom)
                    }
                }
                $bangList.Add("[!SetVariable AnimStyle `"$chosenAnim`" `"$skinName\Folders\$folderName`"]")
            }

            Invoke-RainmeterBangs @($bangList)
            Sync-AppearanceSelections
            $statusLabel.Text = "Applied '$chosenAnim' animation to all folders."
        })
    }

    foreach ($cb in $colButtons) {
        $cb.Add_Click({
            param($sender, $e)
            $chosenCols = [int]$sender.Tag
            if ([int]$Data.Value.gridColumns -eq $chosenCols) { return }

            if ($Data.Value.PSObject.Properties['gridColumns']) { $Data.Value.gridColumns = $chosenCols }
            else { $Data.Value | Add-Member -NotePropertyName "gridColumns" -NotePropertyValue $chosenCols -Force }

            Commit-ManagerChanges
            Sync-AppearanceSelections
            $statusLabel.Text = "Updated popup grid to $chosenCols columns."
        })
    }

    foreach ($db in $densityButtons) {
        $db.Add_Click({
            param($sender, $e)
            $chosenDensity = [string]$sender.Tag
            if ([string]$Data.Value.gridDensity -eq $chosenDensity) { return }

            if ($Data.Value.PSObject.Properties['gridDensity']) { $Data.Value.gridDensity = $chosenDensity }
            else { $Data.Value | Add-Member -NotePropertyName "gridDensity" -NotePropertyValue $chosenDensity -Force }

            Commit-ManagerChanges
            Sync-AppearanceSelections
            $statusLabel.Text = "Updated icon spacing to $chosenDensity."
        })
    }

    $script:lastOpacityPush = [DateTime]::MinValue

    function script:Apply-OpacityLive([bool]$Persist) {
        $fOp = [int]$folderOpSlider.Value
        $popOp = [int]$popupOpSlider.Value
        $pOp = [int]$prevOpSlider.Value

        if (!$Persist) {
            $now = [DateTime]::UtcNow
            if (($now - $script:lastOpacityPush).TotalMilliseconds -lt 50) { return }
            $script:lastOpacityPush = $now
        }

        $folderScale = [Math]::Round($fOp / 100.0, 2).ToString([System.Globalization.CultureInfo]::InvariantCulture)
        $popupScale = [Math]::Round($popOp / 100.0, 2).ToString([System.Globalization.CultureInfo]::InvariantCulture)
        $prevAlpha = [int][Math]::Round(255 * ($pOp / 100.0))

        $skinName = Split-Path -Leaf $Root
        $folderNames = @(Get-FolderDirectoryNames $Data.Value.folders)
        $bangList = New-Object System.Collections.Generic.List[string]

        if ($Persist) {
            $Data.Value.folderOpacity = $fOp
            $Data.Value.popupOpacity = $popOp
            $Data.Value.previewOpacity = $pOp
            Save-Data $Data.Value

            foreach ($folderName in $folderNames) {
                $iniPath = Join-Path $FolderRoot "$folderName\Folder.ini"
                if (Test-Path $iniPath) {
                    $raw = [IO.File]::ReadAllText($iniPath, $Utf8NoBom)
                    $updated = [Regex]::Replace($raw, '(?m)^FolderAlphaScale=.*$', "FolderAlphaScale=$folderScale")
                    if ($updated -match '(?m)^PopupAlphaScale=') {
                        $updated = [Regex]::Replace($updated, '(?m)^PopupAlphaScale=.*$', "PopupAlphaScale=$popupScale")
                    } else {
                        $updated = [Regex]::Replace($updated, '(?m)^(FolderAlphaScale=.*)$', "`$1`r`nPopupAlphaScale=$popupScale")
                    }
                    $updated = [Regex]::Replace($updated, '(?m)^PreviewAlpha=.*$', "PreviewAlpha=$prevAlpha")
                    if ($updated -ne $raw) {
                        [IO.File]::WriteAllText($iniPath, $updated, $Utf8NoBom)
                    }
                }
            }
        }

        foreach ($folderName in $folderNames) {
            $cfg = "$skinName\Folders\$folderName"
            $bangList.Add("[!SetVariable FolderAlphaScale `"$folderScale`" `"$cfg`"]")
            $bangList.Add("[!SetVariable PopupAlphaScale `"$popupScale`" `"$cfg`"]")
            $bangList.Add("[!SetVariable PreviewAlpha `"$prevAlpha`" `"$cfg`"]")
            $bangList.Add("[!UpdateMeter * `"$cfg`"][!Redraw `"$cfg`"]")
        }

        Invoke-RainmeterBangs @($bangList)
    }

    $folderOpSlider.Add_ValueChanged({
        $folderOpVal.Text = "$($folderOpSlider.Value)%"
        Apply-OpacityLive $false
    })
    $folderOpSlider.Add_ValueCommitted({
        Apply-OpacityLive $true
        $statusLabel.Text = "Updated folder squircle opacity to $($folderOpSlider.Value)%."
    })

    $popupOpSlider.Add_ValueChanged({
        $popupOpVal.Text = "$($popupOpSlider.Value)%"
        Apply-OpacityLive $false
    })
    $popupOpSlider.Add_ValueCommitted({
        Apply-OpacityLive $true
        $statusLabel.Text = "Updated expanded popup opacity to $($popupOpSlider.Value)%."
    })

    $prevOpSlider.Add_ValueChanged({
        $prevOpVal.Text = "$($prevOpSlider.Value)%"
        Apply-OpacityLive $false
    })
    $prevOpSlider.Add_ValueCommitted({
        Apply-OpacityLive $true
        $statusLabel.Text = "Updated preview icons opacity to $($prevOpSlider.Value)%."
    })

    $resetOpacityBtn.Add_Click({
        $folderOpSlider.Value = 100
        $popupOpSlider.Value = 100
        $prevOpSlider.Value = 92
        $folderOpVal.Text = "100%"
        $popupOpVal.Text = "100%"
        $prevOpVal.Text = "92%"
        Apply-OpacityLive $true
        $statusLabel.Text = "Reset opacity to defaults (Folder 100%, Popup 100%, Preview 92%)."
    })

    # =========================================================================
    # UNIFIED DRAG & DROP (REORDER, MOVE BETWEEN FOLDERS, DROP FROM EXPLORER)
    # =========================================================================
    $form.AllowDrop = $true
    $grid.AllowDrop = $true
    $folderList.AllowDrop = $true

    function script:Move-ShortcutBetweenFolders($SourceFolder, $TargetFolder, [string]$AppId) {
        if (!$SourceFolder -or !$TargetFolder -or [string]::IsNullOrEmpty($AppId)) { return $null }
        if ([string]$SourceFolder.id -eq [string]$TargetFolder.id) { return $null }

        $srcList = New-Object System.Collections.Generic.List[object]
        $movedApp = $null
        foreach ($s in @($SourceFolder.shortcuts)) {
            if ($null -eq $movedApp -and [string]$s.id -eq $AppId) {
                $movedApp = $s
            } else {
                [void]$srcList.Add($s)
            }
        }
        if ($null -eq $movedApp) { return $null }

        $dstList = New-Object System.Collections.Generic.List[object]
        foreach ($s in @($TargetFolder.shortcuts)) {
            [void]$dstList.Add($s)
        }
        [void]$dstList.Add($movedApp)

        $SourceFolder.shortcuts = $srcList.ToArray()
        $TargetFolder.shortcuts = $dstList.ToArray()
        return $movedApp
    }

    $grid.Add_ItemDrag({
        param($sender, $e)
        if (![string]::IsNullOrEmpty($script:selectedFolderId)) {
            try {
                [void]$grid.DoDragDrop($e.Item, [Windows.Forms.DragDropEffects]::Move)
            } finally {
                if ($script:dragHoverFolderIdx -ne -1) {
                    $script:dragHoverFolderIdx = -1
                    $folderList.Invalidate()
                }
            }
        }
    })

    $gridDragEnterHandler = {
        param($sender, $e)
        if ($e.Data.GetDataPresent([Windows.Forms.ListViewItem])) {
            $e.Effect = [Windows.Forms.DragDropEffects]::Move
        } elseif ($e.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) {
            $e.Effect = [Windows.Forms.DragDropEffects]::Copy
        } else {
            $e.Effect = [Windows.Forms.DragDropEffects]::None
        }
    }

    $fileDragEnterHandler = {
        param($sender, $e)
        if ($e.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) {
            $e.Effect = [Windows.Forms.DragDropEffects]::Copy
        } else {
            $e.Effect = [Windows.Forms.DragDropEffects]::None
        }
    }

    $folderListDragOverHandler = {
        param($sender, $e)
        $pt = $folderList.PointToClient((New-Object Drawing.Point($e.X, $e.Y)))
        $index = $folderList.IndexFromPoint($pt)
        $foldersArr = @($Data.Value.folders)
        $newHoverIdx = -1

        if ($e.Data.GetDataPresent([Windows.Forms.ListViewItem])) {
            if ($index -ge 0 -and $index -lt $foldersArr.Count -and ![string]::IsNullOrEmpty($script:selectedFolderId)) {
                $targetFolder = $foldersArr[$index]
                if ($targetFolder -and [string]$targetFolder.id -ne $script:selectedFolderId) {
                    $e.Effect = [Windows.Forms.DragDropEffects]::Move
                    $newHoverIdx = $index
                } else {
                    $e.Effect = [Windows.Forms.DragDropEffects]::None
                }
            } else {
                $e.Effect = [Windows.Forms.DragDropEffects]::None
            }
        } elseif ($e.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) {
            if ($index -ge 0 -and $index -lt $foldersArr.Count) {
                $e.Effect = [Windows.Forms.DragDropEffects]::Copy
                $newHoverIdx = $index
            } else {
                $e.Effect = [Windows.Forms.DragDropEffects]::None
            }
        } else {
            $e.Effect = [Windows.Forms.DragDropEffects]::None
        }

        if ($script:dragHoverFolderIdx -ne $newHoverIdx) {
            $script:dragHoverFolderIdx = $newHoverIdx
            $folderList.Invalidate()
            if ($newHoverIdx -ge 0) {
                $hoverName = [string]$foldersArr[$newHoverIdx].name
                if ($e.Data.GetDataPresent([Windows.Forms.ListViewItem])) {
                    $statusLabel.Text = "Drop to move shortcut to '$hoverName'."
                } else {
                    $statusLabel.Text = "Drop to add file(s) to '$hoverName'."
                }
            }
        }
    }

    $folderList.Add_DragLeave({
        if ($script:dragHoverFolderIdx -ne -1) {
            $script:dragHoverFolderIdx = -1
            $folderList.Invalidate()
        }
    })

    $gridDragDropHandler = {
        param($sender, $e)
        if ([string]::IsNullOrEmpty($script:selectedFolderId)) {
            $statusLabel.Text = "Please open or select a folder on the left first."
            return
        }
        $folder = @($Data.Value.folders | Where-Object { [string]$_.id -eq $script:selectedFolderId })[0]
        if (!$folder) { return }

        # Case 1: Reordering an existing shortcut inside the grid
        if ($e.Data.GetDataPresent([Windows.Forms.ListViewItem])) {
            $pt = $grid.PointToClient((New-Object Drawing.Point($e.X, $e.Y)))
            $targetItem = $grid.GetItemAt($pt.X, $pt.Y)
            $draggedItem = $e.Data.GetData([Windows.Forms.ListViewItem])
            if ($null -eq $draggedItem) { return }

            $fromId = [string]$draggedItem.Tag
            $shortcutsArr = @($folder.shortcuts)
            $fromIdx = -1
            for ($i = 0; $i -lt $shortcutsArr.Count; $i++) {
                if ([string]$shortcutsArr[$i].id -eq $fromId) { $fromIdx = $i; break }
            }
            if ($fromIdx -lt 0) { return }

            $toIdx = $shortcutsArr.Count - 1
            if ($null -ne $targetItem) {
                $toId = [string]$targetItem.Tag
                for ($i = 0; $i -lt $shortcutsArr.Count; $i++) {
                    if ([string]$shortcutsArr[$i].id -eq $toId) { $toIdx = $i; break }
                }
            }

            if ($fromIdx -ne $toIdx -and $fromIdx -ge 0 -and $toIdx -ge 0) {
                $list = New-Object System.Collections.Generic.List[object]
                foreach ($s in $shortcutsArr) { [void]$list.Add($s) }
                $item = $list[$fromIdx]
                $list.RemoveAt($fromIdx)
                $list.Insert($toIdx, $item)
                $folder.shortcuts = @($list)

                script:Commit-ManagerChanges
                script:Refresh-UI
                $statusLabel.Text = "Rearranged shortcuts in '$($folder.name)'."
            }
            return
        }

        # Case 2: Dropping external files/shortcuts from Windows Explorer
        if ($e.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) {
            $paths = @($e.Data.GetData([Windows.Forms.DataFormats]::FileDrop))
            $added = Add-ShortcutsToFolder $folder $paths
            if ($added -gt 0) {
                script:Commit-ManagerChanges
                script:Refresh-UI
                $statusLabel.Text = "Added $added dropped shortcut(s) to '$($folder.name)'."
            }
        }
    }

    $folderListDragDropHandler = {
        param($sender, $e)
        if ($script:dragHoverFolderIdx -ne -1) {
            $script:dragHoverFolderIdx = -1
            $folderList.Invalidate()
        }

        $pt = $folderList.PointToClient((New-Object Drawing.Point($e.X, $e.Y)))
        $index = $folderList.IndexFromPoint($pt)
        $foldersArr = @($Data.Value.folders)
        if ($index -lt 0 -or $index -ge $foldersArr.Count) { return }
        $targetFolder = $foldersArr[$index]
        if (!$targetFolder) { return }

        # Case 1: Moving a shortcut dragged from the currently open folder into another folder
        if ($e.Data.GetDataPresent([Windows.Forms.ListViewItem])) {
            if ([string]::IsNullOrEmpty($script:selectedFolderId)) { return }
            $sourceFolder = @($foldersArr | Where-Object { [string]$_.id -eq $script:selectedFolderId })[0]
            $draggedItem = $e.Data.GetData([Windows.Forms.ListViewItem])
            if (!$sourceFolder -or $null -eq $draggedItem) { return }

            $movedApp = script:Move-ShortcutBetweenFolders $sourceFolder $targetFolder ([string]$draggedItem.Tag)
            if ($movedApp) {
                script:Commit-ManagerChanges
                script:Refresh-UI
                $statusLabel.Text = "Moved '$($movedApp.name)' from '$($sourceFolder.name)' to '$($targetFolder.name)'."
            }
            return
        }

        # Case 2: Dropping external files/shortcuts from Windows Explorer onto a folder
        if ($e.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) {
            $paths = @($e.Data.GetData([Windows.Forms.DataFormats]::FileDrop))
            $added = Add-ShortcutsToFolder $targetFolder $paths
            if ($added -gt 0) {
                script:Commit-ManagerChanges
                script:Refresh-UI
                $statusLabel.Text = "Added $added dropped shortcut(s) to '$($targetFolder.name)'."
            }
        }
    }

    $form.Add_DragEnter($fileDragEnterHandler)
    $folderList.Add_DragEnter($folderListDragOverHandler)
    $folderList.Add_DragOver($folderListDragOverHandler)
    $grid.Add_DragEnter($gridDragEnterHandler)
    $grid.Add_DragDrop($gridDragDropHandler)
    $folderList.Add_DragDrop($folderListDragDropHandler)

    # =========================================================================
    # INITIALIZE & SHOW
    # =========================================================================
    Apply-Theme $script:isDarkMode
    Switch-Page "Folders"
    Refresh-UI
    Layout-FolderHeader
    Layout-AppearanceCards

    $form.Add_Shown({
        [ModernWin32]::SetDarkTitleBar($form.Handle, $script:isDarkMode)
        [ModernWin32]::SetCueBanner($newFolderName.Handle, "New folder...")
        [ModernWin32]::SetCueBanner($renameBox.Handle, "Select a folder...")
        [ModernWin32]::SetCueBanner($shortcutRenameBox.Handle, "Shortcut name")
        Layout-FolderHeader
        Layout-AppearanceCards
        $form.Activate()
        $form.BringToFront()
    })

    try {
        [void]$form.ShowDialog()
    } finally {
        if ($null -ne $grid.LargeImageList) { $grid.LargeImageList.Dispose() }
        if ($null -ne $uiToolTip) { $uiToolTip.Dispose() }
        foreach ($fnt in @($fontBase, $fontTitle, $fontBrand, $fontSection, $fontCaption, $fontSmallBold, $fontNav, $fontBtn, $fontPlus, $fontList, $fontListBold, $fontBadge)) {
            if ($null -ne $fnt) { $fnt.Dispose() }
        }
        $form.Dispose()
    }
}
function Load-Data {
    if (!(Test-Path $DataFile)) {
        $starter = @{
            animation = "ExpandCollapse"
            folders = @(
                @{ id="f_work"; name="Work"; shortcuts=@() },
                @{ id="f_games"; name="Games"; shortcuts=@() }
            )
        }
        $starter | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $DataFile -Encoding UTF8
    }
    $data = Get-Content -LiteralPath $DataFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -eq $data.folders) {
        $data = [pscustomobject]@{ animation = "ExpandCollapse"; folders = @() }
    }
    if ($data -is [hashtable]) {
        if (!$data.ContainsKey("animation") -or [string]::IsNullOrWhiteSpace($data["animation"])) {
            $data["animation"] = "ExpandCollapse"
        }
    } else {
        if (!$data.PSObject.Properties['animation'] -or [string]::IsNullOrWhiteSpace($data.animation)) {
            $data | Add-Member -NotePropertyName "animation" -NotePropertyValue "ExpandCollapse" -Force
        }
    }
    if (!$data.PSObject.Properties['folderOpacity'] -or $null -eq $data.folderOpacity) {
        $data | Add-Member -NotePropertyName "folderOpacity" -NotePropertyValue 100 -Force
    }
    if (!$data.PSObject.Properties['popupOpacity'] -or $null -eq $data.popupOpacity) {
        $data | Add-Member -NotePropertyName "popupOpacity" -NotePropertyValue 100 -Force
    }
    if (!$data.PSObject.Properties['previewOpacity'] -or $null -eq $data.previewOpacity) {
        $data | Add-Member -NotePropertyName "previewOpacity" -NotePropertyValue 92 -Force
    }
    if (!$data.PSObject.Properties['gridColumns'] -or $null -eq $data.gridColumns) {
        $data | Add-Member -NotePropertyName "gridColumns" -NotePropertyValue 4 -Force
    }
    if (!$data.PSObject.Properties['gridDensity'] -or [string]::IsNullOrWhiteSpace($data.gridDensity)) {
        $data | Add-Member -NotePropertyName "gridDensity" -NotePropertyValue "Standard" -Force
    }
    if (!$data.PSObject.Properties['darkMode'] -or $null -eq $data.darkMode) {
        $data | Add-Member -NotePropertyName "darkMode" -NotePropertyValue $true -Force
    }
    return $data
}

function Save-Data($Data) {
    $json = $Data | ConvertTo-Json -Depth 20
    [IO.File]::WriteAllText($DataFile, $json, $Utf8NoBom)
}

function Extract-Icon([string]$Path, [string]$Destination, $ShellCom = $null) {
    $candidate = $Path
    $iconIndex = 0
    $ownShell = $null
    $shortcut = $null
    try {
        $ext = [IO.Path]::GetExtension($Path).ToLowerInvariant()
        if ($ext -eq ".lnk") {
            $shellToUse = $ShellCom
            if ($null -eq $shellToUse) {
                $ownShell = New-Object -ComObject WScript.Shell
                $shellToUse = $ownShell
            }
            $shortcut = $shellToUse.CreateShortcut($Path)
            if ($shortcut.IconLocation) {
                $parts = $shortcut.IconLocation -split ','
                $iconPath = $parts[0].Trim('"').Trim()
                if ($parts.Count -gt 1) { [void][int]::TryParse($parts[1].Trim(), [ref]$iconIndex) }
                if ($iconPath -and (Test-Path $iconPath)) { $candidate = $iconPath }
                elseif ($shortcut.TargetPath -and (Test-Path $shortcut.TargetPath)) { $candidate = $shortcut.TargetPath; $iconIndex = 0 }
            } elseif ($shortcut.TargetPath -and (Test-Path $shortcut.TargetPath)) {
                $candidate = $shortcut.TargetPath
            }
        } elseif ($ext -eq ".url") {
            foreach ($line in (Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue)) {
                if ($line -match '^IconFile=(.+)$') {
                    $iconPath = $matches[1].Trim('"').Trim()
                    if (Test-Path $iconPath) { $candidate = $iconPath }
                } elseif ($line -match '^IconIndex=(-?\d+)$') {
                    $iconIndex = [int]$matches[1]
                }
            }
        }

        $large = New-Object IntPtr[] 1
        $small = New-Object IntPtr[] 1
        try {
            $extracted = [IconExtractor]::ExtractIconEx($candidate, $iconIndex, $large, $small, 1)
            if ($extracted -gt 0 -and $large[0] -ne [IntPtr]::Zero) {
                $ico = [Drawing.Icon]::FromHandle($large[0])
                try {
                    $bmp = $ico.ToBitmap()
                    try {
                        $bmp.Save($Destination, [Drawing.Imaging.ImageFormat]::Png)
                    } finally {
                        $bmp.Dispose()
                    }
                } finally {
                    $ico.Dispose()
                }
                return
            }
        } finally {
            if ($large[0] -ne [IntPtr]::Zero) { [void][IconExtractor]::DestroyIcon($large[0]) }
            if ($small[0] -ne [IntPtr]::Zero) { [void][IconExtractor]::DestroyIcon($small[0]) }
        }

        $ico = [Drawing.Icon]::ExtractAssociatedIcon($candidate)
        $isSystemFallback = $false
        if (!$ico) {
            $ico = [Drawing.SystemIcons]::Application
            $isSystemFallback = $true
        }
        try {
            $bmp = $ico.ToBitmap()
            try {
                $bmp.Save($Destination, [Drawing.Imaging.ImageFormat]::Png)
            } finally {
                $bmp.Dispose()
            }
        } finally {
            if (!$isSystemFallback) { $ico.Dispose() }
        }
    } catch {
        $bmp = [Drawing.SystemIcons]::Application.ToBitmap()
        try {
            $bmp.Save($Destination, [Drawing.Imaging.ImageFormat]::Png)
        } finally {
            $bmp.Dispose()
        }
    } finally {
        if ($null -ne $shortcut) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shortcut) }
        if ($null -ne $ownShell) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($ownShell) }
    }
}

function Escape-Ini([string]$Value) {
    if ($null -eq $Value) { return "" }
    return $Value.Replace("#","##").Replace("`r"," ").Replace("`n"," ")
}

function Get-FolderDirectoryName([string]$Name) {
    $safe = $Name.Trim() -replace '[<>:"/\\|?*\x00-\x1F]', '_'
    $safe = $safe.TrimEnd(' ', '.')
    if ([string]::IsNullOrWhiteSpace($safe)) { $safe = "Folder" }
    return $safe
}

function Get-FolderDirectoryNames($Folders) {
    $used = @{}
    $names = @()
    foreach ($folder in @($Folders)) {
        $base = Get-FolderDirectoryName ([string]$folder.name)
        $name = $base
        $suffix = 2
        while ($used.ContainsKey($name)) {
            $name = "${base}_${suffix}"
            $suffix++
        }
        $used[$name] = $true
        $names += $name
    }
    return $names
}

function Write-Launcher($Data) {
    Write-MonitorMetrics
    $folders = @($Data.folders)
    if (!(Test-Path $FolderTemplate)) {
        throw "Missing shared folder template: $FolderTemplate"
    }
    if (!(Test-Path $FolderRoot)) {
        New-Item -ItemType Directory -Path $FolderRoot -Force | Out-Null
    }

    # Cache existing icon filenames once for O(1) lookups during generation
    $existingIconPaths = [IO.Directory]::GetFiles($IconDir)
    $iconSet = New-Object "System.Collections.Generic.HashSet[string]" ([StringComparer]::OrdinalIgnoreCase)
    foreach ($p in $existingIconPaths) {
        [void]$iconSet.Add([IO.Path]::GetFileName($p))
    }

    # Read existing WindowX / WindowY positions without deleting active directories
    $existingPos = @{}
    $existingDirs = @(Get-ChildItem -LiteralPath $FolderRoot -Directory -ErrorAction SilentlyContinue)
    foreach ($dir in $existingDirs) {
        $iniFile = Join-Path $dir.FullName "Folder.ini"
        if (Test-Path $iniFile) {
            $rawIni = [IO.File]::ReadAllText($iniFile, $Utf8NoBom)
            $wx = $null; $wy = $null
            if ($rawIni -match '(?m)^WindowX=(-?\d+)') { $wx = $matches[1] }
            if ($rawIni -match '(?m)^WindowY=(-?\d+)') { $wy = $matches[1] }
            if ($null -ne $wx -and $null -ne $wy) {
                $existingPos[$dir.Name] = @{ X = $wx; Y = $wy }
            }
        }
    }

    $animMode = if ($Data.PSObject.Properties['animation'] -and $Data.animation) { [string]$Data.animation } else { "ExpandCollapse" }
    $validNames = @(Get-FolderDirectoryNames $folders)

    $fOp = if ($Data.PSObject.Properties['folderOpacity'] -and $null -ne $Data.folderOpacity) { [int]$Data.folderOpacity } else { 100 }
    $popOp = if ($Data.PSObject.Properties['popupOpacity'] -and $null -ne $Data.popupOpacity) { [int]$Data.popupOpacity } else { 100 }
    $pOp = if ($Data.PSObject.Properties['previewOpacity'] -and $null -ne $Data.previewOpacity) { [int]$Data.previewOpacity } else { 92 }
    $folderAlphaScale = [Math]::Round($fOp / 100.0, 2).ToString([System.Globalization.CultureInfo]::InvariantCulture)
    $popupAlphaScale = [Math]::Round($popOp / 100.0, 2).ToString([System.Globalization.CultureInfo]::InvariantCulture)
    $previewAlpha = [int][Math]::Round(255 * ($pOp / 100.0))

    $appCols = if ($Data.PSObject.Properties['gridColumns'] -and $null -ne $Data.gridColumns) { [int]$Data.gridColumns } else { 4 }
    if ($appCols -notin @(3, 4, 5)) { $appCols = 4 }

    $density = if ($Data.PSObject.Properties['gridDensity'] -and $Data.gridDensity) { [string]$Data.gridDensity } else { "Standard" }
    if ($density -eq "Compact") {
        $cellW = 84; $cellH = 82; $padX = 12; $padY = 42
        $iconSize = 34; $labelOffset = 38; $labelH = 36; $bottomPad = 12
    } else {
        $cellW = 104; $cellH = 98; $padX = 16; $padY = 48
        $iconSize = 40; $labelOffset = 45; $labelH = 44; $bottomPad = 16
    }

    # Only delete directories for folders that were removed from Data.json
    $removedFolders = New-Object System.Collections.Generic.List[string]
    foreach ($dir in $existingDirs) {
        if ($dir.Name -notin $validNames) {
            [void]$removedFolders.Add($dir.Name)
            Remove-Item -LiteralPath $dir.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    $changedFolders = New-Object System.Collections.Generic.List[string]

    for ($i = 0; $i -lt $folders.Count; $i++) {
        $folder = $folders[$i]
        $folderId = [string]$folder.id
        $folderName = $validNames[$i]
        $folderDir = Join-Path $FolderRoot $folderName
        if (!(Test-Path $folderDir)) {
            New-Item -ItemType Directory -Path $folderDir -Force | Out-Null
        }

        if ($existingPos.ContainsKey($folderName)) {
            $x = $existingPos[$folderName].X
            $y = $existingPos[$folderName].Y
        } else {
            $x = 36 + (($i % 5) * 124)
            $y = 18 + ([Math]::Floor($i / 5) * 100)
        }

        $folderLines = New-Object System.Collections.Generic.List[string]
        $folderLines.Add("[Rainmeter]")
        $folderLines.Add("Update=16")
        $folderLines.Add("DefaultUpdateDivider=-1")
        $folderLines.Add("AccurateText=1")
        $folderLines.Add("DynamicWindowSize=1")
        $folderLines.Add("Draggable=1")
        $folderLines.Add("KeepPosition=1")
        $folderLines.Add("KeepOnScreen=0")
        $folderLines.Add("SolidColor=0,0,0,1")
        $folderLines.Add("WindowX=$x")
        $folderLines.Add("WindowY=$y")
        $folderLines.Add("")
        $folderLines.Add("[Metadata]")
        $folderLines.Add("Name=$(Escape-Ini ([string]$folder.name)) Folder")
        $folderLines.Add("Author=Custom")
        $folderLines.Add("Version=3.0")
        $folderLines.Add("")
        $folderLines.Add("[Variables]")
        $folderLines.Add("FolderID=$folderId")
        $folderLines.Add("FolderName=$(Escape-Ini ([string]$folder.name))")
        $folderLines.Add("AnimStyle=$animMode")
        $folderLines.Add("FolderAlphaScale=$folderAlphaScale")
        $folderLines.Add("PopupAlphaScale=$popupAlphaScale")
        $folderLines.Add("PreviewAlpha=$previewAlpha")

        $folderAccent = if ($folder.PSObject.Properties['accentColor']) { [string]$folder.accentColor } else { "" }
        $tintPalette = Get-FolderTintPalette $folderAccent
        foreach ($tKey in $tintPalette.Keys) {
            $folderLines.Add("$tKey=$($tintPalette[$tKey])")
        }

        $apps = @($folder.shortcuts)
        $rows = [Math]::Max(1, [Math]::Ceiling([Math]::Max(1, $apps.Count) / $appCols))
        $panelW = (2 * $padX) + ($appCols * $cellW)
        $panelH = $padY + ($rows * $cellH) + $bottomPad

        $folderLines.Add("PanelWidth=$panelW")
        $folderLines.Add("PanelHeight=$panelH")
        $folderLines.Add("GridCols=$appCols")
        $folderLines.Add("CellW=$cellW")
        $folderLines.Add("CellH=$cellH")
        $folderLines.Add("PadX=$padX")
        $folderLines.Add("PadY=$padY")
        $folderLines.Add("FolderPath=#CURRENTCONFIGDIR#")
        $folderLines.Add("")
        $folderLines.Add("@Include=#@#FolderTemplate.inc")
        $folderLines.Add("")

        # Check if this folder has a custom closed overlay icon
        $folderIcon = ""
        if ($folder.PSObject.Properties['icon'] -and !([string]::IsNullOrEmpty($folder.icon))) {
            $folderIcon = [string]$folder.icon
        }

        if (![string]::IsNullOrEmpty($folderIcon) -and $iconSet.Contains($folderIcon)) {
            $folderLines.Add("[FolderCustomIconOverlay]")
            $folderLines.Add("Meter=Image")
            $folderLines.Add("ImageName=#ROOTCONFIGPATH#Icons\$folderIcon")
            $folderLines.Add("X=(40 + #IconOffsetX#)")
            $folderLines.Add("Y=(26 + #IconOffsetY#)")
            $folderLines.Add("W=32")
            $folderLines.Add("H=32")
            $folderLines.Add("ImageAlpha=#PreviewAlpha#")
            $folderLines.Add("PreserveAspectRatio=1")
            $folderLines.Add("DynamicVariables=1")
            $folderLines.Add("MouseActionCursorName=HAND")
            $folderLines.Add('LeftMouseUpAction=[!CommandMeasure MeasureToggle "TogglePanel()"]')
            $folderLines.Add("")
        } else {
            $previewCount = [Math]::Min(4, $apps.Count)
            for ($p = 0; $p -lt $previewCount; $p++) {
                $pApp = $apps[$p]
                $pCol = $p % 2
                $pRow = [Math]::Floor($p / 2)
                $px = 38 + ($pCol * 20)
                $py = 24 + ($pRow * 20)
                $pIcon = [string]$pApp.icon
                if (!$pIcon -or !$iconSet.Contains($pIcon)) { $pIcon = "app_default.png" }

                $folderLines.Add("[FolderPreview_${p}]")
                $folderLines.Add("Meter=Image")
                $folderLines.Add("ImageName=#ROOTCONFIGPATH#Icons\$pIcon")
                $folderLines.Add("X=($px + #IconOffsetX#)")
                $folderLines.Add("Y=($py + #IconOffsetY#)")
                $folderLines.Add("W=16")
                $folderLines.Add("H=16")
                $folderLines.Add("ImageAlpha=#PreviewAlpha#")
                $folderLines.Add("PreserveAspectRatio=1")
                $folderLines.Add("DynamicVariables=1")
                $folderLines.Add("MouseActionCursorName=HAND")
                $folderLines.Add('LeftMouseUpAction=[!CommandMeasure MeasureToggle "TogglePanel()"]')
                $folderLines.Add("")
            }
        }

        if ($apps.Count -eq 0) {
            $folderLines.Add("[PanelEmpty]")
            $folderLines.Add("Meter=String")
            $folderLines.Add("Group=PanelContent")
            $folderLines.Add("X=(#PanelX# + 16)")
            $folderLines.Add("Y=(#PanelY# + 50)")
            $folderLines.Add("W=$($panelW - 32)")
            $folderLines.Add("H=24")
            $folderLines.Add("Text=No shortcuts yet.")
            $folderLines.Add("FontFace=Segoe UI")
            $folderLines.Add("FontSize=10")
            $folderLines.Add("FontColor=175,185,205,#AnimAlpha#")
            $folderLines.Add("AntiAlias=1")
            $folderLines.Add("DynamicVariables=1")
            $folderLines.Add("Hidden=1")
            $folderLines.Add("TransformationMatrix=#PanelMatrix#")
            $folderLines.Add("")
        }

        for ($j = 0; $j -lt $apps.Count; $j++) {
            $app = $apps[$j]
            $col = $j % $appCols
            $row = [Math]::Floor($j / $appCols)

            $relIconX = $padX + ($col * $cellW) + [Math]::Floor($cellW / 2) - [Math]::Floor($iconSize / 2)
            $relCenterX = $padX + ($col * $cellW) + [Math]::Floor($cellW / 2)
            $relIconY = $padY + ($row * $cellH)
            $relLabelY = $relIconY + $labelOffset

            # Full-tile hitbox dimensions (read directly by FolderPopup.lua via GetH())
            $relBoxX = $padX + ($col * $cellW) + 3
            $relBoxY = $relIconY - 6
            $boxW = $cellW - 6
            if ($density -eq "Compact") {
                $boxH = 72
            } else {
                $nameLen = ([string]$app.name).Length
                if ($nameLen -le 13) { $boxH = 74 }
                elseif ($nameLen -le 26) { $boxH = 88 }
                else { $boxH = 96 }
            }

            $appName = Escape-Ini ([string]$app.name)
            $iconName = [string]$app.icon
            if (!$iconName -or !$iconSet.Contains($iconName)) { $iconName = "app_default.png" }
            $path = Escape-Ini ([string]$app.path)

            $folderLines.Add("[AppIcon_${j}]")
            $folderLines.Add("Meter=Image")
            $folderLines.Add("Group=PanelContent")
            $folderLines.Add("ImageName=#ROOTCONFIGPATH#Icons\$iconName")
            $folderLines.Add("X=(#PanelX# + $relIconX)")
            $folderLines.Add("Y=(#PanelY# + $relIconY)")
            $folderLines.Add("W=$iconSize")
            $folderLines.Add("H=$iconSize")
            $folderLines.Add("ImageAlpha=#AnimAlpha#")
            $folderLines.Add("PreserveAspectRatio=1")
            $folderLines.Add("DynamicVariables=1")
            $folderLines.Add("Hidden=1")
            $folderLines.Add("TransformationMatrix=#PanelMatrix#")
            $folderLines.Add("")

            $folderLines.Add("[AppLabel_${j}]")
            $folderLines.Add("Meter=String")
            $folderLines.Add("Group=PanelContent")
            $folderLines.Add("X=(#PanelX# + $relCenterX)")
            $folderLines.Add("Y=(#PanelY# + $relLabelY)")
            $folderLines.Add("W=$($cellW - 10)")
            $folderLines.Add("H=$labelH")
            $folderLines.Add("Text=$appName")
            $folderLines.Add("FontFace=Segoe UI")
            $folderLines.Add("FontSize=9")
            $folderLines.Add("FontWeight=400")
            $folderLines.Add("FontColor=255,255,255,#AnimAlpha#")
            $folderLines.Add("StringAlign=Center")
            $folderLines.Add("StringEffect=Border")
            $folderLines.Add("FontEffectColor=0,0,0,(Round(220 * #AnimAlpha# / 255))")
            $folderLines.Add("ClipString=2")
            $folderLines.Add("AntiAlias=1")
            $folderLines.Add("DynamicVariables=1")
            $folderLines.Add("Hidden=1")
            $folderLines.Add("TransformationMatrix=#PanelMatrix#")
            $folderLines.Add("")

            # Full-tile invisible hitbox in its own group (shown only when idle to skip animation updates)
            $folderLines.Add("[AppHitbox_${j}]")
            $folderLines.Add("Meter=Image")
            $folderLines.Add("Group=PanelHitboxes")
            $folderLines.Add("SolidColor=0,0,0,1")
            $folderLines.Add("X=(#PanelX# + $relBoxX)")
            $folderLines.Add("Y=(#PanelY# + $relBoxY)")
            $folderLines.Add("W=$boxW")
            $folderLines.Add("H=$boxH")
            $folderLines.Add("DynamicVariables=1")
            $folderLines.Add("Hidden=1")
            $folderLines.Add("MouseActionCursorName=HAND")
            $folderLines.Add('MouseOverAction=[!CommandMeasure MeasureToggle "HoverApp(' + $j + ')"]')
            $folderLines.Add('MouseLeaveAction=[!CommandMeasure MeasureToggle "UnhoverApp(' + $j + ')"]')
            $folderLines.Add('LeftMouseUpAction=[!CommandMeasure MeasureToggle "SelectApp(' + $j + ')"]')
            $folderLines.Add('LeftMouseDoubleClickAction=["' + $path + '"][!CommandMeasure MeasureToggle "ClosePanel()"]')
            $folderLines.Add("")
        }

        $iniTarget = Join-Path $folderDir "Folder.ini"
        $newContent = ($folderLines -join "`r`n") + "`r`n"
        $needsWrite = $true
        if (Test-Path $iniTarget) {
            $oldContent = [IO.File]::ReadAllText($iniTarget, $Utf8NoBom)
            if ($oldContent -eq $newContent) {
                $needsWrite = $false
            }
        }
        if ($needsWrite) {
            [IO.File]::WriteAllText($iniTarget, $newContent, $Utf8NoBom)
            [void]$changedFolders.Add($folderName)
        }
    }

    Remove-OrphanedIcons $Data $existingIconPaths

    return [pscustomobject]@{
        Changed = @($changedFolders)
        Removed = @($removedFolders)
        All     = @($validNames)
    }
}

function Refresh-Skin {
    param(
        $Data = $null,
        [string[]]$TargetFolders,
        [string[]]$RemovedFolders = @()
    )
    if (!(Test-Path $RainmeterExe)) { return }
    if ($null -eq $Data) { $Data = Load-Data }

    $skinName = Split-Path -Leaf $Root
    $targets = if ($PSBoundParameters.ContainsKey('TargetFolders')) {
        @($TargetFolders | Where-Object { ![string]::IsNullOrEmpty($_) })
    } else {
        @(Get-FolderDirectoryNames $Data.folders)
    }
    $removed = @($RemovedFolders | Where-Object { ![string]::IsNullOrEmpty($_) })

    # 1. Batch deactivate removed skins and instantly close any open popups on target skins
    $preBangs = New-Object System.Collections.Generic.List[string]
    foreach ($rem in $removed) {
        $preBangs.Add("[!DeactivateConfig `"$skinName\Folders\$rem`"]")
    }
    foreach ($folderName in $targets) {
        $cfg = "$skinName\Folders\$folderName"
        $preBangs.Add("[!CommandMeasure MeasureToggle `"ClosePanelInstant()`" `"$cfg`"]")
    }
    Invoke-RainmeterBangs @($preBangs)

    if ($targets.Count -eq 0) { return }
    Start-Sleep -Milliseconds 60

    # 2. Batch activate and refresh target skins from updated Folder.ini
    $activateBangs = New-Object System.Collections.Generic.List[string]
    $refreshBangs = New-Object System.Collections.Generic.List[string]
    foreach ($folderName in $targets) {
        $iniPath = Join-Path $FolderRoot "$folderName\Folder.ini"
        if (Test-Path $iniPath) {
            $cfg = "$skinName\Folders\$folderName"
            $activateBangs.Add("[!ActivateConfig `"$cfg`" `"Folder.ini`"]")
            $refreshBangs.Add("[!Refresh `"$cfg`"][!Draggable 1 `"$cfg`"]")
        }
    }
    Invoke-RainmeterBangs @($activateBangs)
    Start-Sleep -Milliseconds 40
    Invoke-RainmeterBangs @($refreshBangs)
}

function Sync-FolderSkins($Data = $null) {
    Write-MonitorMetrics
    if (!(Test-Path $RainmeterExe)) { return }
    if ($null -eq $Data) { $Data = Load-Data }

    $stateFile = Join-Path $Resource "FolderState.txt"
    $previous = @()
    if (Test-Path $stateFile) {
        $previous = @(Get-Content -LiteralPath $stateFile -Encoding UTF8 | Where-Object { $_ })
    }
    $skinName = Split-Path -Leaf $Root
    $current = @(Get-FolderDirectoryNames $Data.folders)

    $bangs = New-Object System.Collections.Generic.List[string]
    foreach ($folderName in ($previous | Where-Object { $_ -notin $current })) {
        $bangs.Add("[!DeactivateConfig `"$skinName\Folders\$folderName`"]")
    }
    foreach ($folderName in $current) {
        $bangs.Add("[!ActivateConfig `"$skinName\Folders\$folderName`" `"Folder.ini`"]")
    }
    Invoke-RainmeterBangs @($bangs)
    [IO.File]::WriteAllLines($stateFile, $current, $Utf8NoBom)
}

function Get-Folder($Data) {
    $labels = @($Data.folders | ForEach-Object { [string]$_.name })
    $chosen = Select-Item "Choose folder" $labels
    if ($null -eq $chosen) { return $null }
    return @($Data.folders | Where-Object { $_.name -eq $chosen })[0]
}

$data = Load-Data
switch ($Action) {
    "LoadFolders" { Sync-FolderSkins $data; exit 0 }
    "Manage" { Show-FolderManager ([ref]$data); exit 0 }
    "AddFolder" {
        $name = Show-TextPrompt "Create folder" "Enter a folder name:"
        if ($name) {
            if (@($data.folders | Where-Object { $_.name -eq $name }).Count -gt 0) {
                [Windows.Forms.MessageBox]::Show("A folder with that name already exists.") | Out-Null
            } else {
                $id = "f_" + [Guid]::NewGuid().ToString("N").Substring(0,8)
                $data.folders = @($data.folders) + @([pscustomobject]@{ id = $id; name = $name; shortcuts = @() })
            }
        }
    }
    "RenameFolder" {
        $folder = Get-Folder $data
        if ($folder) {
            $name = Show-TextPrompt "Rename folder" "New folder name:" ([string]$folder.name)
            if ($name) { $folder.name = $name }
        }
    }
    "DeleteFolder" {
        $folder = Get-Folder $data
        if ($folder -and [Windows.Forms.MessageBox]::Show("Delete '$($folder.name)' and its shortcuts?","Confirm delete","YesNo","Warning") -eq "Yes") {
            $data.folders = @($data.folders | Where-Object { $_.id -ne $folder.id })
        }
    }
    "AddShortcut" {
        if (@($data.folders).Count -eq 0) {
            [Windows.Forms.MessageBox]::Show("Create a folder first.") | Out-Null
        } else {
            $folder = Get-Folder $data
            if ($folder) {
                $dialog = New-Object Windows.Forms.OpenFileDialog
                try {
                    $dialog.Title = "Choose an application, shortcut, or file"
                    $dialog.Filter = "All files (*.*)|*.*"
                    $dialog.CheckFileExists = $true
                    $dialog.Multiselect = $false
                    if ($dialog.ShowDialog() -eq "OK") {
                        $path = $dialog.FileName
                        $defaultName = [IO.Path]::GetFileNameWithoutExtension($path)
                        $name = Show-TextPrompt "Shortcut name" "Display name:" $defaultName
                        if (!$name) { $name = $defaultName }
                        $iconFile = "app_" + [Guid]::NewGuid().ToString("N") + ".png"
                        Extract-Icon $path (Join-Path $IconDir $iconFile)
                        $entry = [pscustomobject]@{ id = [Guid]::NewGuid().ToString("N"); name = $name; path = $path; icon = $iconFile }
                        $folder.shortcuts = @($folder.shortcuts) + @($entry)
                        if ([Windows.Forms.MessageBox]::Show("Use a custom PNG/ICO icon instead?","Custom icon","YesNo","Question") -eq "Yes") {
                            $iconDialog = New-Object Windows.Forms.OpenFileDialog
                            try {
                                $iconDialog.Title = "Choose a custom icon"
                                $iconDialog.Filter = "Icon files (*.png;*.ico;*.jpg;*.bmp)|*.png;*.ico;*.jpg;*.bmp|All files (*.*)|*.*"
                                if ($iconDialog.ShowDialog() -eq "OK") {
                                    $customName = "custom_" + [Guid]::NewGuid().ToString("N") + ".png"
                                    Save-IconAsPng $iconDialog.FileName (Join-Path $IconDir $customName)
                                    $entry.icon = $customName
                                }
                            } finally {
                                $iconDialog.Dispose()
                            }
                        }
                    }
                } finally {
                    $dialog.Dispose()
                }
            }
        }
    }
    "RemoveShortcut" {
        $folder = Get-Folder $data
        if ($folder) {
            $apps = @($folder.shortcuts)
            $labels = @($apps | ForEach-Object { [string]$_.name })
            $chosen = Select-Item "Remove shortcut from $($folder.name)" $labels
            if ($chosen) { $folder.shortcuts = @($apps | Where-Object { $_.name -ne $chosen }) }
        }
    }
    "SetCustomIcon" {
        $folder = Get-Folder $data
        if ($folder) {
            $apps = @($folder.shortcuts)
            $labels = @($apps | ForEach-Object { [string]$_.name })
            $chosen = Select-Item "Choose shortcut" $labels
            if ($chosen) {
                $app = @($apps | Where-Object { $_.name -eq $chosen })[0]
                $dialog = New-Object Windows.Forms.OpenFileDialog
                try {
                    $dialog.Title = "Choose a custom icon"
                    $dialog.Filter = "Image/icon files (*.png;*.ico;*.jpg;*.bmp)|*.png;*.ico;*.jpg;*.bmp|All files (*.*)|*.*"
                    if ($dialog.ShowDialog() -eq "OK") {
                        $customName = "custom_" + [Guid]::NewGuid().ToString("N") + ".png"
                        Save-IconAsPng $dialog.FileName (Join-Path $IconDir $customName)
                        $app.icon = $customName
                    }
                } finally {
                    $dialog.Dispose()
                }
            }
        }
    }
    "SetAnimation" {
        $data.animation = $AnimStyle
        Save-Data $data
        $sync = Write-Launcher $data
        Refresh-Skin $data -TargetFolders @($sync.Changed) -RemovedFolders @($sync.Removed)
        exit 0
    }
    "SyncMonitors" { Write-MonitorMetrics; Refresh-Skin $data; exit 0 }
    "ResetLayout" { }
    "Initialize" {
        $shell = $null
        try {
            foreach ($f in @($data.folders)) {
                foreach ($s in @($f.shortcuts)) {
                    if ($s.icon -like "app_*" -and (Test-Path $s.path)) {
                        if ($null -eq $shell -and [IO.Path]::GetExtension($s.path).Equals(".lnk", [StringComparison]::OrdinalIgnoreCase)) {
                            $shell = New-Object -ComObject WScript.Shell
                        }
                        Extract-Icon $s.path (Join-Path $IconDir $s.icon) $shell
                    }
                }
            }
        } finally {
            if ($null -ne $shell) {
                [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
            }
        }
    }
}

Save-Data $data
$sync = Write-Launcher $data
if ($Action -in @("ResetLayout", "Initialize")) {
    Refresh-Skin $data -RemovedFolders @($sync.Removed)
} else {
    Refresh-Skin $data -TargetFolders @($sync.Changed) -RemovedFolders @($sync.Removed)
}
