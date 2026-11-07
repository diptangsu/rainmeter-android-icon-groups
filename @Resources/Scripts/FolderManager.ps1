param(
    [ValidateSet("Initialize","LoadFolders","AddFolder","RenameFolder","DeleteFolder","AddShortcut","RemoveShortcut","SetCustomIcon","ResetLayout")]
    [string]$Action = "Initialize"
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Resource = Join-Path $Root "@Resources"
$DataFile = Join-Path $Resource "Data.json"
$IconDir = Join-Path $Resource "Icons"
$LauncherFile = Join-Path $Root "Launcher.ini"
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

function Load-Data {
    if (!(Test-Path $DataFile)) {
        $starter = @{ folders = @(
            @{ id="f_work"; name="Work"; shortcuts=@() },
            @{ id="f_games"; name="Games"; shortcuts=@() }
        )}
        $starter | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $DataFile -Encoding UTF8
    }
    $data = Get-Content -LiteralPath $DataFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -eq $data.folders) { $data = @{ folders=@() } }
    return $data
}

function Save-Data($Data) {
    $json = $Data | ConvertTo-Json -Depth 20
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($DataFile, $json, $utf8)
}

function Extract-Icon([string]$Path, [string]$Destination) {
    $candidate = $Path
    try {
        if ([IO.Path]::GetExtension($Path).ToLowerInvariant() -eq ".lnk") {
            $shell = New-Object -ComObject WScript.Shell
            $shortcut = $shell.CreateShortcut($Path)
            if ($shortcut.IconLocation) {
                $iconPath = ($shortcut.IconLocation -split ',')[0].Trim('"')
                if (Test-Path $iconPath) { $candidate = $iconPath }
            } elseif (Test-Path $shortcut.TargetPath) { $candidate = $shortcut.TargetPath }
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
    if (Test-Path $FolderRoot) {
        Get-ChildItem -LiteralPath $FolderRoot -Directory |
            ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force }
    } else {
        New-Item -ItemType Directory -Path $FolderRoot | Out-Null
    }

    $launcher = New-Object System.Collections.Generic.List[string]
    $launcher.Add("[Rainmeter]")
    $launcher.Add("Update=-1")
    $launcher.Add("AccurateText=1")
    $powershellExe = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
    $launcher.Add("OnRefreshAction=[`"$powershellExe`" -NoProfile -STA -ExecutionPolicy Bypass -File #CURRENTPATH#@Resources\Scripts\FolderManager.ps1 -Action LoadFolders]")
    $launcher.Add("")
    $launcher.Add("[Metadata]")
    $launcher.Add("Name=Android Desktop Launcher")
    $launcher.Add("Author=Custom")
    $launcher.Add("Information=Folder skin launcher")
    $launcher.Add("Version=2.1")
    $launcher.Add("")
    $launcher.Add("[FolderLoader]")
    $launcher.Add("Measure=Script")
    $launcher.Add("ScriptFile=#@#Scripts\LoadFolders.lua")
    $launcher.Add("DynamicVariables=1")
    $launcher.Add("")
    $launcher.Add("[Startup]")
    $launcher.Add("Meter=String")
    $launcher.Add("Text=")
    $launcher.Add("X=0")
    $launcher.Add("Y=0")
    $launcher.Add("W=1")
    $launcher.Add("H=1")
    $launcher.Add("Hidden=1")
    $launcher.Add("")

    for ($i=0; $i -lt $folders.Count; $i++) {
        $folder = $folders[$i]
        $folderId = [string]$folder.id
        $folderName = Get-FolderDirectoryName ([string]$folder.name)
        $folderDir = Join-Path $FolderRoot $folderName
        $suffix = 2
        while (Test-Path $folderDir) {
            $folderName = "$(Get-FolderDirectoryName ([string]$folder.name))_$suffix"
            $folderDir = Join-Path $FolderRoot $folderName
            $suffix++
        }
        New-Item -ItemType Directory -Path $folderDir | Out-Null
        $x = 36 + (($i % 5) * 124)
        $y = 18 + ([Math]::Floor($i / 5) * 100)

        $folderLines = New-Object System.Collections.Generic.List[string]
        $folderLines.Add("[Rainmeter]")
        $folderLines.Add("@Include=#@#FolderTemplate.inc")
        $folderLines.Add("Update=1000")
        $folderLines.Add("AccurateText=1")
        $folderLines.Add("DynamicWindowSize=1")
        $folderLines.Add("Draggable=1")
        $folderLines.Add("KeepPosition=1")
        $folderLines.Add("SolidColor=0,0,0,1")
        $folderLines.Add("WindowX=$x")
        $folderLines.Add("WindowY=$y")
        $folderLines.Add("")
        $folderLines.Add("[Metadata]")
        $folderLines.Add("Name=$(Escape-Ini ([string]$folder.name)) Folder")
        $folderLines.Add("Author=Custom")
        $folderLines.Add("Version=2.1")
        $folderLines.Add("")
        $folderLines.Add("[Variables]")
        $folderLines.Add("FolderID=$folderId")
        $folderLines.Add("FolderName=$(Escape-Ini ([string]$folder.name))")
        $folderLines.Add("")

        $apps = @($folder.shortcuts)
        $appCols = 4
        $cellW = 84; $cellH = 76; $padX = 14; $padY = 48
        $rows = [Math]::Max(1,[Math]::Ceiling([Math]::Max(1,$apps.Count) / $appCols))
        $panelW = (2 * $padX) + ($appCols * $cellW)
        $panelH = $padY + ($rows * $cellH) + 12
        $folderLines.Add("PanelWidth=$panelW")
        $folderLines.Add("PanelHeight=$panelH")
        $folderLines.Add("FolderPath=#CURRENTCONFIGDIR#")
        $folderLines.Add("")

        if ($apps.Count -eq 0) {
            $folderLines.Add("[PanelEmpty]")
            $folderLines.Add("Meter=String")
            $folderLines.Add("Group=PanelContent")
            $folderLines.Add("X=34")
            $folderLines.Add("Y=154")
            $folderLines.Add("W=$($panelW-32)")
            $folderLines.Add("H=24")
            $folderLines.Add("Text=No shortcuts yet.")
            $folderLines.Add("FontFace=Segoe UI")
            $folderLines.Add("FontSize=10")
            $folderLines.Add("FontColor=175,185,205,255")
            $folderLines.Add("AntiAlias=1")
            $folderLines.Add("Hidden=1")
            $folderLines.Add("")
        }

        for ($j=0; $j -lt $apps.Count; $j++) {
            $app = $apps[$j]
            $col = $j % $appCols
            $row = [Math]::Floor($j / $appCols)

            # Position relative to PanelBackground (X=18, Y=104)
            $cellStartX = 18 + $padX + ($col * $cellW)
            $cellCenterX = $cellStartX + [Math]::Floor($cellW / 2)
            $iconX = $cellCenterX - 20
            $iconY = 104 + $padY + ($row * $cellH)
            $labelY = $iconY + 44

            $appName = Escape-Ini ([string]$app.name)
            $iconName = [string]$app.icon
            if (!$iconName -or !(Test-Path (Join-Path $IconDir $iconName))) { $iconName = "app_default.png" }
            $path = Escape-Ini ([string]$app.path)

            $folderLines.Add("[AppIcon_${j}]")
            $folderLines.Add("Meter=Image")
            $folderLines.Add("Group=PanelContent")
            $folderLines.Add("ImageName=#@#Icons\$iconName")
            $folderLines.Add("X=$iconX")
            $folderLines.Add("Y=$iconY")
            $folderLines.Add("W=40")
            $folderLines.Add("H=40")
            $folderLines.Add("PreserveAspectRatio=1")
            $folderLines.Add("Hidden=1")
            $folderLines.Add('LeftMouseUpAction=["' + $path + '"]')
            $folderLines.Add("")

            $folderLines.Add("[AppLabel_${j}]")
            $folderLines.Add("Meter=String")
            $folderLines.Add("Group=PanelContent")
            $folderLines.Add("X=$cellCenterX")
            $folderLines.Add("Y=$labelY")
            $folderLines.Add("W=$($cellW - 6)")
            $folderLines.Add("H=28")
            $folderLines.Add("Text=$appName")
            $folderLines.Add("FontFace=Segoe UI")
            $folderLines.Add("FontSize=9")
            $folderLines.Add("FontColor=245,247,255,255")
            $folderLines.Add("StringAlign=Center")
            $folderLines.Add("ClipString=1")
            $folderLines.Add("AntiAlias=1")
            $folderLines.Add("Hidden=1")
            $folderLines.Add('LeftMouseUpAction=["' + $path + '"]')
            $folderLines.Add("")
        }
        [IO.File]::WriteAllLines((Join-Path $folderDir "Folder.ini"), $folderLines, $utf8)
    }
    [IO.File]::WriteAllLines($LauncherFile, $launcher, $utf8)
}

function Refresh-Skin {
    if (Test-Path $RainmeterExe) {
        $data = Load-Data
        $skinName = Split-Path -Leaf $Root
        Start-Process -FilePath $RainmeterExe -ArgumentList "!Refresh `"$skinName\Launcher`"" -WindowStyle Hidden
        foreach ($folderName in @(Get-FolderDirectoryNames $data.folders)) {
            Start-Sleep -Milliseconds 40
            Start-Process -FilePath $RainmeterExe -ArgumentList "!ActivateConfig `"$skinName\Folders\$folderName`" Folder.ini" -WindowStyle Hidden
            Start-Sleep -Milliseconds 40
            Start-Process -FilePath $RainmeterExe -ArgumentList "!RefreshConfig `"$skinName\Folders\$folderName`"" -WindowStyle Hidden
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
    "LoadFolders" { Sync-FolderSkins }
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
    "ResetLayout" { }
    "Initialize" { }
}

if ($Action -eq "LoadFolders") {
    exit 0
}

Save-Data $data
Write-Launcher $data
Refresh-Skin
