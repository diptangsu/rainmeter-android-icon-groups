function Initialize()
    isOpen = false
    animState = "idle" -- "idle", "opening", "closing"
    animProgress = 0
    openLeft = false
    openUp = false
    selectedIdx = -1
    SKIN:Bang('!KeepOnScreen', '0')
end

function TogglePanel()
    if isOpen and animState ~= "closing" then
        ClosePanel()
    else
        OpenPanel()
    end
end

function RestoreIcon(idx)
    if idx == nil or idx < 0 then return end
    local col = idx % 4
    local row = math.floor(idx / 4)
    local relIconX = 14 + (col * 84) + 22
    local relIconY = 48 + (row * 76)
    local relLabelY = relIconY + 44

    SKIN:Bang('!SetOption', 'AppIcon_' .. idx, 'X', '((#PanelX# + #AnimShiftX# + (' .. relIconX .. ' * #AnimScale#)) * #IsOpen#)')
    SKIN:Bang('!SetOption', 'AppIcon_' .. idx, 'Y', '((#PanelY# + #AnimShiftY# + (' .. relIconY .. ' * #AnimScale#)) * #IsOpen#)')
    SKIN:Bang('!SetOption', 'AppIcon_' .. idx, 'W', '(40 * #AnimScale# * #IsOpen#)')
    SKIN:Bang('!SetOption', 'AppIcon_' .. idx, 'H', '(40 * #AnimScale# * #IsOpen#)')
    SKIN:Bang('!SetOption', 'AppLabel_' .. idx, 'Y', '((#PanelY# + #AnimShiftY# + (' .. relLabelY .. ' * #AnimScale#)) * #IsOpen#)')
    SKIN:Bang('!SetOption', 'AppLabel_' .. idx, 'FontWeight', '400')
    SKIN:Bang('!UpdateMeter', 'AppIcon_' .. idx)
    SKIN:Bang('!UpdateMeter', 'AppLabel_' .. idx)
end

function SelectApp(idx)
    if not isOpen or animState ~= "idle" then return end
    idx = tonumber(idx) or -1
    if idx < 0 then
        ClearSelection()
        return
    end

    if selectedIdx >= 0 and selectedIdx ~= idx then
        RestoreIcon(selectedIdx)
    end

    selectedIdx = idx
    local panelX = tonumber(SKIN:GetVariable('PanelX')) or 18
    local panelY = tonumber(SKIN:GetVariable('PanelY')) or 104
    local col = idx % 4
    local row = math.floor(idx / 4)

    local expIconX = 14 + (col * 84) + 22 - 3
    local expIconY = 48 + (row * 76) - 3
    local expLabelY = 48 + (row * 76) + 46

    SKIN:Bang('!SetOption', 'AppIcon_' .. idx, 'X', '((#PanelX# + #AnimShiftX# + (' .. expIconX .. ' * #AnimScale#)) * #IsOpen#)')
    SKIN:Bang('!SetOption', 'AppIcon_' .. idx, 'Y', '((#PanelY# + #AnimShiftY# + (' .. expIconY .. ' * #AnimScale#)) * #IsOpen#)')
    SKIN:Bang('!SetOption', 'AppIcon_' .. idx, 'W', '(46 * #AnimScale# * #IsOpen#)')
    SKIN:Bang('!SetOption', 'AppIcon_' .. idx, 'H', '(46 * #AnimScale# * #IsOpen#)')
    SKIN:Bang('!SetOption', 'AppLabel_' .. idx, 'Y', '((#PanelY# + #AnimShiftY# + (' .. expLabelY .. ' * #AnimScale#)) * #IsOpen#)')
    SKIN:Bang('!SetOption', 'AppLabel_' .. idx, 'FontWeight', '600')

    local boxX = panelX + 14 + (col * 84) + 4
    local boxY = panelY + 48 + (row * 76) - 4

    SKIN:Bang('!SetOption', 'SelectionHighlight', 'X', boxX)
    SKIN:Bang('!SetOption', 'SelectionHighlight', 'Y', boxY)
    SKIN:Bang('!ShowMeter', 'SelectionHighlight')
    SKIN:Bang('!UpdateMeter', 'AppIcon_' .. idx)
    SKIN:Bang('!UpdateMeter', 'AppLabel_' .. idx)
    SKIN:Bang('!UpdateMeter', 'SelectionHighlight')
    SKIN:Bang('!Redraw')
