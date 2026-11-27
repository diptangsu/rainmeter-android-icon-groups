param(
    [ValidateSet("Initialize","LoadFolders","Manage","AddFolder","RenameFolder","DeleteFolder","AddShortcut","RemoveShortcut","SetCustomIcon","ReorderShortcut","SetAnimation","ResetLayout")]
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
    $form = New-Object Windows.Forms.Form
    $form.Size = New-Object Drawing.Size(940, 640)
    $form.MinimumSize = New-Object Drawing.Size(880, 560)
    $form.Text = "Icon Folder Settings"
    $form.AutoScaleMode = "Dpi"
    $form.StartPosition = "CenterScreen"
    $form.TopMost = $false
    $form.Font = New-Object Drawing.Font("Segoe UI", 9.5)
    $form.BackColor = [Drawing.Color]::FromArgb(245, 246, 248)

    # --- LEFT SIDEBAR (Pure Dock Layout + 14px Inner Padding) ---
    $sidebar = New-Object Windows.Forms.Panel
    $sidebar.Dock = "Left"
    $sidebar.Width = 230
    $sidebar.Padding = New-Object Windows.Forms.Padding(14, 14, 14, 16)
    $sidebar.BackColor = [Drawing.Color]::FromArgb(232, 235, 242)

    $sidebarTop = New-Object Windows.Forms.Panel
    $sidebarTop.Dock = "Top"
    $sidebarTop.Height = 152

    $sidebarTitle = New-Object Windows.Forms.Label
    $sidebarTitle.Text = "FOLDERS"
    $sidebarTitle.Location = New-Object Drawing.Point(0, 0)
    $sidebarTitle.Size = New-Object Drawing.Size(202, 20)
    $sidebarTitle.Font = New-Object Drawing.Font("Segoe UI", 9, [Drawing.FontStyle]::Bold)
    $sidebarTitle.ForeColor = [Drawing.Color]::FromArgb(95, 105, 125)

    $allFoldersBtn = New-Object Windows.Forms.Button
    $allFoldersBtn.Text = "All Folders (Overview)"
    $allFoldersBtn.Location = New-Object Drawing.Point(0, 24)
    $allFoldersBtn.Size = New-Object Drawing.Size(202, 30)
    $allFoldersBtn.FlatStyle = "Flat"
    $allFoldersBtn.BackColor = [Drawing.Color]::FromArgb(215, 222, 235)
    $allFoldersBtn.FlatAppearance.BorderSize = 0

    $newFolderLabel = New-Object Windows.Forms.Label
    $newFolderLabel.Text = "Create New Folder:"
    $newFolderLabel.Location = New-Object Drawing.Point(0, 62)
    $newFolderLabel.Size = New-Object Drawing.Size(202, 18)
    $newFolderLabel.ForeColor = [Drawing.Color]::FromArgb(80, 90, 110)

    $newFolderName = New-Object Windows.Forms.TextBox
    $newFolderName.Location = New-Object Drawing.Point(0, 82)
    $newFolderName.Size = New-Object Drawing.Size(202, 25)

    $newFolderButton = New-Object Windows.Forms.Button
    $newFolderButton.Text = "+ Create Folder"
    $newFolderButton.Location = New-Object Drawing.Point(0, 112)
    $newFolderButton.Size = New-Object Drawing.Size(202, 32)
    $newFolderButton.FlatStyle = "Flat"
    $newFolderButton.BackColor = [Drawing.Color]::FromArgb(83, 125, 205)
    $newFolderButton.ForeColor = [Drawing.Color]::White
    $newFolderButton.FlatAppearance.BorderSize = 0

    $sidebarTop.Controls.AddRange(@($sidebarTitle, $allFoldersBtn, $newFolderLabel, $newFolderName, $newFolderButton))

    $folderList = New-Object Windows.Forms.ListBox
    $folderList.Dock = "Fill"
    $folderList.IntegralHeight = $false
    $folderList.BorderStyle = "FixedSingle"
    $folderList.BackColor = [Drawing.Color]::White
    $folderList.Font = New-Object Drawing.Font("Segoe UI", 10)

    # In WinForms, Dock="Fill" is added first so it fills the remaining space below Dock="Top"
    $sidebar.Controls.Add($folderList)
    $sidebar.Controls.Add($sidebarTop)

    # --- RIGHT MAIN PANEL (Pure Dock Layout + 20px Inner Padding) ---
    $main = New-Object Windows.Forms.Panel
    $main.Dock = "Fill"
    $main.Padding = New-Object Windows.Forms.Padding(20, 14, 20, 14)

    # Inside Show-FolderManager, enlarge Top panel for better visual padding
    $mainTop = New-Object Windows.Forms.Panel
    $mainTop.Dock = "Top"
    $mainTop.Height = 220

    $customFolderIconBtn = New-Object Windows.Forms.Button
    $customFolderIconBtn.Text = "Change Folder Icon"
    $customFolderIconBtn.Location = New-Object Drawing.Point(12, 150)
    $customFolderIconBtn.Size = New-Object Drawing.Size(145, 28)

    $restoreFolderIconBtn = New-Object Windows.Forms.Button
    $restoreFolderIconBtn.Text = "Restore Default Icon"
    $restoreFolderIconBtn.Location = New-Object Drawing.Point(165, 150)
    $restoreFolderIconBtn.Size = New-Object Drawing.Size(145, 28)

    $customFolderIconBtn.Location = New-Object Drawing.Point(0, 182)
    $customFolderIconBtn.Size = New-Object Drawing.Size(140, 28)

    $restoreFolderIconBtn.Location = New-Object Drawing.Point(146, 182)
    $restoreFolderIconBtn.Size = New-Object Drawing.Size(140, 28)

    $colsLabel = New-Object Windows.Forms.Label
    $colsLabel.Text = "Columns:"
    $colsLabel.Location = New-Object Drawing.Point(300, 186)
    $colsLabel.Size = New-Object Drawing.Size(58, 22)

    $colsCombo = New-Object Windows.Forms.ComboBox
    $colsCombo.Location = New-Object Drawing.Point(360, 183)
    $colsCombo.Size = New-Object Drawing.Size(48, 25)
    $colsCombo.DropDownStyle = "DropDownList"
    [void]$colsCombo.Items.AddRange(@("3", "4", "5"))

    $densityLabel = New-Object Windows.Forms.Label
    $densityLabel.Text = "Spacing:"
    $densityLabel.Location = New-Object Drawing.Point(420, 186)
    $densityLabel.Size = New-Object Drawing.Size(56, 22)

    $densityCombo = New-Object Windows.Forms.ComboBox
    $densityCombo.Location = New-Object Drawing.Point(478, 183)
    $densityCombo.Size = New-Object Drawing.Size(100, 25)
    $densityCombo.DropDownStyle = "DropDownList"
    [void]$densityCombo.Items.AddRange(@("Standard", "Compact"))

    $breadcrumb = New-Object Windows.Forms.Label
    $breadcrumb.Location = New-Object Drawing.Point(0, 0)
    $breadcrumb.Size = New-Object Drawing.Size(600, 28)
    $breadcrumb.Text = "All Folders"
    $breadcrumb.Font = New-Object Drawing.Font("Segoe UI", 13, [Drawing.FontStyle]::Bold)

    $backButton = New-Object Windows.Forms.Button
    $backButton.Text = "< Back"; $backButton.Location = New-Object Drawing.Point(0, 36); $backButton.Size = New-Object Drawing.Size(70, 32)

    $addShortcutButton = New-Object Windows.Forms.Button
    $addShortcutButton.Text = "+ Add Shortcut(s)"; $addShortcutButton.Location = New-Object Drawing.Point(78, 36); $addShortcutButton.Size = New-Object Drawing.Size(130, 32)

    $customIconButton = New-Object Windows.Forms.Button
    $customIconButton.Text = "Change Icon"; $customIconButton.Location = New-Object Drawing.Point(216, 36); $customIconButton.Size = New-Object Drawing.Size(102, 32)

    $removeButton = New-Object Windows.Forms.Button
    $removeButton.Text = "Remove Shortcut"; $removeButton.Location = New-Object Drawing.Point(326, 36); $removeButton.Size = New-Object Drawing.Size(126, 32)

    $deleteFolderButton = New-Object Windows.Forms.Button
    $deleteFolderButton.Text = "Delete Folder"; $deleteFolderButton.Location = New-Object Drawing.Point(460, 36); $deleteFolderButton.Size = New-Object Drawing.Point(110, 32)

    $renameLabel = New-Object Windows.Forms.Label
    $renameLabel.Text = "Name:"; $renameLabel.Location = New-Object Drawing.Point(0, 81); $renameLabel.Size = New-Object Drawing.Size(48, 22)

    $renameBox = New-Object Windows.Forms.TextBox
    $renameBox.Location = New-Object Drawing.Point(52, 78); $renameBox.Size = New-Object Drawing.Size(240, 25)

    $renameButton = New-Object Windows.Forms.Button
    $renameButton.Text = "Save Name"; $renameButton.Location = New-Object Drawing.Point(300, 76); $renameButton.Size = New-Object Drawing.Size(96, 28)

    $animLabel = New-Object Windows.Forms.Label
    $animLabel.Text = "Animation:"; $animLabel.Location = New-Object Drawing.Point(410, 81); $animLabel.Size = New-Object Drawing.Size(68, 22)

    $animCombo = New-Object Windows.Forms.ComboBox
    $animCombo.Location = New-Object Drawing.Point(480, 77); $animCombo.Size = New-Object Drawing.Size(125, 25)
    $animCombo.DropDownStyle = "DropDownList"
    [void]$animCombo.Items.AddRange(@(
        "ExpandCollapse", "ElasticBounce", "SubtlePop", "Settle",
        "VerticalBounce", "Snap", "Slide", "Fade", "None"
    ))

    $initFOp = if ($Data.Value.PSObject.Properties['folderOpacity'] -and $null -ne $Data.Value.folderOpacity) { [int]$Data.Value.folderOpacity } else { 100 }
    $initPopOp = if ($Data.Value.PSObject.Properties['popupOpacity'] -and $null -ne $Data.Value.popupOpacity) { [int]$Data.Value.popupOpacity } else { 100 }
    $initPOp = if ($Data.Value.PSObject.Properties['previewOpacity'] -and $null -ne $Data.Value.previewOpacity) { [int]$Data.Value.previewOpacity } else { 92 }

    $folderOpLabel = New-Object Windows.Forms.Label
    $folderOpLabel.Text = "Folder Opacity: ${initFOp}%"
    $folderOpLabel.Location = New-Object Drawing.Point(0, 114)
    $folderOpLabel.Size = New-Object Drawing.Size(134, 22)

    $folderOpSlider = New-Object Windows.Forms.TrackBar
    $folderOpSlider.Location = New-Object Drawing.Point(134, 110)
    $folderOpSlider.Size = New-Object Drawing.Size(145, 28)
    $folderOpSlider.Minimum = 10; $folderOpSlider.Maximum = 100
    $folderOpSlider.TickStyle = "None"; $folderOpSlider.AutoSize = $false
    $folderOpSlider.Value = [Math]::Max(10, [Math]::Min(100, $initFOp))

    $popupOpLabel = New-Object Windows.Forms.Label
    $popupOpLabel.Text = "Popup Opacity: ${initPopOp}%"
    $popupOpLabel.Location = New-Object Drawing.Point(295, 114)
    $popupOpLabel.Size = New-Object Drawing.Size(134, 22)

    $popupOpSlider = New-Object Windows.Forms.TrackBar
    $popupOpSlider.Location = New-Object Drawing.Point(429, 110)
    $popupOpSlider.Size = New-Object Drawing.Size(145, 28)
    $popupOpSlider.Minimum = 10; $popupOpSlider.Maximum = 100
    $popupOpSlider.TickStyle = "None"; $popupOpSlider.AutoSize = $false
    $popupOpSlider.Value = [Math]::Max(10, [Math]::Min(100, $initPopOp))

    $prevOpLabel = New-Object Windows.Forms.Label
    $prevOpLabel.Text = "Preview Opacity: ${initPOp}%"
    $prevOpLabel.Location = New-Object Drawing.Point(0, 148)
    $prevOpLabel.Size = New-Object Drawing.Size(134, 22)

    $prevOpSlider = New-Object Windows.Forms.TrackBar
    $prevOpSlider.Location = New-Object Drawing.Point(134, 144)
    $prevOpSlider.Size = New-Object Drawing.Size(145, 28)
    $prevOpSlider.Minimum = 0; $prevOpSlider.Maximum = 100
    $prevOpSlider.TickStyle = "None"; $prevOpSlider.AutoSize = $false
    $prevOpSlider.Value = [Math]::Max(0, [Math]::Min(100, $initPOp))

    $resetOpacityBtn = New-Object Windows.Forms.Button
    $resetOpacityBtn.Text = "Reset Opacity"
    $resetOpacityBtn.Location = New-Object Drawing.Point(295, 144)
    $resetOpacityBtn.Size = New-Object Drawing.Size(115, 28)

    $customFolderIconBtn = New-Object Windows.Forms.Button
    $customFolderIconBtn.Text = "Change Folder Icon"
    $customFolderIconBtn.Location = New-Object Drawing.Point(0, 182)
    $customFolderIconBtn.Size = New-Object Drawing.Size(145, 28)

    $restoreFolderIconBtn = New-Object Windows.Forms.Button
    $restoreFolderIconBtn.Text = "Restore Default Icon"
    $restoreFolderIconBtn.Location = New-Object Drawing.Point(153, 182)
    $restoreFolderIconBtn.Size = New-Object Drawing.Size(145, 28)

    $mainTop.Controls.AddRange(@(
        $breadcrumb, $backButton, $addShortcutButton, $customIconButton,
        $removeButton, $deleteFolderButton, $renameLabel, $renameBox, $renameButton,
        $animLabel, $animCombo,
        $folderOpLabel, $folderOpSlider, $popupOpLabel, $popupOpSlider,
        $prevOpLabel, $prevOpSlider, $resetOpacityBtn,
        $customFolderIconBtn, $restoreFolderIconBtn,
        $colsLabel, $colsCombo, $densityLabel, $densityCombo
    ))

    $statusLabel = New-Object Windows.Forms.Label
    $statusLabel.Dock = "Bottom"
    $statusLabel.Height = 26
    $statusLabel.TextAlign = "BottomLeft"
    $statusLabel.ForeColor = [Drawing.Color]::FromArgb(100, 110, 130)
    $statusLabel.Text = "Double-click a folder to view its shortcuts, or select a folder on the left."

    $grid = New-Object Windows.Forms.ListView
    $grid.Dock = "Fill"
    $grid.View = "LargeIcon"
    $grid.LargeImageList = New-Object Windows.Forms.ImageList
    $grid.LargeImageList.ImageSize = New-Object Drawing.Size(48, 48)
    $grid.LargeImageList.ColorDepth = "Depth32Bit"
    $grid.BorderStyle = "FixedSingle"
    $grid.BackColor = $bgPanel
    $grid.ForeColor = $fgWhite
    $grid.MultiSelect = $false
    $grid.AllowDrop = $true

    # --- DRAG & DROP REORDERING INSIDE SETTINGS GRID ---
    $grid.Add_ItemDrag({
        param($sender, $e)
        if (![string]::IsNullOrEmpty($script:selectedFolderId)) {
            $grid.DoDragDrop($e.Item, [Windows.Forms.DragDropEffects]::Move)
        }
    })

    $grid.Add_DragEnter({
        param($sender, $e)
        if ($e.Data.GetDataPresent([Windows.Forms.ListViewItem])) {
            $e.Effect = [Windows.Forms.DragDropEffects]::Move
        } else {
            $e.Effect = [Windows.Forms.DragDropEffects]::None
        }
    })

    $grid.Add_DragDrop({
        param($sender, $e)
        if ([string]::IsNullOrEmpty($script:selectedFolderId)) { return }
        $folder = @($Data.Value.folders | Where-Object { [string]$_.id -eq $script:selectedFolderId })[0]
        if (!$folder) { return }

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
            $list = New-Object System.Collections.ArrayList
            foreach ($s in $shortcutsArr) { [void]$list.Add($s) }
            $item = $list[$fromIdx]
            $list.RemoveAt($fromIdx)
            $list.Insert($toIdx, $item)
            $folder.shortcuts = @($list)

            script:Commit-ManagerChanges
            script:Refresh-UI
            $grid.Invalidate()
            $grid.Refresh()
            $statusLabel.Text = "Rearranged shortcuts successfully."
        }
    })

    # Add Dock="Fill" first, then Bottom and Top so WinForms docks them in the exact inner rectangle
    $main.Controls.Add($grid)
    $main.Controls.Add($statusLabel)
    $main.Controls.Add($mainTop)

    $form.Controls.Add($main)
    $form.Controls.Add($sidebar)

    $script:selectedFolderId = $null
    $script:suppressListEvent = $false

    function script:Load-UnlockedImage([string]$Path) {
        $bytes = [IO.File]::ReadAllBytes($Path)
        $ms = New-Object IO.MemoryStream(,$bytes)
        return [Drawing.Image]::FromStream($ms)
    }

    function script:Commit-ManagerChanges {
        Save-Data $Data.Value
        Write-Launcher $Data.Value
        Refresh-Skin
    }

    function script:Refresh-UI {
        $script:suppressListEvent = $true
        $folderList.BeginUpdate()
        $folderList.Items.Clear()
        $selIdx = -1
        $foldersArr = @($Data.Value.folders)
        for ($i = 0; $i -lt $foldersArr.Count; $i++) {
            [void]$folderList.Items.Add([string]$foldersArr[$i].name)
            if ([string]$foldersArr[$i].id -eq $script:selectedFolderId) { $selIdx = $i }
        }
        if ($selIdx -ge 0) { $folderList.SelectedIndex = $selIdx }
        $folderList.EndUpdate()

        $grid.BeginUpdate()
        $grid.Items.Clear()
        $grid.LargeImageList.Images.Clear()

        $folderIconPath = Join-Path $IconDir "folder.png"
        if (!(Test-Path $folderIconPath)) { $folderIconPath = Join-Path $IconDir "app_default.png" }
        if (Test-Path $folderIconPath) {
            $grid.LargeImageList.Images.Add("folder", (Load-UnlockedImage $folderIconPath))
        }

        if ([string]::IsNullOrEmpty($script:selectedFolderId)) {
            $breadcrumb.Text = "All Folders"
            $customFolderIconBtn.Enabled = $false
            $restoreFolderIconBtn.Enabled = $false
            $backButton.Enabled = $false
            $addShortcutButton.Enabled = $false
            $customIconButton.Enabled = $false
            $removeButton.Enabled = $false
            $deleteFolderButton.Enabled = $false
            $renameBox.Text = ""
            $renameBox.Enabled = $false
            $renameButton.Enabled = $false

            foreach ($f in $foldersArr) {
                $item = New-Object Windows.Forms.ListViewItem([string]$f.name)
                $item.Tag = [string]$f.id
                $item.ImageKey = "folder"
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
            $breadcrumb.Text = "All Folders  >  " + [string]$folder.name
            $customFolderIconBtn.Enabled = $true
            $restoreFolderIconBtn.Enabled = $true
            $backButton.Enabled = $true
            $addShortcutButton.Enabled = $true
            $customIconButton.Enabled = $false
            $removeButton.Enabled = $false
            $deleteFolderButton.Enabled = $true
            $renameBox.Enabled = $true
            $renameButton.Enabled = $true
            $renameBox.Text = [string]$folder.name

            foreach ($s in @($folder.shortcuts)) {
                $iconName = [string]$s.icon
                $iconPath = Join-Path $IconDir $iconName
                if (!$iconName -or !(Test-Path $iconPath)) { $iconPath = Join-Path $IconDir "app_default.png" }
                $imgKey = "app_" + [string]$s.id
                if ((Test-Path $iconPath) -and !$grid.LargeImageList.Images.ContainsKey($imgKey)) {
                    try { $grid.LargeImageList.Images.Add($imgKey, (Load-UnlockedImage $iconPath)) } catch {}
                }
                $item = New-Object Windows.Forms.ListViewItem([string]$s.name)
                $item.Tag = [string]$s.id
                $item.ImageKey = $imgKey
                [void]$grid.Items.Add($item)
            }
        }
        $grid.EndUpdate()

        $curAnim = if ($Data.Value.animation) { [string]$Data.Value.animation } else { "ExpandCollapse" }
        $animIdx = $animCombo.Items.IndexOf($curAnim)
        if ($animIdx -ge 0 -and $animCombo.SelectedIndex -ne $animIdx) {
            $animCombo.SelectedIndex = $animIdx
        }

        $curCols = if ($Data.Value.PSObject.Properties['gridColumns'] -and $null -ne $Data.Value.gridColumns) { [string]$Data.Value.gridColumns } else { "4" }
        $colsIdx = $colsCombo.Items.IndexOf($curCols)
        if ($colsIdx -ge 0 -and $colsCombo.SelectedIndex -ne $colsIdx) {
            $colsCombo.SelectedIndex = $colsIdx
        }

        $curDensity = if ($Data.Value.PSObject.Properties['gridDensity'] -and $Data.Value.gridDensity) { [string]$Data.Value.gridDensity } else { "Standard" }
        $densIdx = $densityCombo.Items.IndexOf($curDensity)
        if ($densIdx -ge 0 -and $densityCombo.SelectedIndex -ne $densIdx) {
            $densityCombo.SelectedIndex = $densIdx
        }

        # Force immediate UI repaint
        $grid.Invalidate()
        $grid.Refresh()
        Update-FolderButtons
        $script:suppressListEvent = $false
    }

    $allFoldersBtn.Add_Click({
        $script:selectedFolderId = $null
        $folderList.ClearSelected()
        Refresh-UI
    })

    $backButton.Add_Click({
        $script:selectedFolderId = $null
        $folderList.ClearSelected()
        Refresh-UI
    })

    $folderList.Add_SelectedIndexChanged({
        if ($script:suppressListEvent -or $folderList.SelectedIndex -lt 0) { return }
        $foldersArr = @($Data.Value.folders)
        $script:selectedFolderId = [string]$foldersArr[$folderList.SelectedIndex].id
        Refresh-UI
    })

    $grid.Add_SelectedIndexChanged({
        $hasSel = ($grid.SelectedItems.Count -gt 0)

        if ([string]::IsNullOrEmpty($script:selectedFolderId)) {
            $renameBox.Enabled = $hasSel
            $renameButton.Enabled = $hasSel
            $renameBox.Text = if ($hasSel) { $grid.SelectedItems[0].Text } else { "" }
        } else {
            $customIconButton.Enabled = $hasSel
            $removeButton.Enabled = $hasSel
            if ($hasSel) {
                $renameBox.Text = $grid.SelectedItems[0].Text
            } else {
                $folder = @($Data.Value.folders | Where-Object { [string]$_.id -eq $script:selectedFolderId })[0]
                if ($folder) { $renameBox.Text = [string]$folder.name }
            }
        }

        Update-FolderButtons
    })

    $grid.Add_DoubleClick({
        if ($grid.SelectedItems.Count -eq 0) { return }
        if ([string]::IsNullOrEmpty($script:selectedFolderId)) {
            $script:selectedFolderId = [string]$grid.SelectedItems[0].Tag
            Refresh-UI
        } else {
            $folder = @($Data.Value.folders | Where-Object { [string]$_.id -eq $script:selectedFolderId })[0]
            $shortcut = @($folder.shortcuts | Where-Object { [string]$_.id -eq [string]$grid.SelectedItems[0].Tag })[0]
            if ($shortcut -and (Test-Path ([string]$shortcut.path))) { Start-Process ([string]$shortcut.path) }
        }
    })

    $newFolderButton.Add_Click({
        $name = $newFolderName.Text.Trim()
        if (!$name) { $statusLabel.Text = "Type a new folder name in the sidebar box first."; $newFolderName.Focus(); return }
        if (@($Data.Value.folders | Where-Object { [string]$_.name -eq $name }).Count -gt 0) {
            $statusLabel.Text = "A folder named '$name' already exists."; return
        }
        $newId = "f_" + [Guid]::NewGuid().ToString("N").Substring(0,8)
        $newObj = [pscustomobject]@{ id = $newId; name = $name; shortcuts = @() }
        $Data.Value.folders = @($Data.Value.folders) + @($newObj)
        $newFolderName.Text = ""
        $script:selectedFolderId = $newId
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
        $dialog.Title = "Select Application(s), Shortcut(s), or File(s)"
        $dialog.Filter = "All files (*.*)|*.*"
        $dialog.DereferenceLinks = $false
        $dialog.Multiselect = $true
        if ($dialog.ShowDialog() -ne "OK") { return }
        foreach ($path in @($dialog.FileNames)) {
            $defaultName = [IO.Path]::GetFileNameWithoutExtension($path)
            $iconFile = "app_" + [Guid]::NewGuid().ToString("N") + ".png"
            Extract-Icon $path (Join-Path $IconDir $iconFile)
            $newApp = [pscustomobject]@{ id = [Guid]::NewGuid().ToString("N"); name = $defaultName; path = $path; icon = $iconFile }
            $folder.shortcuts = @($folder.shortcuts) + @($newApp)
        }
        Commit-ManagerChanges
        Refresh-UI
        $statusLabel.Text = "Added shortcut(s) to '$($folder.name)'."
    })

    $renameButton.Add_Click({
        $newName = $renameBox.Text.Trim()
        if (!$newName) { return }
        if ([string]::IsNullOrEmpty($script:selectedFolderId)) {
            if ($grid.SelectedItems.Count -gt 0) {
                $fId = [string]$grid.SelectedItems[0].Tag
                $f = @($Data.Value.folders | Where-Object { [string]$_.id -eq $fId })[0]
                if ($f) { $f.name = $newName; Commit-ManagerChanges; Refresh-UI; $statusLabel.Text = "Renamed folder to '$newName'." }
            }
            return
        }
        $folder = @($Data.Value.folders | Where-Object { [string]$_.id -eq $script:selectedFolderId })[0]
        if (!$folder) { return }
        if ($grid.SelectedItems.Count -gt 0) {
            $appId = [string]$grid.SelectedItems[0].Tag
            $app = @($folder.shortcuts | Where-Object { [string]$_.id -eq $appId })[0]
            if ($app) { $app.name = $newName; Commit-ManagerChanges; Refresh-UI; $statusLabel.Text = "Renamed shortcut to '$newName'." }
        } else {
            $folder.name = $newName
            Commit-ManagerChanges
            Refresh-UI
            $statusLabel.Text = "Renamed folder to '$newName'."
        }
    })

    $animCombo.Add_SelectedIndexChanged({
        if ($script:suppressListEvent -or $script:suppressAnimEvent) { return }
        $chosenAnim = [string]$animCombo.SelectedItem
        if (!$chosenAnim) { return }

        $currentAnim = if ($Data.Value.PSObject.Properties['animation']) { [string]$Data.Value.animation } else { "" }
        if ($currentAnim -eq $chosenAnim) { return }

        if ($Data.Value.PSObject.Properties['animation']) {
            $Data.Value.animation = $chosenAnim
        } else {
            $Data.Value | Add-Member -NotePropertyName "animation" -NotePropertyValue $chosenAnim -Force
        }

        Save-Data $Data.Value

        # Fast in-place update of AnimStyle= in each Folder.ini (avoids full Write-Launcher rebuild)
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        $skinName = Split-Path -Leaf $Root
        $folderNames = @(Get-FolderDirectoryNames $Data.Value.folders)
        $bangList = New-Object System.Collections.Generic.List[string]

        foreach ($folderName in $folderNames) {
            $iniPath = Join-Path $FolderRoot "$folderName\Folder.ini"
            if (Test-Path $iniPath) {
                $raw = [IO.File]::ReadAllText($iniPath, $utf8)
                $updated = [Regex]::Replace($raw, '(?m)^AnimStyle=.*$', "AnimStyle=$chosenAnim")
                if ($updated -ne $raw) {
                    [IO.File]::WriteAllText($iniPath, $updated, $utf8)
                }
            }
            $bangList.Add("[!SetVariable AnimStyle `"$chosenAnim`" `"$skinName\Folders\$folderName`"]")
        }

        # Single non-blocking Rainmeter.exe call for all folders at once
        if ((Test-Path $RainmeterExe) -and $bangList.Count -gt 0) {
            Start-Process -FilePath $RainmeterExe -ArgumentList ($bangList -join "") -WindowStyle Hidden
        }

        $statusLabel.Text = "Applied '$chosenAnim' animation to all folders."
    })

    $colsCombo.Add_SelectedIndexChanged({
        if ($script:suppressListEvent) { return }
        $chosenCols = [int]$colsCombo.SelectedItem
        if ([int]$Data.Value.gridColumns -eq $chosenCols) { return }

        if ($Data.Value.PSObject.Properties['gridColumns']) { $Data.Value.gridColumns = $chosenCols }
        else { $Data.Value | Add-Member -NotePropertyName "gridColumns" -NotePropertyValue $chosenCols -Force }

        Commit-ManagerChanges
        $statusLabel.Text = "Updated popup grid to $chosenCols columns."
    })

    $densityCombo.Add_SelectedIndexChanged({
        if ($script:suppressListEvent) { return }
        $chosenDensity = [string]$densityCombo.SelectedItem
        if ([string]$Data.Value.gridDensity -eq $chosenDensity) { return }

        if ($Data.Value.PSObject.Properties['gridDensity']) { $Data.Value.gridDensity = $chosenDensity }
        else { $Data.Value | Add-Member -NotePropertyName "gridDensity" -NotePropertyValue $chosenDensity -Force }

        Commit-ManagerChanges
        $statusLabel.Text = "Updated icon spacing to $chosenDensity."
    })

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

            $utf8 = New-Object System.Text.UTF8Encoding($false)
            foreach ($folderName in $folderNames) {
                $iniPath = Join-Path $FolderRoot "$folderName\Folder.ini"
                if (Test-Path $iniPath) {
                    $raw = [IO.File]::ReadAllText($iniPath, $utf8)
                    $updated = [Regex]::Replace($raw, '(?m)^FolderAlphaScale=.*$', "FolderAlphaScale=$folderScale")
                    if ($updated -match '(?m)^PopupAlphaScale=') {
                        $updated = [Regex]::Replace($updated, '(?m)^PopupAlphaScale=.*$', "PopupAlphaScale=$popupScale")
                    } else {
                        $updated = [Regex]::Replace($updated, '(?m)^(FolderAlphaScale=.*)$', "`$1`r`nPopupAlphaScale=$popupScale")
                    }
                    $updated = [Regex]::Replace($updated, '(?m)^PreviewAlpha=.*$', "PreviewAlpha=$prevAlpha")
                    if ($updated -ne $raw) {
                        [IO.File]::WriteAllText($iniPath, $updated, $utf8)
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

        if ((Test-Path $RainmeterExe) -and $bangList.Count -gt 0) {
            Start-Process -FilePath $RainmeterExe -ArgumentList ($bangList -join "") -WindowStyle Hidden
        }
    }

    $folderOpSlider.Add_Scroll({
        $folderOpLabel.Text = "Folder Opacity: $($folderOpSlider.Value)%"
        Apply-OpacityLive $false
    })
    $folderOpSlider.Add_MouseUp({
        Apply-OpacityLive $true
        $statusLabel.Text = "Updated folder icon opacity to $($folderOpSlider.Value)%."
    })

    $popupOpSlider.Add_Scroll({
        $popupOpLabel.Text = "Popup Opacity: $($popupOpSlider.Value)%"
        Apply-OpacityLive $false
    })
    $popupOpSlider.Add_MouseUp({
        Apply-OpacityLive $true
        $statusLabel.Text = "Updated popup panel opacity to $($popupOpSlider.Value)%."
    })

    $prevOpSlider.Add_Scroll({
        $prevOpLabel.Text = "Preview Opacity: $($prevOpSlider.Value)%"
        Apply-OpacityLive $false
    })
    $prevOpSlider.Add_MouseUp({
        Apply-OpacityLive $true
        $statusLabel.Text = "Updated preview icon opacity to $($prevOpSlider.Value)%."
    })

    $resetOpacityBtn.Add_Click({
        $folderOpSlider.Value = 100
        $popupOpSlider.Value = 100
        $prevOpSlider.Value = 92
        $folderOpLabel.Text = "Folder Opacity: 100%"
        $popupOpLabel.Text = "Popup Opacity: 100%"
        $prevOpLabel.Text = "Preview Opacity: 92%"
        Apply-OpacityLive $true
        $statusLabel.Text = "Reset opacity to defaults (Folder 100%, Popup 100%, Preview 92%)."
    })

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

    function script:Update-FolderButtons {
        $hasTarget = ($null -ne (Get-TargetFolder))
        $deleteFolderButton.Enabled = $hasTarget
        $customFolderIconBtn.Enabled = $hasTarget
        $restoreFolderIconBtn.Enabled = $hasTarget
    }

    $customFolderIconBtn.Add_Click({
        $folder = Get-TargetFolder
        if (!$folder) { return }

        $dlg = New-Object Windows.Forms.OpenFileDialog
        $dlg.Title = "Choose Custom Folder Icon"
        $dlg.Filter = "Images (*.png;*.ico;*.jpg;*.bmp)|*.png;*.ico;*.jpg;*.bmp"
        if ($dlg.ShowDialog() -eq "OK") {
            $customName = "folder_" + $folder.id + ".png"
            $img = Load-UnlockedImage $dlg.FileName
            $bmp = New-Object Drawing.Bitmap($img)
            $bmp.Save((Join-Path $IconDir $customName), [Drawing.Imaging.ImageFormat]::Png)
            $bmp.Dispose(); $img.Dispose()

            if ($folder.PSObject.Properties['icon']) { $folder.icon = $customName }
            else { $folder | Add-Member -NotePropertyName "icon" -NotePropertyValue $customName -Force }

            Commit-ManagerChanges
            Refresh-UI
            $statusLabel.Text = "Applied custom folder icon to '$($folder.name)'."
        }
    })

    $restoreFolderIconBtn.Add_Click({
        $folder = Get-TargetFolder
        if (!$folder) { return }

        if ($folder.PSObject.Properties['icon']) {
            $folder.icon = ""
        }
        $customName = "folder_" + $folder.id + ".png"
        $filePath = Join-Path $IconDir $customName
        if (Test-Path $filePath) { Remove-Item $filePath -Force }

        Commit-ManagerChanges
        Refresh-UI
        $statusLabel.Text = "Restored default 2x2 icon preview for '$($folder.name)'."
    })

    $customIconButton.Add_Click({
        if ([string]::IsNullOrEmpty($script:selectedFolderId) -or $grid.SelectedItems.Count -eq 0) { return }
        $appId = [string]$grid.SelectedItems[0].Tag
        $folder = @($Data.Value.folders | Where-Object { [string]$_.id -eq $script:selectedFolderId })[0]
        $app = @($folder.shortcuts | Where-Object { [string]$_.id -eq $appId })[0]
        if (!$app) { return }
        $dlg = New-Object Windows.Forms.OpenFileDialog
        $dlg.Title = "Choose Custom Icon"
        $dlg.Filter = "Images (*.png;*.ico;*.jpg;*.bmp)|*.png;*.ico;*.jpg;*.bmp"
        if ($dlg.ShowDialog() -eq "OK") {
            $customName = "custom_" + [Guid]::NewGuid().ToString("N") + ".png"
            $img = Load-UnlockedImage $dlg.FileName
            $bmp = New-Object Drawing.Bitmap($img)
            $bmp.Save((Join-Path $IconDir $customName), [Drawing.Imaging.ImageFormat]::Png)
            $bmp.Dispose(); $img.Dispose()
            $app.icon = $customName
            Commit-ManagerChanges
            Refresh-UI
            $statusLabel.Text = "Updated icon for '$($app.name)'."
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
            $script:selectedFolderId = ""
        }

        Commit-ManagerChanges
        Refresh-UI
        $statusLabel.Text = "Deleted folder '$($folder.name)'."
    })

    # --- UNIFIED DRAG & DROP (REORDER SHORTCUTS + DROP FILES FROM EXPLORER) ---
    $form.AllowDrop = $true
    $grid.AllowDrop = $true
    $folderList.AllowDrop = $true

    $grid.Add_ItemDrag({
        param($sender, $e)
        if (![string]::IsNullOrEmpty($script:selectedFolderId)) {
            [void]$grid.DoDragDrop($e.Item, [Windows.Forms.DragDropEffects]::Move)
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
                $list = New-Object System.Collections.ArrayList
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
            $paths = $e.Data.GetData([Windows.Forms.DataFormats]::FileDrop)
            foreach ($path in $paths) {
                if (Test-Path $path) {
                    $defaultName = [IO.Path]::GetFileNameWithoutExtension($path)
                    $iconFile = "app_" + [Guid]::NewGuid().ToString("N") + ".png"
                    Extract-Icon $path (Join-Path $IconDir $iconFile)
                    $newApp = [pscustomobject]@{ id = [Guid]::NewGuid().ToString("N"); name = $defaultName; path = $path; icon = $iconFile }
                    $folder.shortcuts = @($folder.shortcuts) + @($newApp)
                }
            }
            script:Commit-ManagerChanges
            script:Refresh-UI
            $statusLabel.Text = "Added dropped shortcut(s) to '$($folder.name)'."
        }
    }

    $folderListDragDropHandler = {
        param($sender, $e)
        if ($e.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) {
            $paths = $e.Data.GetData([Windows.Forms.DataFormats]::FileDrop)
            $pt = $folderList.PointToClient((New-Object Drawing.Point($e.X, $e.Y)))
            $index = $folderList.IndexFromPoint($pt)
            if ($index -ge 0) {
                $foldersArr = @($Data.Value.folders)
                $folder = $foldersArr[$index]
                if ($folder) {
                    foreach ($path in $paths) {
                        if (Test-Path $path) {
                            $defaultName = [IO.Path]::GetFileNameWithoutExtension($path)
                            $iconFile = "app_" + [Guid]::NewGuid().ToString("N") + ".png"
                            Extract-Icon $path (Join-Path $IconDir $iconFile)
                            $newApp = [pscustomobject]@{ id = [Guid]::NewGuid().ToString("N"); name = $defaultName; path = $path; icon = $iconFile }
                            $folder.shortcuts = @($folder.shortcuts) + @($newApp)
                        }
                    }
                    script:Commit-ManagerChanges
                    script:Refresh-UI
                    $statusLabel.Text = "Added dropped shortcut(s) to '$($folder.name)'."
                }
            }
        }
    }

    $form.Add_DragEnter($fileDragEnterHandler)
    $folderList.Add_DragEnter($fileDragEnterHandler)
    $grid.Add_DragEnter($gridDragEnterHandler)

    $grid.Add_DragDrop($gridDragDropHandler)
    $folderList.Add_DragDrop($folderListDragDropHandler)

    Refresh-UI
    $form.Add_Shown({
        $form.Activate()
        $form.BringToFront()
    })
    [void]$form.ShowDialog()
    $form.Dispose()
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
    return $data
}

function Save-Data($Data) {
    $json = $Data | ConvertTo-Json -Depth 20
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($DataFile, $json, $utf8)
}

function Extract-Icon([string]$Path, [string]$Destination) {
    $candidate = $Path
    $iconIndex = 0
    try {
        $ext = [IO.Path]::GetExtension($Path).ToLowerInvariant()
        if ($ext -eq ".lnk") {
            $shell = New-Object -ComObject WScript.Shell
            $shortcut = $shell.CreateShortcut($Path)
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
        $extracted = [IconExtractor]::ExtractIconEx($candidate, $iconIndex, $large, $small, 1)
        if ($extracted -gt 0 -and $large[0] -ne [IntPtr]::Zero) {
            $ico = [Drawing.Icon]::FromHandle($large[0])
            $bmp = $ico.ToBitmap()
            $bmp.Save($Destination, [Drawing.Imaging.ImageFormat]::Png)
            $bmp.Dispose()
            [void][IconExtractor]::DestroyIcon($large[0])
            if ($small[0] -ne [IntPtr]::Zero) { [void][IconExtractor]::DestroyIcon($small[0]) }
            return
        }

        $ico = [Drawing.Icon]::ExtractAssociatedIcon($candidate)
        if (!$ico) { $ico = [Drawing.SystemIcons]::Application }
        $bmp = $ico.ToBitmap()
        $bmp.Save($Destination, [Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
        if ($ico -ne [Drawing.SystemIcons]::Application) { $ico.Dispose() }
    } catch {
        $fallback = [Drawing.SystemIcons]::Application
        $bmp = $fallback.ToBitmap()
        $bmp.Save($Destination, [Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
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
    $folders = @($Data.folders)
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    if (!(Test-Path $FolderTemplate)) {
        throw "Missing shared folder template: $FolderTemplate"
    }
    if (!(Test-Path $FolderRoot)) {
        New-Item -ItemType Directory -Path $FolderRoot -Force | Out-Null
    }

    # Read existing WindowX / WindowY positions without deleting active directories
    $existingPos = @{}
    Get-ChildItem -LiteralPath $FolderRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $iniFile = Join-Path $_.FullName "Folder.ini"
        if (Test-Path $iniFile) {
            $rawIni = Get-Content -LiteralPath $iniFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
            $wx = $null; $wy = $null
            if ($rawIni -match '(?m)^WindowX=(-?\d+)') { $wx = $matches[1] }
            if ($rawIni -match '(?m)^WindowY=(-?\d+)') { $wy = $matches[1] }
            if ($null -ne $wx -and $null -ne $wy) {
                $existingPos[$_.Name] = @{ X = $wx; Y = $wy }
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

    # Only delete directories for folders that were removed from Data.json
    Get-ChildItem -LiteralPath $FolderRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.Name -notin $validNames) {
            Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    for ($i=0; $i -lt $folders.Count; $i++) {
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

        $apps = @($folder.shortcuts)

        # Read configured column count (clamped to 3, 4, or 5)
        $appCols = if ($Data.PSObject.Properties['gridColumns'] -and $null -ne $Data.gridColumns) { [int]$Data.gridColumns } else { 4 }
        if ($appCols -notin @(3, 4, 5)) { $appCols = 4 }

        # Read spacing density preset
        $density = if ($Data.PSObject.Properties['gridDensity'] -and $Data.gridDensity) { [string]$Data.gridDensity } else { "Standard" }
        if ($density -eq "Compact") {
            $cellW = 84; $cellH = 82; $padX = 12; $padY = 42
            $iconSize = 34; $labelOffset = 38; $labelH = 36; $bottomPad = 12
        } else {
            $cellW = 104; $cellH = 98; $padX = 16; $padY = 48
            $iconSize = 40; $labelOffset = 45; $labelH = 44; $bottomPad = 16
        }

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
        $folderLines.Add("ImageAlpha=#PreviewAlpha#")
        $folderLines.Add("")

        # In Folder.ini, check if this folder has a custom closed overlay
        $folderIcon = ""
        if ($folder.PSObject.Properties['icon'] -and !([string]::IsNullOrEmpty($folder.icon))) {
            $folderIcon = [string]$folder.icon
        }

        # Replace existing mini-icon previews & generate conditional visual previews
        if (![string]::IsNullOrEmpty($folderIcon) -and (Test-Path (Join-Path $IconDir $folderIcon))) {
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
            # Run the 2x2 mini icon preview generator loop:
            $previewCount = [Math]::Min(4, $apps.Count)
            for ($p=0; $p -lt $previewCount; $p++) {
                $pApp = $apps[$p]
                $pCol = $p % 2
                $pRow = [Math]::Floor($p / 2)
                $px = 38 + ($pCol * 20)
                $py = 24 + ($pRow * 20)
                $pIcon = [string]$pApp.icon
                if (!$pIcon -or !(Test-Path (Join-Path $IconDir $pIcon))) { $pIcon = "app_default.png" }

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
            $folderLines.Add("X=((#PanelX# + #AnimShiftX# + (16 * #AnimScale#)) * #IsOpen#)")
            $folderLines.Add("Y=((#PanelY# + #AnimShiftY# + (50 * #AnimScale#)) * #IsOpen#)")
            $folderLines.Add("W=(($panelW - 32) * #AnimScale# * #IsOpen#)")
            $folderLines.Add("H=(24 * #AnimScale# * #IsOpen#)")
            $folderLines.Add("Text=No shortcuts yet.")
            $folderLines.Add("FontFace=Segoe UI")
            $folderLines.Add("FontSize=10")
            $folderLines.Add("FontColor=175,185,205,#AnimAlpha#")
            $folderLines.Add("AntiAlias=1")
            $folderLines.Add("DynamicVariables=1")
            $folderLines.Add("Hidden=1")
            $folderLines.Add("")
        }

        for ($j=0; $j -lt $apps.Count; $j++) {
            $app = $apps[$j]
            $col = $j % $appCols
            $row = [Math]::Floor($j / $appCols)

            $relIconX = $padX + ($col * $cellW) + [Math]::Floor($cellW / 2) - [Math]::Floor($iconSize / 2)
            $relCenterX = $padX + ($col * $cellW) + [Math]::Floor($cellW / 2)
            $relIconY = $padY + ($row * $cellH)
            $relLabelY = $relIconY + $labelOffset

            # Match HoverHighlight / SelectionHighlight bounds from FolderPopup.lua
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
            if (!$iconName -or !(Test-Path (Join-Path $IconDir $iconName))) { $iconName = "app_default.png" }
            $path = Escape-Ini ([string]$app.path)

            $folderLines.Add("[AppIcon_${j}]")
            $folderLines.Add("Meter=Image")
            $folderLines.Add("Group=PanelContent")
            $folderLines.Add("ImageName=#ROOTCONFIGPATH#Icons\$iconName")
            $folderLines.Add("X=((#PanelX# + #AnimShiftX# + ($relIconX * #AnimScale#)) * #IsOpen#)")
            $folderLines.Add("Y=((#PanelY# + #AnimShiftY# + ($relIconY * #AnimScale#)) * #IsOpen#)")
            $folderLines.Add("W=($iconSize * #AnimScale# * #IsOpen#)")
            $folderLines.Add("H=($iconSize * #AnimScale# * #IsOpen#)")
            $folderLines.Add("ImageAlpha=#AnimAlpha#")
            $folderLines.Add("PreserveAspectRatio=1")
            $folderLines.Add("DynamicVariables=1")
            $folderLines.Add("Hidden=1")
            $folderLines.Add("")

            $folderLines.Add("[AppLabel_${j}]")
            $folderLines.Add("Meter=String")
            $folderLines.Add("Group=PanelContent")
            $folderLines.Add("X=((#PanelX# + #AnimShiftX# + ($relCenterX * #AnimScale#)) * #IsOpen#)")
            $folderLines.Add("Y=((#PanelY# + #AnimShiftY# + ($relLabelY * #AnimScale#)) * #IsOpen#)")
            $folderLines.Add("W=(($cellW - 10) * #AnimScale# * #IsOpen#)")
            $folderLines.Add("H=($labelH * #AnimScale# * #IsOpen#)")
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
            $folderLines.Add("")

            # Full-tile invisible hitbox placed on top of icon + label to prevent hover flicker
            $folderLines.Add("[AppHitbox_${j}]")
            $folderLines.Add("Meter=Image")
            $folderLines.Add("Group=PanelContent")
            $folderLines.Add("SolidColor=0,0,0,1")
            $folderLines.Add("X=((#PanelX# + #AnimShiftX# + ($relBoxX * #AnimScale#)) * #IsOpen#)")
            $folderLines.Add("Y=((#PanelY# + #AnimShiftY# + ($relBoxY * #AnimScale#)) * #IsOpen#)")
            $folderLines.Add("W=($boxW * #AnimScale# * #IsOpen#)")
            $folderLines.Add("H=($boxH * #AnimScale# * #IsOpen#)")
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
        [IO.File]::WriteAllLines($iniTarget, $folderLines, $utf8)
    }
}

function Refresh-Skin {
    if (Test-Path $RainmeterExe) {
        $data = Load-Data
        $skinName = Split-Path -Leaf $Root
        $folderNames = @(Get-FolderDirectoryNames $data.folders)

        # 1. Instantly close any open/closing popups so shifted coordinates are restored first
        foreach ($folderName in $folderNames) {
            $cfg = "$skinName\Folders\$folderName"
            Start-Process -FilePath $RainmeterExe -ArgumentList "!CommandMeasure MeasureToggle `"ClosePanelInstant()`" `"$cfg`"" -WindowStyle Hidden
        }
        Start-Sleep -Milliseconds 60

        # 2. Refresh each folder skin from the updated Folder.ini and keep it draggable
        foreach ($folderName in $folderNames) {
            $iniPath = Join-Path $FolderRoot "$folderName\Folder.ini"
            if (Test-Path $iniPath) {
                $cfg = "$skinName\Folders\$folderName"
                Start-Process -FilePath $RainmeterExe -ArgumentList "!ActivateConfig `"$cfg`" `"Folder.ini`"" -WindowStyle Hidden
                Start-Sleep -Milliseconds 25
                Start-Process -FilePath $RainmeterExe -ArgumentList "!Refresh `"$cfg`"" -WindowStyle Hidden
                Start-Process -FilePath $RainmeterExe -ArgumentList "!Draggable 1 `"$cfg`"" -WindowStyle Hidden
            }
        }
    }
}

function Sync-FolderSkins {
    if (!(Test-Path $RainmeterExe)) { return }
    $stateFile = Join-Path $Resource "FolderState.txt"
    $previous = @()
    if (Test-Path $stateFile) {
        $previous = @(Get-Content -LiteralPath $stateFile -Encoding UTF8 | Where-Object { $_ })
    }
    $data = Load-Data
    $skinName = Split-Path -Leaf $Root
    $current = @(Get-FolderDirectoryNames $data.folders)
    foreach ($folderName in ($previous | Where-Object { $_ -notin $current })) {
        Start-Process -FilePath $RainmeterExe -ArgumentList "!DeactivateConfig `"$skinName\Folders\$folderName`"" -WindowStyle Hidden
    }
    foreach ($folderName in $current) {
        Start-Process -FilePath $RainmeterExe -ArgumentList "!ActivateConfig `"$skinName\Folders\$folderName`" Folder.ini" -WindowStyle Hidden
        Start-Sleep -Milliseconds 40
    }
    [IO.File]::WriteAllLines($stateFile, $current, (New-Object System.Text.UTF8Encoding($false)))
}

function Get-Folder($Data) {
    $labels = @($Data.folders | ForEach-Object { [string]$_.name })
    $chosen = Select-Item "Choose folder" $labels
    if ($null -eq $chosen) { return $null }
    return @($Data.folders | Where-Object { $_.name -eq $chosen })[0]
}

$data = Load-Data
switch ($Action) {
    "LoadFolders" { Sync-FolderSkins; exit 0 }
    "Manage" { Show-FolderManager ([ref]$data); exit 0 }
    "AddFolder" {
        $name = Show-TextPrompt "Create folder" "Enter a folder name:"
        if ($name) {
            if (@($data.folders | Where-Object { $_.name -eq $name }).Count -gt 0) {
                [Windows.Forms.MessageBox]::Show("A folder with that name already exists.") | Out-Null
            } else {
                $id = "f_" + [Guid]::NewGuid().ToString("N").Substring(0,8)
                $data.folders = @($data.folders) + @(@{id=$id;name=$name;shortcuts=@()})
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
                    $entry = @{id=[Guid]::NewGuid().ToString("N");name=$name;path=$path;icon=$iconFile}
                    $folder.shortcuts = @($folder.shortcuts) + @($entry)
                    if ([Windows.Forms.MessageBox]::Show("Use a custom PNG/ICO icon instead?","Custom icon","YesNo","Question") -eq "Yes") {
                        $iconDialog = New-Object Windows.Forms.OpenFileDialog
                        $iconDialog.Title = "Choose a custom icon"
                        $iconDialog.Filter = "Icon files (*.png;*.ico;*.jpg;*.bmp)|*.png;*.ico;*.jpg;*.bmp|All files (*.*)|*.*"
                        if ($iconDialog.ShowDialog() -eq "OK") {
                            $customName = "custom_" + [Guid]::NewGuid().ToString("N") + ".png"
                            $img = [Drawing.Image]::FromFile($iconDialog.FileName)
                            $bmp = New-Object Drawing.Bitmap($img)
                            $bmp.Save((Join-Path $IconDir $customName),[Drawing.Imaging.ImageFormat]::Png)
                            $bmp.Dispose(); $img.Dispose()
                            $entry.icon = $customName
                        }
                    }
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
                $dialog.Title = "Choose a custom icon"
                $dialog.Filter = "Image/icon files (*.png;*.ico;*.jpg;*.bmp)|*.png;*.ico;*.jpg;*.bmp|All files (*.*)|*.*"
                if ($dialog.ShowDialog() -eq "OK") {
                    $customName = "custom_" + [Guid]::NewGuid().ToString("N") + ".png"
                    $img = [Drawing.Image]::FromFile($dialog.FileName)
                    $bmp = New-Object Drawing.Bitmap($img)
                    $bmp.Save((Join-Path $IconDir $customName),[Drawing.Imaging.ImageFormat]::Png)
                    $bmp.Dispose(); $img.Dispose()
                    $app.icon = $customName
                }
            }
        }
    }
    "SetAnimation" {
        $data.animation = $AnimStyle
        Save-Data $data
        Write-Launcher $data
        Refresh-Skin
        exit 0
    }
    "ResetLayout" { }
    "Initialize" {
        foreach ($f in @($data.folders)) {
            foreach ($s in @($f.shortcuts)) {
                if ($s.icon -like "app_*" -and (Test-Path $s.path)) {
                    Extract-Icon $s.path (Join-Path $IconDir $s.icon)
                }
            }
        }
    }
}

if ($Action -eq "LoadFolders") {
    exit 0
}

Save-Data $data
Write-Launcher $data
Refresh-Skin
