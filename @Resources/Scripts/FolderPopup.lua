local OPEN_DURATION = 0.16
local CLOSE_DURATION = 0.12
local HOVER_IN_DURATION = 0.09
local HOVER_OUT_DURATION = 0.13

local floor = math.floor
local ceil = math.ceil
local min = math.min
local abs = math.abs
local clock = os.clock
local concat = table.concat

function Initialize()
    isOpen = false
    animState = "idle"
    animStartTime = 0
    animStartProgress = 0
    animProgress = 0
    openLeft = false
    openUp = false
    selectedIdx = -1

    hoveredIdx = -1
    hoverAlpha = 0
    hoverTarget = 0
    hoverStartTime = 0
    hoverStartAlpha = 0
    lastHoverAlpha = -1

    savedOrigX = nil
    savedOrigY = nil
    didMove = false
    pendingRestore = false

    cachedStyle = (SKIN:GetVariable('AnimStyle') or 'ExpandCollapse'):gsub('%s+', '')
    cachedPanelW = tonumber(SKIN:GetVariable('PanelWidth')) or 448
    cachedPanelH = tonumber(SKIN:GetVariable('PanelHeight')) or 146
    cachedPanelX = 18
    cachedPanelY = 104

    -- Cache static grid layout metrics once per skin load/refresh
    cachedCols = tonumber(SKIN:GetVariable('GridCols')) or 4
    cachedCellW = tonumber(SKIN:GetVariable('CellW')) or 104
    cachedCellH = tonumber(SKIN:GetVariable('CellH')) or 98
    cachedPadX = tonumber(SKIN:GetVariable('PadX')) or 16
    cachedPadY = tonumber(SKIN:GetVariable('PadY')) or 48
    cachedIsCompact = (cachedCellW <= 90)
    cachedIconSize = cachedIsCompact and 34 or 40
    cachedLabelOffset = cachedIsCompact and 38 or 45

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

local function GetTileBoxSize(idx)
    local boxW = cachedCellW - 6
    local hitbox = SKIN:GetMeter('AppHitbox_' .. idx)
    if hitbox then
        local h = hitbox:GetH()
        if h and h > 0 then
            return boxW, h
        end
    end

    local boxH = cachedIsCompact and 72 or 88
    local labelMeter = SKIN:GetMeter('AppLabel_' .. idx)
    if labelMeter and not cachedIsCompact then
        local textLen = #(labelMeter:GetOption('Text') or '')
        if textLen <= 13 then
            boxH = 74
        elseif textLen <= 26 then
            boxH = 88
        else
            boxH = 96
        end
    end
    return boxW, boxH
end

function RestoreIcon(idx)
    if idx == nil or idx < 0 then return end
    local col = idx % cachedCols
    local row = floor(idx / cachedCols)

    local relIconX = cachedPadX + (col * cachedCellW) + floor(cachedCellW / 2) - floor(cachedIconSize / 2)
    local relIconY = cachedPadY + (row * cachedCellH)
    local relLabelY = relIconY + cachedLabelOffset

    local iconName = 'AppIcon_' .. idx
    local labelName = 'AppLabel_' .. idx

    -- Use #*Var*# so Rainmeter writes literal #Var# into the meter instead of baking current values
    SKIN:Bang(
        '[!SetOption ' .. iconName .. ' X "((#*PanelX*# + #*AnimShiftX*# + (' .. relIconX .. ' * #*AnimScale*#)) * #*IsOpen*#)"]' ..
        '[!SetOption ' .. iconName .. ' Y "((#*PanelY*# + #*AnimShiftY*# + (' .. relIconY .. ' * #*AnimScale*#)) * #*IsOpen*#)"]' ..
        '[!SetOption ' .. iconName .. ' W "(' .. cachedIconSize .. ' * #*AnimScale*# * #*IsOpen*#)"]' ..
        '[!SetOption ' .. iconName .. ' H "(' .. cachedIconSize .. ' * #*AnimScale*# * #*IsOpen*#)"]' ..
        '[!SetOption ' .. labelName .. ' Y "((#*PanelY*# + #*AnimShiftY*# + (' .. relLabelY .. ' * #*AnimScale*#)) * #*IsOpen*#)"]' ..
        '[!SetOption ' .. labelName .. ' FontWeight "400"]' ..
        '[!UpdateMeter ' .. iconName .. '][!UpdateMeter ' .. labelName .. ']'
    )
