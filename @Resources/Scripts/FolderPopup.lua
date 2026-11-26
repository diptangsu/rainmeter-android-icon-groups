local OPEN_DURATION = 0.16
local CLOSE_DURATION = 0.12

function Initialize()
    isOpen = false
    animState = "idle"
    animStartTime = 0
    animStartProgress = 0
    animProgress = 0
    openLeft = false
    openUp = false
    selectedIdx = -1

    savedOrigX = nil
    savedOrigY = nil
    didMove = false

    cachedStyle = "ExpandCollapse"
    cachedPanelW = 448
    cachedPanelH = 146

    lastScale = -1
    lastAlpha = -1
    lastShiftX = -9999
    lastShiftY = -9999

    SKIN:Bang('[!KeepOnScreen 0][!Draggable 1][!SetOption MeasureToggle UpdateDivider -1][!UpdateMeasure MeasureToggle]')
end

function TogglePanel()
    if isOpen and animState ~= "closing" then
        ClosePanel()
    else
        OpenPanel()
    end
end

local function GetGridMetrics()
    local panelW = tonumber(SKIN:GetVariable('PanelWidth')) or 448
    if panelW >= 440 then
        return panelW, 104, 98, 16, 48, 45
    end
    return panelW, 84, 76, 14, 48, 44
end

function RestoreIcon(idx)
    if idx == nil or idx < 0 then return end
    local col = idx % 4
    local row = math.floor(idx / 4)
    local _, cellW, cellH, padX, padY, labelOffset = GetGridMetrics()

    local relIconX = padX + (col * cellW) + math.floor(cellW / 2) - 20
    local relIconY = padY + (row * cellH)
    local relLabelY = relIconY + labelOffset

    local iconName = 'AppIcon_' .. idx
    local labelName = 'AppLabel_' .. idx

    SKIN:Bang(
        '[!SetOption ' .. iconName .. ' X "(([#PanelX] + [#AnimShiftX] + (' .. relIconX .. ' * [#AnimScale])) * [#IsOpen])"]' ..
        '[!SetOption ' .. iconName .. ' Y "(([#PanelY] + [#AnimShiftY] + (' .. relIconY .. ' * [#AnimScale])) * [#IsOpen])"]' ..
        '[!SetOption ' .. iconName .. ' W "(40 * [#AnimScale] * [#IsOpen])"]' ..
        '[!SetOption ' .. iconName .. ' H "(40 * [#AnimScale] * [#IsOpen])"]' ..
        '[!SetOption ' .. labelName .. ' Y "(([#PanelY] + [#AnimShiftY] + (' .. relLabelY .. ' * [#AnimScale])) * [#IsOpen])"]' ..
        '[!SetOption ' .. labelName .. ' FontWeight "400"]' ..
        '[!UpdateMeter ' .. iconName .. '][!UpdateMeter ' .. labelName .. ']'
    )
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
    local col = idx % 4
    local row = math.floor(idx / 4)
    local panelW, cellW, cellH, padX, padY = GetGridMetrics()

    local baseIconX = padX + (col * cellW) + math.floor(cellW / 2) - 20
    local baseIconY = padY + (row * cellH)
    local expIconX = baseIconX - 3
    local expIconY = baseIconY - 3
    local expLabelY = baseIconY + 48

    local iconName = 'AppIcon_' .. idx
    local labelName = 'AppLabel_' .. idx

    local labelMeter = SKIN:GetMeter(labelName)
    local selW = cellW - 6
    local selH = (panelW >= 440) and 88 or 72
    if labelMeter and panelW >= 440 then
        local textLen = #(labelMeter:GetOption('Text') or '')
        if textLen <= 13 then
            selH = 74
        elseif textLen <= 26 then
            selH = 88
        else
            selH = 96
        end
    end

    local relBoxX = padX + (col * cellW) + 3
    local relBoxY = baseIconY - 6

    SKIN:Bang(
        '[!SetOption ' .. iconName .. ' X "(([#PanelX] + [#AnimShiftX] + (' .. expIconX .. ' * [#AnimScale])) * [#IsOpen])"]' ..
        '[!SetOption ' .. iconName .. ' Y "(([#PanelY] + [#AnimShiftY] + (' .. expIconY .. ' * [#AnimScale])) * [#IsOpen])"]' ..
        '[!SetOption ' .. iconName .. ' W "(46 * [#AnimScale] * [#IsOpen])"]' ..
        '[!SetOption ' .. iconName .. ' H "(46 * [#AnimScale] * [#IsOpen])"]' ..
        '[!SetOption ' .. labelName .. ' Y "(([#PanelY] + [#AnimShiftY] + (' .. expLabelY .. ' * [#AnimScale])) * [#IsOpen])"]' ..
        '[!SetOption ' .. labelName .. ' FontWeight "600"]' ..
        '[!SetVariable SelW ' .. selW .. ']' ..
        '[!SetVariable SelH ' .. selH .. ']' ..
        '[!SetOption SelectionHighlight X "(([#PanelX] + [#AnimShiftX] + (' .. relBoxX .. ' * [#AnimScale])) * [#IsOpen])"]' ..
        '[!SetOption SelectionHighlight Y "(([#PanelY] + [#AnimShiftY] + (' .. relBoxY .. ' * [#AnimScale])) * [#IsOpen])"]' ..
        '[!ShowMeter SelectionHighlight]' ..
        '[!UpdateMeter ' .. iconName .. '][!UpdateMeter ' .. labelName .. '][!UpdateMeter SelectionHighlight][!Redraw]'
    )
