function Initialize()
end

function LoadFolders()
    local configName = SKIN:GetVariable("CURRENTCONFIG")
    local skinsPath = SKIN:GetVariable("SKINSPATH")
    if configName == nil or configName == "" or skinsPath == nil or skinsPath == "" then
        return
    end

    local root = skinsPath .. configName .. "\\Folders"
    local folders = io.popen('cmd /d /c dir "' .. root .. '" /ad /b /on 2>nul')
    if folders == nil then
        return
    end

    for folderName in folders:lines() do
        if folderName:match("^F_") then
            SKIN:Bang('!ActivateConfig "' .. configName .. '\\Folders\\' .. folderName .. '" "Folder.ini"')
        end
    end

    folders:close()
end