end

function ClearSelection()
    if selectedIdx >= 0 then
        RestoreIcon(selectedIdx)
        selectedIdx = -1
    end
    SKIN:Bang('!HideMeter', 'SelectionHighlight')
    SKIN:Bang('!UpdateMeter', 'SelectionHighlight')
    SKIN:Bang('!Redraw')
end

function ApplyAnimFrame(p)
    local style = SKIN:GetVariable('AnimStyle') or 'ExpandCollapse'
    style = style:gsub('%s+', '')
    local panelW = tonumber(SKIN:GetVariable('PanelWidth')) or 364
    local panelH = tonumber(SKIN:GetVariable('PanelHeight')) or 136

    local ease = 1 - math.pow(1 - p, 3)
    local scale = 1
    local alpha = math.max(0, math.min(255, math.floor(255 * ease)))
    local shiftX = 0
    local shiftY = 0

    if style == 'ExpandCollapse' then
        scale = 0.20 + (0.80 * ease)
        shiftX = openLeft and math.floor((1 - scale) * (panelW - 38)) or math.floor((1 - scale) * 20)
        shiftY = openUp and math.floor((1 - scale) * panelH) or math.floor(-(1 - scale) * 28)
    elseif style == 'ElasticBounce' then
        -- Overshoot spring curve (peaks around 1.12x scale before settling at 1.0x)
        local c1 = 2.6
        local c3 = c1 + 1
        local backEase = 1 + c3 * math.pow(p - 1, 3) + c1 * math.pow(p - 1, 2)
        scale = math.max(0.15, 0.20 + (0.80 * backEase))
        alpha = math.max(0, math.min(255, math.floor(255 * math.min(1, p * 1.8))))
        shiftX = openLeft and math.floor((1 - scale) * (panelW - 38)) or math.floor((1 - scale) * 20)
        shiftY = openUp and math.floor((1 - scale) * panelH) or math.floor(-(1 - scale) * 28)
    elseif style == 'Slide' then
        -- Pure slide at 100% full scale (no shrinking/expanding)
        scale = 1
        local dist = math.floor((1 - ease) * 75)
        shiftX = openLeft and dist or -math.floor(dist * 0.35)
        shiftY = openUp and dist or -dist
    elseif style == 'Fade' then
        -- Pure opacity fade in place at 100% scale and 0 position shift
        scale = 1
        shiftX = 0
        shiftY = 0
        alpha = math.max(0, math.min(255, math.floor(255 * p)))
    else -- 'None'
        scale = 1
        alpha = p >= 0.5 and 255 or 0
        shiftX = 0
        shiftY = 0
    end

    SKIN:Bang('!SetVariable', 'AnimScale', scale)
    SKIN:Bang('!SetVariable', 'AnimAlpha', alpha)
    SKIN:Bang('!SetVariable', 'AnimShiftX', shiftX)
    SKIN:Bang('!SetVariable', 'AnimShiftY', shiftY)
    SKIN:Bang('!UpdateMeterGroup', 'PanelContent')
    SKIN:Bang('!Redraw')
end

function Update()
    if animState == "idle" then return end

    if animState == "opening" then
        animProgress = animProgress + 0.11
        if animProgress >= 1 then
            animProgress = 1
            animState = "idle"
            ApplyAnimFrame(1)
            SKIN:Bang('!SetOption', 'MeasureToggle', 'UpdateDivider', '60')
            SKIN:Bang('!UpdateMeasure', 'MeasureToggle')
            return
        end
        ApplyAnimFrame(animProgress)
    elseif animState == "closing" then
        animProgress = animProgress - 0.14
        if animProgress <= 0 then
            animProgress = 0
            animState = "idle"
            FinishClose()
            return
        end
        ApplyAnimFrame(animProgress)
    end