end

function ClearSelection()
    if selectedIdx >= 0 then
        RestoreIcon(selectedIdx)
        selectedIdx = -1
    end
    SKIN:Bang('[!HideMeter SelectionHighlight][!UpdateMeter SelectionHighlight][!Redraw]')
end

function ApplyAnimFrame(p, skipRedraw)
    local style = cachedStyle
    local inv = 1 - p
    local ease = 1 - (inv * inv * inv) -- Faster than math.pow(1 - p, 3)

    local scale = 1
    local alpha = math.floor(255 * ease + 0.5)
    local shiftX = 0
    local shiftY = 0

    if style == 'ExpandCollapse' then
        scale = 0.20 + (0.80 * ease)
        shiftX = openLeft and math.floor((1 - scale) * (cachedPanelW - 38)) or math.floor((1 - scale) * 20)
        shiftY = openUp and math.floor((1 - scale) * cachedPanelH) or math.floor(-(1 - scale) * 28)
    elseif style == 'ElasticBounce' then
        local pm1 = p - 1
        local backEase = 1 + 3.6 * (pm1 * pm1 * pm1) + 2.6 * (pm1 * pm1)
        scale = 0.20 + (0.80 * backEase)
        if scale < 0.15 then scale = 0.15 end
        local a = p * 1.8
        alpha = (a >= 1) and 255 or math.floor(255 * a + 0.5)
        shiftX = openLeft and math.floor((1 - scale) * (cachedPanelW - 38)) or math.floor((1 - scale) * 20)
        shiftY = openUp and math.floor((1 - scale) * cachedPanelH) or math.floor(-(1 - scale) * 28)
    elseif style == 'Slide' then
        local dist = math.floor((1 - ease) * 75)
        shiftX = openLeft and dist or -math.floor(dist * 0.35)
        shiftY = openUp and dist or -dist
    elseif style == 'Fade' then
        alpha = math.floor(255 * p + 0.5)
    else -- 'None'
        alpha = (p >= 0.5) and 255 or 0
    end

    -- Clamp alpha and round scale to 3 decimals to avoid micro-updates
    if alpha < 0 then alpha = 0 elseif alpha > 255 then alpha = 255 end
    scale = math.floor(scale * 1000 + 0.5) / 1000

    local bangs = {}
    if scale ~= lastScale then
        lastScale = scale
        bangs[#bangs + 1] = '[!SetVariable AnimScale ' .. scale .. ']'
    end
    if alpha ~= lastAlpha then
        lastAlpha = alpha
        bangs[#bangs + 1] = '[!SetVariable AnimAlpha ' .. alpha .. ']'
    end
    if shiftX ~= lastShiftX then
        lastShiftX = shiftX
        bangs[#bangs + 1] = '[!SetVariable AnimShiftX ' .. shiftX .. ']'
    end
    if shiftY ~= lastShiftY then
        lastShiftY = shiftY
        bangs[#bangs + 1] = '[!SetVariable AnimShiftY ' .. shiftY .. ']'
    end

    if #bangs > 0 then
        if not skipRedraw then
            bangs[#bangs + 1] = '[!UpdateMeterGroup PanelContent][!Redraw]'
        end
        SKIN:Bang(table.concat(bangs))
    end
end

function Update()
    if animState == "idle" then return end

    local elapsed = os.clock() - animStartTime
    if animState == "opening" then
        local p = animStartProgress + (elapsed / OPEN_DURATION)
        if p >= 1 then
            animProgress = 1
            animState = "idle"
            ApplyAnimFrame(1, false)
            SKIN:Bang('[!SetOption MeasureToggle UpdateDivider -1][!UpdateMeasure MeasureToggle]')
            return
        end
        animProgress = p
        ApplyAnimFrame(p, false)
    elseif animState == "closing" then
        local p = animStartProgress - (elapsed / CLOSE_DURATION)
        if p <= 0 then
            animProgress = 0
            animState = "idle"
            FinishClose()
            return
        end
        animProgress = p
        ApplyAnimFrame(p, false)
    end
end

function OpenPanel()
    if isOpen and animState ~= "closing" then return end
    if selectedIdx >= 0 then
        RestoreIcon(selectedIdx)
        selectedIdx = -1
    end

    cachedStyle = (SKIN:GetVariable('AnimStyle') or 'ExpandCollapse'):gsub('%s+', '')
    cachedPanelW = tonumber(SKIN:GetVariable('PanelWidth')) or 448
    cachedPanelH = tonumber(SKIN:GetVariable('PanelHeight')) or 146

    local skinX = tonumber(SKIN:ReplaceVariables('#CURRENTCONFIGX#'))
    local skinY = tonumber(SKIN:ReplaceVariables('#CURRENTCONFIGY#'))
    local workX = tonumber(SKIN:ReplaceVariables('#WORKAREAX#')) or 0
    local workY = tonumber(SKIN:ReplaceVariables('#WORKAREAY#')) or 0
    local workW = tonumber(SKIN:ReplaceVariables('#WORKAREAWIDTH#')) or 1920
    local workH = tonumber(SKIN:ReplaceVariables('#WORKAREAHEIGHT#')) or 1080

    local rightEdge = workX + workW
    local bottomEdge = workY + workH

    if not isOpen then
        savedOrigX = skinX
        savedOrigY = skinY
        didMove = false
    end

    isOpen = true
    local origX = savedOrigX
    local savedOrigY = savedOrigY
    local newSkinX = savedOrigX
    local newSkinY = savedOrigY
    local iconOffsetX = 0
    local iconOffsetY = 0
    local panelX = 18
    local panelY = 104

    openLeft = false
    openUp = false

    -- Only shift if live coordinates were read and the popup overflows the current work area
    if savedOrigX ~= nil and savedOrigY ~= nil then
        if savedOrigX >= workX and savedOrigX <= rightEdge and (savedOrigX + 18 + cachedPanelW) > (rightEdge - 12) then
            openLeft = true
            local shiftLeft = cachedPanelW - 76
            newSkinX = savedOrigX - shiftLeft
            iconOffsetX = shiftLeft
            panelX = 18
        end

        if savedOrigY >= workY and savedOrigY <= bottomEdge and (savedOrigY + 104 + cachedPanelH) > (bottomEdge - 12) then
            openUp = true
            local shiftUp = cachedPanelH + 12
            newSkinY = savedOrigY - shiftUp
            iconOffsetY = shiftUp
            panelY = 10
        end
    end

    local bangs = {
        '[!SetVariable IsOpen 1]' ..
        '[!KeepOnScreen 0][!Draggable 0]' ..
        '[!SetVariable IconOffsetX ' .. iconOffsetX .. ']' ..
        '[!SetVariable IconOffsetY ' .. iconOffsetY .. ']' ..
        '[!SetVariable PanelX ' .. panelX .. ']' ..
        '[!SetVariable PanelY ' .. panelY .. ']'
    }

    if newSkinX ~= nil and newSkinY ~= nil and (newSkinX ~= skinX or newSkinY ~= skinY) then
        didMove = true
        bangs[#bangs + 1] = '[!Move ' .. newSkinX .. ' ' .. newSkinY .. ']'
    end

    bangs[#bangs + 1] = '[!ShowMeterGroup PanelContent][!HideMeter SelectionHighlight]'

    lastScale, lastAlpha, lastShiftX, lastShiftY = -1, -1, -9999, -9999

    if cachedStyle == 'None' then
        animState = "idle"
        animProgress = 1
        SKIN:Bang(table.concat(bangs))
        ApplyAnimFrame(1, true)
        SKIN:Bang('[!SetOption MeasureToggle UpdateDivider -1][!UpdateMeasure MeasureToggle][!UpdateMeter *][!Redraw]')
    else
        animState = "opening"
        animStartProgress = (animProgress > 0 and animProgress < 1) and animProgress or 0.12
        animProgress = animStartProgress
        animStartTime = os.clock()
        SKIN:Bang(table.concat(bangs))
        ApplyAnimFrame(animProgress, true)
        SKIN:Bang('[!SetOption MeasureToggle UpdateDivider 1][!UpdateMeasure MeasureToggle][!UpdateMeter *][!Redraw]')
    end
end

function ClosePanel()
    if not isOpen or animState == "closing" then return end
    if selectedIdx >= 0 then
        RestoreIcon(selectedIdx)
        selectedIdx = -1
    end

    cachedStyle = (SKIN:GetVariable('AnimStyle') or 'ExpandCollapse'):gsub('%s+', '')
    cachedPanelW = tonumber(SKIN:GetVariable('PanelWidth')) or 448
    cachedPanelH = tonumber(SKIN:GetVariable('PanelHeight')) or 146

    if cachedStyle == 'None' then
        FinishClose()
    else
        animState = "closing"
        animStartProgress = (animProgress > 0) and animProgress or 1
        animStartTime = os.clock()
        SKIN:Bang('[!HideMeter SelectionHighlight][!SetOption MeasureToggle UpdateDivider 1][!UpdateMeasure MeasureToggle]')
    end
end

function FinishClose()
    isOpen = false
    animState = "idle"
    animProgress = 0
    lastScale, lastAlpha, lastShiftX, lastShiftY = 1, 0, 0, 0

    -- Step 1: Collapse meters and shrink the dynamic window BEFORE any !Move bang
    SKIN:Bang(
        '[!SetOption MeasureToggle UpdateDivider -1][!UpdateMeasure MeasureToggle]' ..
        '[!HideMeterGroup PanelContent][!HideMeter SelectionHighlight]' ..
        '[!SetVariable IsOpen 0]' ..
        '[!SetVariable AnimScale 1][!SetVariable AnimAlpha 0]' ..
        '[!SetVariable AnimShiftX 0][!SetVariable AnimShiftY 0]' ..
        '[!SetVariable IconOffsetX 0][!SetVariable IconOffsetY 0]' ..
        '[!SetVariable PanelX 18][!SetVariable PanelY 104]' ..
        '[!KeepOnScreen 0][!UpdateMeter *]'
    )

    -- Step 2: Only move back if OpenPanel() actually shifted the window for a screen edge
    if didMove and savedOrigX ~= nil and savedOrigY ~= nil then
        SKIN:Bang('[!Move ' .. savedOrigX .. ' ' .. savedOrigY .. ']')
    end
    didMove = false

    SKIN:Bang('[!Draggable 1][!Redraw]')
end

function ClosePanelInstant()
    if selectedIdx >= 0 then
        RestoreIcon(selectedIdx)
        selectedIdx = -1
    end
    if isOpen then
        FinishClose()
    else
        SKIN:Bang('[!Draggable 1][!KeepOnScreen 0]')
    end
end