# Android-style Dynamic Rainmeter Launcher

## What it does
- Dynamic folders (create, rename, delete)
- Add shortcuts through a Windows Browse dialog
- Supports EXE, LNK, documents, URLs/files selected through the dialog, and folders only if selected through a shortcut
- Automatic icon extraction where Windows/.NET exposes an associated icon
- Optional custom icon override (PNG, ICO, JPG, BMP; converted to PNG)
- Grid-based folder contents
- Each desktop folder is an independent Rainmeter skin, so folders can be dragged and positioned separately
- Persistent data stored in `@Resources\Data.json`

## Install
1. Install Rainmeter.
2. Copy the complete `AndroidIconGroups` folder into:
   `%USERPROFILE%\Documents\Rainmeter\Skins\`
   (If your Rainmeter Skins folder is elsewhere, use that location instead.)
3. In Rainmeter Manage, click Refresh all.
4. Load `AndroidIconGroups\Settings.ini`.
5. In Settings, click **Refresh / Initialize** once. This generates one skin folder for each folder in `Data.json`.
6. Load `AndroidIconGroups\Launcher.ini`. It opens all generated folder skins.
7. Drag each folder directly to its preferred desktop position. Rainmeter stores and restores the position of every folder skin separately.
8. Keep Settings loaded when you want to manage folders, or unload it after use.

## Managing content
- Create folder: creates a new folder tile.
- Rename folder: select an existing folder and enter a new name.
- Delete folder: deletes that folder and its shortcut records (does not delete original files).
- Add shortcut: choose a folder, browse to a file/app/shortcut, give it a display name, then optionally choose a custom icon.
- Remove shortcut: choose a folder and then a shortcut.
- Change shortcut icon: choose a folder, shortcut, and custom image.

## Notes / limitations
- This is a launcher overlay; it does not physically move or manage Windows desktop shortcuts.
- Rainmeter INI files are regenerated when you make changes. Keep a backup of `@Resources\Data.json` if you customize heavily.
- Automatic icon extraction uses .NET `Icon.ExtractAssociatedIcon`; some shortcut targets, packaged apps, and unusual file types may return a generic icon. Use the custom icon override for those.
- App launch uses Rainmeter's standard `LeftMouseUpAction` shell launch syntax.
- The included default folders are empty. Add your own shortcuts in Settings.
- The settings actions invoke Windows PowerShell and Windows Forms dialogs. If your organization blocks PowerShell scripts, this skin will need an approved execution policy or a different helper.
