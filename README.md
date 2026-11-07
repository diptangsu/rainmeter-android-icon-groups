# Android-style Dynamic Rainmeter Launcher

A desktop-style launcher for Rainmeter, inspired by Android folders. It
organizes applications and files into movable folder skins, with a settings
panel for managing the contents.

## Features

- Create, rename, and delete launcher folders
- Add shortcuts through a native Windows file browser
- Automatically extract icons for supported applications and files
- Replace shortcut icons with PNG, ICO, JPG, or BMP images
- Drag folders independently to any desktop position
- Open folders in a popup and launch shortcuts from a grid
- Store launcher configuration locally in `Data.json`

## Requirements

- Windows
- [Rainmeter](https://www.rainmeter.net/)
- Windows PowerShell
- `.NET Framework` support for icon extraction and Windows Forms dialogs

## Installation

1. Close or exit the AndroidIconGroups skins if they are already running.
2. Copy the `AndroidIconGroups` folder into your Rainmeter skins directory,
   normally:

   ```text
   %USERPROFILE%\Documents\Rainmeter\Skins\
   ```

   If Rainmeter uses another skins directory, copy it there instead.
3. Open **Rainmeter Manage**, click **Refresh all**, and load
   `AndroidIconGroups\Settings.ini`.
4. Click **Refresh / Initialize** to create the default configuration and
   generated folder skins.
5. Load `AndroidIconGroups\Launcher.ini`.
6. Position each generated folder where desired. Rainmeter remembers the
   location of each folder skin independently.

You can leave Settings open while configuring the launcher or unload it after
your changes are complete.

## First-time configuration

The first initialization creates local folders named **Work** and **Games**.
Use **Create folder**, **Rename folder**, and **Delete folder** to build the
layout you want. Then add shortcuts with **Add shortcut (Browse)**.

When adding a shortcut, select the target file, application, or Windows
shortcut and enter the name shown in the launcher. The optional custom-icon
prompt accepts PNG, ICO, JPG, and BMP images.

## Managing shortcuts and folders

| Action | Description |
| --- | --- |
| Create folder | Add an empty folder and generate its Rainmeter skin |
| Rename folder | Change the folder display name |
| Delete folder | Remove the folder and its launcher entries |
| Add shortcut (Browse) | Choose a target and add it to a selected folder |
| Remove shortcut | Remove a launcher entry from a selected folder |
| Change shortcut icon | Replace an existing shortcut icon with a local image |
| Refresh / Initialize | Rebuild generated skins and icon files |

Rainmeter skin files and extracted icons can be regenerated from the launcher
configuration. Do not manually edit generated folder INI files unless you
intend to regenerate them afterward.

## Local files and generated files

The following files are created or updated locally by the launcher:

| Path | Purpose |
| --- | --- |
| `@Resources\Data.json` | Launcher folders, shortcut targets, names, and icon references |
| `@Resources\FolderState.txt` | Last-known generated folder state |
| `Folders\<name>\Folder.ini` | Generated Rainmeter skin for each folder |
| `@Resources\Icons\app_*.png` | Automatically extracted shortcut icons |
| `@Resources\Icons\custom_*.png` | Icons imported through the custom-icon controls |

Back up `@Resources\Data.json` before moving the skin to another computer or
restoring an older copy. Shortcut paths are local Windows paths and may need
to be re-added if the target location differs.

## Development

The core files are:

- `Settings.ini` - settings panel
- `Launcher.ini` - folder launcher refresh entry point
- `@Resources\Scripts\FolderManager.ps1` - configuration and skin generation
- `@Resources\Scripts\LoadFolders.lua` - Rainmeter folder-loading behavior
- `@Resources\FolderTemplate.inc` - shared generated-folder template

Generated configuration, state, and extracted/custom icon files are ignored
by Git. Static artwork in `@Resources\Icons` remains included.

## Notes and limitations

- This is a launcher overlay; deleting an entry does not delete its original
  application, file, or Windows shortcut.
- Folder skins are regenerated when configuration changes.
- Icon extraction depends on Windows and the target file type. Some packaged
  applications, network targets, and unusual file formats may fall back to a
  generic icon.
- The settings actions launch Windows Forms and require a desktop session.
- Some organization-managed systems block PowerShell scripts or custom
  execution policies. In that case, the script may require an approved policy
  or a signed launcher helper.