end

function OpenPanel()
    if isOpen and animState ~= "closing" then return end
    if selectedIdx >= 0 then
        RestoreIcon(selectedIdx)
        selectedIdx = -1
    end

    local style = SKIN:GetVariable('AnimStyle') or 'ExpandCollapse'
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

    if not isOpen then
        SKIN:Bang('!SetVariable', 'OrigX', skinX)
        SKIN:Bang('!SetVariable', 'OrigY', skinY)
    end

    isOpen = true
    SKIN:Bang('!SetVariable', 'IsOpen', 1)
    SKIN:Bang('!KeepOnScreen', '0')
    SKIN:Bang('!Draggable', '0')

    local origX = tonumber(SKIN:GetVariable('OrigX')) or skinX
    local origY = tonumber(SKIN:GetVariable('OrigY')) or skinY
    local newSkinX = origX
    local newSkinY = origY
    local iconOffsetX = 0
    local iconOffsetY = 0
    local panelX = 18
    local panelY = 104

    openLeft = false
    openUp = false

    if (origX + 18 + panelW) > (rightEdge - 12) then
        openLeft = true
        local shiftLeft = panelW - 76
        newSkinX = origX - shiftLeft
        iconOffsetX = shiftLeft
        panelX = 18
    end

    if (origY + 104 + panelH) > (bottomEdge - 12) then
        openUp = true
        local shiftUp = panelH + 12
        newSkinY = origY - shiftUp
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
    SKIN:Bang('!HideMeter', 'SelectionHighlight')

    if instant or style == 'None' then
        animState = "idle"
        animProgress = 1
        ApplyAnimFrame(1)
        SKIN:Bang('!SetOption', 'MeasureToggle', 'UpdateDivider', '60')
        SKIN:Bang('!UpdateMeasure', 'MeasureToggle')
    else
        animState = "opening"
        animProgress = 0.15
        ApplyAnimFrame(animProgress)
        SKIN:Bang('!SetOption', 'MeasureToggle', 'UpdateDivider', '1')
        SKIN:Bang('!UpdateMeasure', 'MeasureToggle')
    end

    SKIN:Bang('!UpdateMeter', '*')
    SKIN:Bang('!Redraw')
end

function ClosePanel()
    if not isOpen or animState == "closing" then return end
    if selectedIdx >= 0 then
        RestoreIcon(selectedIdx)
        selectedIdx = -1
    end
    SKIN:Bang('!HideMeter', 'SelectionHighlight')

    local style = SKIN:GetVariable('AnimStyle') or 'ExpandCollapse'
    if style == 'None' then
        FinishClose()
    else
        animState = "closing"
        if animProgress <= 0 then animProgress = 1 end
        SKIN:Bang('!SetOption', 'MeasureToggle', 'UpdateDivider', '1')
        SKIN:Bang('!UpdateMeasure', 'MeasureToggle')
    end
end

function FinishClose()
    isOpen = false
    animState = "idle"
    animProgress = 0

    local origX = tonumber(SKIN:GetVariable('OrigX'))
    local origY = tonumber(SKIN:GetVariable('OrigY'))

    SKIN:Bang('!SetOption', 'MeasureToggle', 'UpdateDivider', '60')
    SKIN:Bang('!HideMeterGroup', 'PanelContent')
    SKIN:Bang('!HideMeter', 'SelectionHighlight')
    SKIN:Bang('!SetVariable', 'IsOpen', 0)
    SKIN:Bang('!SetVariable', 'AnimScale', 1)
    SKIN:Bang('!SetVariable', 'AnimAlpha', 0)
    SKIN:Bang('!SetVariable', 'AnimShiftX', 0)
    SKIN:Bang('!SetVariable', 'AnimShiftY', 0)
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