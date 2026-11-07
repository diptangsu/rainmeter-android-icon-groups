function Initialize()
    isOpen = false
    SKIN:Bang('!KeepOnScreen', '0')
end

function TogglePanel()
    if isOpen then
        ClosePanel()
    else
        OpenPanel()
    end
end

function OpenPanel()
    if isOpen then return end
    isOpen = true

    local skinX = tonumber(SKIN:GetVariable('CURRENTCONFIGX')) or 0
    local skinY = tonumber(SKIN:GetVariable('CURRENTCONFIGY')) or 0
    local workX = tonumber(SKIN:GetVariable('WORKAREAX')) or 0
    local workY = tonumber(SKIN:GetVariable('WORKAREAY')) or 0
    local workW = tonumber(SKIN:GetVariable('WORKAREAWIDTH')) or 1920
    local workH = tonumber(SKIN:GetVariable('WORKAREAHEIGHT')) or 1080
    local panelW = tonumber(SKIN:GetVariable('PanelWidth')) or 364
    local panelH = tonumber(SKIN:GetVariable('PanelHeight')) or 136

    local rightEdge = workX + workW
    local bottomEdge = workY + workH

    SKIN:Bang('!SetVariable', 'OrigX', skinX)
    SKIN:Bang('!SetVariable', 'OrigY', skinY)
    SKIN:Bang('!SetVariable', 'IsOpen', 1)
    SKIN:Bang('!KeepOnScreen', '0')
    SKIN:Bang('!Draggable', '0')

    local newSkinX = skinX
    local newSkinY = skinY
    local iconOffsetX = 0
    local iconOffsetY = 0
    local panelX = 18
    local panelY = 104

    -- Horizontal Check: If opening right overflows the right edge of the screen, open LEFT
    if (skinX + 18 + panelW) > (rightEdge - 12) then
        local shiftLeft = panelW - 76
        newSkinX = skinX - shiftLeft
        iconOffsetX = shiftLeft
        panelX = 18
    end

    -- Vertical Check: If opening down overflows the bottom edge of the screen, open UPWARD
    if (skinY + 104 + panelH) > (bottomEdge - 12) then
        local shiftUp = panelH + 12
        newSkinY = skinY - shiftUp
        iconOffsetY = shiftUp
        panelY = 10
    end

    SKIN:Bang('!SetVariable', 'IconOffsetX', iconOffsetX)
    SKIN:Bang('!SetVariable', 'IconOffsetY', iconOffsetY)
    SKIN:Bang('!SetVariable', 'PanelX', panelX)
    SKIN:Bang('!SetVariable', 'PanelY', panelY)

    if newSkinX ~= skinX or newSkinY ~= skinY then
        SKIN:Bang('!Move', newSkinX, newSkinY)
    end

    SKIN:Bang('!ShowMeterGroup', 'PanelContent')
    SKIN:Bang('!UpdateMeter', '*')
    SKIN:Bang('!Redraw')
end

function ClosePanel()
    if not isOpen then return end
    isOpen = false

    local origX = tonumber(SKIN:GetVariable('OrigX'))
    local origY = tonumber(SKIN:GetVariable('OrigY'))

    SKIN:Bang('!HideMeterGroup', 'PanelContent')
    SKIN:Bang('!SetVariable', 'IsOpen', 0)
    SKIN:Bang('!SetVariable', 'IconOffsetX', 0)
    SKIN:Bang('!SetVariable', 'IconOffsetY', 0)
    SKIN:Bang('!SetVariable', 'PanelX', 18)
    SKIN:Bang('!SetVariable', 'PanelY', 104)

    if origX and origY then
        SKIN:Bang('!Move', origX, origY)
    end

    SKIN:Bang('!Draggable', '1')
    SKIN:Bang('!KeepOnScreen', '0')
    SKIN:Bang('!UpdateMeter', '*')
    SKIN:Bang('!Redraw')
end