end

function ResetHover()
    hoveredIdx = -1
    hoverAlpha = 0
    hoverTarget = 0
    lastHoverAlpha = 0
    SKIN:Bang('[!SetVariable HoverAlpha 0][!HideMeter HoverHighlight][!UpdateMeter HoverHighlight]')
end

function HoverApp(idx)
    if not isOpen or animState ~= "idle" then return end
    idx = tonumber(idx) or -1
    if idx < 0 or idx == selectedIdx then
        if hoveredIdx >= 0 then UnhoverApp(hoveredIdx) end
        return
    end

    local col = idx % cachedCols
    local row = floor(idx / cachedCols)
    local baseIconY = cachedPadY + (row * cachedCellH)
    local hoverW, hoverH = GetTileBoxSize(idx)
    local relBoxX = cachedPadX + (col * cachedCellW) + 3
    local relBoxY = baseIconY - 6

    local bangs = {}
    if hoveredIdx ~= idx then
        hoveredIdx = idx
        bangs[#bangs + 1] =
            '[!SetVariable HoverX ' .. relBoxX .. ']' ..
            '[!SetVariable HoverY ' .. relBoxY .. ']' ..
            '[!SetVariable HoverW ' .. hoverW .. ']' ..
            '[!SetVariable HoverH ' .. hoverH .. ']' ..
            '[!ShowMeter HoverHighlight][!UpdateMeter HoverHighlight][!Redraw]'
    end

    hoverTarget = 1
    hoverStartAlpha = hoverAlpha
    hoverStartTime = clock()
    bangs[#bangs + 1] = '[!SetOption MeasureToggle UpdateDivider 1][!UpdateMeasure MeasureToggle]'
    SKIN:Bang(concat(bangs))
end

function UnhoverApp(idx)
    idx = tonumber(idx) or -1
    if hoveredIdx ~= idx then return end

    hoverTarget = 0
    hoverStartAlpha = hoverAlpha
    hoverStartTime = clock()
    SKIN:Bang('[!SetOption MeasureToggle UpdateDivider 1][!UpdateMeasure MeasureToggle]')
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
    local col = idx % cachedCols
    local row = floor(idx / cachedCols)

    local baseIconX = cachedPadX + (col * cachedCellW) + floor(cachedCellW / 2) - floor(cachedIconSize / 2)
    local baseIconY = cachedPadY + (row * cachedCellH)
    local expIconX = baseIconX - 3
    local expIconY = baseIconY - 3
    local expIconSize = cachedIconSize + 6
    local expLabelY = baseIconY + cachedLabelOffset + 3

    local iconName = 'AppIcon_' .. idx
    local labelName = 'AppLabel_' .. idx
    local selW, selH = GetTileBoxSize(idx)
    local relBoxX = cachedPadX + (col * cachedCellW) + 3
    local relBoxY = baseIconY - 6

    SKIN:Bang(
        '[!SetOption ' .. iconName .. ' X "((#*PanelX*# + #*AnimShiftX*# + (' .. expIconX .. ' * #*AnimScale*#)) * #*IsOpen*#)"]' ..
        '[!SetOption ' .. iconName .. ' Y "((#*PanelY*# + #*AnimShiftY*# + (' .. expIconY .. ' * #*AnimScale*#)) * #*IsOpen*#)"]' ..
        '[!SetOption ' .. iconName .. ' W "(' .. expIconSize .. ' * #*AnimScale*# * #*IsOpen*#)"]' ..
        '[!SetOption ' .. iconName .. ' H "(' .. expIconSize .. ' * #*AnimScale*# * #*IsOpen*#)"]' ..
        '[!SetOption ' .. labelName .. ' Y "((#*PanelY*# + #*AnimShiftY*# + (' .. expLabelY .. ' * #*AnimScale*#)) * #*IsOpen*#)"]' ..
        '[!SetOption ' .. labelName .. ' FontWeight "600"]' ..
        '[!SetVariable SelW ' .. selW .. ']' ..
        '[!SetVariable SelH ' .. selH .. ']' ..
        '[!SetOption SelectionHighlight X "((#*PanelX*# + #*AnimShiftX*# + (' .. relBoxX .. ' * #*AnimScale*#)) * #*IsOpen*#)"]' ..
        '[!SetOption SelectionHighlight Y "((#*PanelY*# + #*AnimShiftY*# + (' .. relBoxY .. ' * #*AnimScale*#)) * #*IsOpen*#)"]' ..
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
    local ease = 1 - (inv * inv * inv)

    local scale = 1
    local alpha = floor(255 * ease + 0.5)
    local shiftX = 0
    local shiftY = 0

    if style == 'ExpandCollapse' then
        scale = 0.20 + (0.80 * ease)
        shiftX = openLeft and floor((1 - scale) * (cachedPanelW - 38)) or floor((1 - scale) * 20)
        shiftY = openUp and floor((1 - scale) * cachedPanelH) or floor(-(1 - scale) * 28)
    elseif style == 'ElasticBounce' then
        local pm1 = p - 1
        local backEase = 1 + 2.4 * (pm1 * pm1 * pm1) + 1.4 * (pm1 * pm1)
        scale = 0.20 + (0.80 * backEase)
        if scale < 0.15 then scale = 0.15 end
        local a = p * 1.8
        alpha = (a >= 1) and 255 or floor(255 * a + 0.5)
        shiftX = openLeft and floor((1 - scale) * (cachedPanelW - 38)) or floor((1 - scale) * 20)
        shiftY = openUp and floor((1 - scale) * cachedPanelH) or floor(-(1 - scale) * 28)

        if (cachedPanelX + shiftX) < 2 then shiftX = 2 - cachedPanelX end
        if (cachedPanelY + shiftY) < 2 then shiftY = 2 - cachedPanelY end
    elseif style == 'SubtlePop' then
        scale = 0.88 + (0.12 * ease)
        local a = p * 1.5
        alpha = (a >= 1) and 255 or floor(255 * a + 0.5)
        shiftX = floor((1 - scale) * cachedPanelW * 0.5)
        shiftY = floor((1 - scale) * cachedPanelH * 0.5)
    elseif style == 'Settle' then
        scale = 1.06 - (0.06 * ease)
        shiftX = floor((1 - scale) * cachedPanelW * 0.5)
        shiftY = floor((1 - scale) * cachedPanelH * 0.5)

        if (cachedPanelX + shiftX) < 2 then shiftX = 2 - cachedPanelX end
        if (cachedPanelY + shiftY) < 2 then shiftY = 2 - cachedPanelY end
    elseif style == 'VerticalBounce' then
        local pm1 = p - 1
        local backEase = 1 + 2.7 * (pm1 * pm1 * pm1) + 1.7 * (pm1 * pm1)
        local dist = floor((1 - backEase) * 42)
        local a = p * 1.8
        alpha = (a >= 1) and 255 or floor(255 * a + 0.5)
        shiftY = openUp and dist or -dist

        if (cachedPanelY + shiftY) < 2 then shiftY = 2 - cachedPanelY end
    elseif style == 'Snap' then
        local a = p * 2.0
        alpha = (a >= 1) and 255 or floor(255 * a + 0.5)
        local nudge = floor((1 - ease) * 10)
        shiftY = openUp and nudge or -nudge
    elseif style == 'Slide' then
        local dist = floor((1 - ease) * 75)
        shiftX = openLeft and dist or -floor(dist * 0.35)
        shiftY = openUp and dist or -dist
    elseif style == 'Fade' then
        alpha = floor(255 * p + 0.5)
    else -- 'None'
        alpha = (p >= 0.5) and 255 or 0
    end

    -- Clamp alpha and round scale to 3 decimals to avoid micro-updates
    if alpha < 0 then alpha = 0 elseif alpha > 255 then alpha = 255 end
    scale = floor(scale * 1000 + 0.5) / 1000

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
        SKIN:Bang(concat(bangs))
    end
end

function Update()
    if pendingRestore then
        pendingRestore = false
        local moveBang = ''
        if savedOrigX ~= nil and savedOrigY ~= nil then
            moveBang = '[!KeepOnScreen 0][!Move ' .. savedOrigX .. ' ' .. savedOrigY .. ']'
        end
        didMove = false
        SKIN:Bang(moveBang .. '[!Draggable 1][!SetOption MeasureToggle UpdateDivider -1][!UpdateMeasure MeasureToggle][!Redraw]')
        return
    end

    if animState ~= "idle" then
        local elapsed = clock() - animStartTime
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
        return
    end

    -- Smooth Windows Start-style hover fade when panel is idle
    if hoverAlpha ~= hoverTarget then
        local elapsed = clock() - hoverStartTime
        local nextAlpha = hoverTarget
        if hoverTarget > hoverStartAlpha then
            local t = min(1, elapsed / HOVER_IN_DURATION)
            local inv = 1 - t
            nextAlpha = hoverStartAlpha + (1 - hoverStartAlpha) * (1 - inv * inv)
        else
            local t = min(1, elapsed / HOVER_OUT_DURATION)
            nextAlpha = hoverStartAlpha * (1 - t)
        end

        hoverAlpha = floor(nextAlpha * 1000 + 0.5) / 1000
        if abs(hoverAlpha - hoverTarget) < 0.01 then
            hoverAlpha = hoverTarget
        end

        local bangs = {}
        local needHoverRedraw = false
        if hoverAlpha ~= lastHoverAlpha then
            lastHoverAlpha = hoverAlpha
            bangs[#bangs + 1] = '[!SetVariable HoverAlpha ' .. hoverAlpha .. ']'
            needHoverRedraw = true
        end

        if hoverAlpha == hoverTarget then
            if hoverTarget == 0 then
                hoveredIdx = -1
                bangs[#bangs + 1] = '[!HideMeter HoverHighlight]'
                needHoverRedraw = true
            end
            bangs[#bangs + 1] = '[!SetOption MeasureToggle UpdateDivider -1][!UpdateMeasure MeasureToggle]'
        end

        if needHoverRedraw then
            bangs[#bangs + 1] = '[!UpdateMeter HoverHighlight][!Redraw]'
        end

        if #bangs > 0 then
            SKIN:Bang(concat(bangs))
        end
    else
        SKIN:Bang('[!SetOption MeasureToggle UpdateDivider -1][!UpdateMeasure MeasureToggle]')
    end
end

local function GetWorkAreaForPoint(x, y)
    if x ~= nil and y ~= nil then
        for i = 1, 4 do
            local wx = tonumber(SKIN:ReplaceVariables('#WORKAREAX@' .. i .. '#'))
            local wy = tonumber(SKIN:ReplaceVariables('#WORKAREAY@' .. i .. '#'))
            local ww = tonumber(SKIN:ReplaceVariables('#WORKAREAWIDTH@' .. i .. '#'))
            local wh = tonumber(SKIN:ReplaceVariables('#WORKAREAHEIGHT@' .. i .. '#'))
            if wx and wy and ww and wh and ww > 0 and wh > 0 then
                if x >= wx and x <= (wx + ww) and y >= wy and y <= (wy + wh) then
                    return wx, wy, ww, wh
                end
            end
        end
    end
    local wx = tonumber(SKIN:ReplaceVariables('#WORKAREAX#')) or 0
    local wy = tonumber(SKIN:ReplaceVariables('#WORKAREAY#')) or 0
    local ww = tonumber(SKIN:ReplaceVariables('#WORKAREAWIDTH#')) or 1920
    local wh = tonumber(SKIN:ReplaceVariables('#WORKAREAHEIGHT#')) or 1080
    return wx, wy, ww, wh
end

function OpenPanel()
    if isOpen and animState ~= "closing" then return end
    if selectedIdx >= 0 then
        RestoreIcon(selectedIdx)
        selectedIdx = -1
    end

    cachedStyle = (SKIN:GetVariable('AnimStyle') or 'ExpandCollapse'):gsub('%s+', '')

    local skinX = tonumber(SKIN:ReplaceVariables('#CURRENTCONFIGX#'))
    local skinY = tonumber(SKIN:ReplaceVariables('#CURRENTCONFIGY#'))

    if pendingRestore then
        pendingRestore = false
        skinX = savedOrigX or skinX
        skinY = savedOrigY or skinY
    end

    if not isOpen then
        savedOrigX = skinX
        savedOrigY = skinY
        didMove = false
    end

    local workX, workY, workW, workH = GetWorkAreaForPoint(savedOrigX, savedOrigY)
    local rightEdge = workX + workW
    local bottomEdge = workY + workH

    isOpen = true
    local newSkinX = savedOrigX
    local newSkinY = savedOrigY
    local iconOffsetX = 0
    local iconOffsetY = 0
    local panelX = 18
    local panelY = 104

    openLeft = false
    openUp = false

    -- Shift the skin window inward if the popup (plus bounce headroom) would cross an edge,
    -- and offset the folder icon by the exact delta so it stays locked to savedOrigX / savedOrigY.
    if savedOrigX ~= nil and savedOrigY ~= nil then
        local bouncePadX = ceil(cachedPanelW * 0.06) + 12
        if (savedOrigX + panelX + cachedPanelW + bouncePadX) > rightEdge then
            openLeft = true
            local maxSkinX = rightEdge - panelX - cachedPanelW - bouncePadX
            local desiredSkinX = min(savedOrigX - (cachedPanelW - 76), maxSkinX)
            if desiredSkinX < (workX + 4) then
                desiredSkinX = workX + 4
            end
            newSkinX = desiredSkinX
            iconOffsetX = savedOrigX - newSkinX
        end

        local bouncePadY = ceil(cachedPanelH * 0.06) + 12
        if (savedOrigY + panelY + cachedPanelH + bouncePadY) > bottomEdge then
            openUp = true
            local shiftUp = cachedPanelH + 12
            local desiredSkinY = savedOrigY - shiftUp
            if desiredSkinY < (workY + 4) then
                desiredSkinY = workY + 4
            end
            newSkinY = desiredSkinY
            iconOffsetY = savedOrigY - newSkinY
            panelY = 10
        end
    end

    cachedPanelX = panelX
    cachedPanelY = panelY

    local setupBang =
        '[!SetVariable IsOpen 1]' ..
        '[!KeepOnScreen 0][!Draggable 0]' ..
        '[!SetVariable IconOffsetX ' .. iconOffsetX .. ']' ..
        '[!SetVariable IconOffsetY ' .. iconOffsetY .. ']' ..
        '[!SetVariable PanelX ' .. panelX .. ']' ..
        '[!SetVariable PanelY ' .. panelY .. ']' ..
        '[!ShowMeterGroup PanelContent][!HideMeter SelectionHighlight]'

    local moveBang = ''
    if newSkinX ~= nil and newSkinY ~= nil and (newSkinX ~= skinX or newSkinY ~= skinY) then
        didMove = true
        moveBang = '[!Move ' .. newSkinX .. ' ' .. newSkinY .. ']'
    end

    lastScale, lastAlpha, lastShiftX, lastShiftY = -1, -1, -9999, -9999

    if cachedStyle == 'None' then
        animState = "idle"
        animProgress = 1
        SKIN:Bang(setupBang)
        ApplyAnimFrame(1, true)
        SKIN:Bang('[!SetOption MeasureToggle UpdateDivider -1][!UpdateMeasure MeasureToggle][!UpdateMeter *][!Redraw]' .. moveBang)
    else
        animState = "opening"
        animStartProgress = (animProgress > 0 and animProgress < 1) and animProgress or 0.12
        animProgress = animStartProgress
        animStartTime = clock()
        SKIN:Bang(setupBang)
        ApplyAnimFrame(animProgress, true)
        SKIN:Bang('[!SetOption MeasureToggle UpdateDivider 1][!UpdateMeasure MeasureToggle][!UpdateMeter *][!Redraw]' .. moveBang)
    end
end

function ClosePanel()
    if not isOpen or animState == "closing" then return end
    if selectedIdx >= 0 then
        RestoreIcon(selectedIdx)
        selectedIdx = -1
    end

    cachedStyle = (SKIN:GetVariable('AnimStyle') or 'ExpandCollapse'):gsub('%s+', '')

    if cachedStyle == 'None' then
        FinishClose()
    else
        animState = "closing"
        animStartProgress = (animProgress > 0) and animProgress or 1
        animStartTime = clock()
        SKIN:Bang('[!HideMeter SelectionHighlight][!SetOption MeasureToggle UpdateDivider 1][!UpdateMeasure MeasureToggle]')
    end
end

function FinishClose(immediate)
    isOpen = false
    animState = "idle"
    animProgress = 0
    hoveredIdx = -1
    hoverAlpha = 0
    hoverTarget = 0
    lastHoverAlpha = 0
    cachedPanelX = 18
    cachedPanelY = 104
    lastScale, lastAlpha, lastShiftX, lastShiftY = 1, 0, 0, 0

    local curX = tonumber(SKIN:ReplaceVariables('#CURRENTCONFIGX#'))
    local curY = tonumber(SKIN:ReplaceVariables('#CURRENTCONFIGY#'))
    local needsMove = (savedOrigX ~= nil and savedOrigY ~= nil) and (didMove or curX ~= savedOrigX or curY ~= savedOrigY)

    local resetBang =
        '[!HideMeterGroup PanelContent][!HideMeter SelectionHighlight][!HideMeter HoverHighlight]' ..
        '[!SetVariable IsOpen 0][!SetVariable HoverAlpha 0]' ..
        '[!SetVariable AnimScale 1][!SetVariable AnimAlpha 0]' ..
        '[!SetVariable AnimShiftX 0][!SetVariable AnimShiftY 0]' ..
        '[!SetVariable IconOffsetX 0][!SetVariable IconOffsetY 0]' ..
        '[!SetVariable PanelX 18][!SetVariable PanelY 104]' ..
        '[!KeepOnScreen 0][!UpdateMeter *][!Redraw]'

    if needsMove and not immediate then
        pendingRestore = true
        SKIN:Bang(resetBang .. '[!SetOption MeasureToggle UpdateDivider 1][!UpdateMeasure MeasureToggle]')
    else
        pendingRestore = false
        didMove = false
        SKIN:Bang('[!SetOption MeasureToggle UpdateDivider -1][!UpdateMeasure MeasureToggle]' .. resetBang)
        if needsMove then
            SKIN:Bang('[!KeepOnScreen 0][!Move ' .. savedOrigX .. ' ' .. savedOrigY .. '][!Redraw]')
        end
        SKIN:Bang('[!Draggable 1]')
    end
end

function ClosePanelInstant()
    if selectedIdx >= 0 then
        RestoreIcon(selectedIdx)
        selectedIdx = -1
    end
    if isOpen then
        FinishClose(true)
    else
        pendingRestore = false
        didMove = false
        hoveredIdx = -1
        hoverAlpha = 0
        hoverTarget = 0
        lastHoverAlpha = 0
        SKIN:Bang('[!Draggable 1][!KeepOnScreen 0]')
    end
end
