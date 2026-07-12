--
-- IronHorseHud
--
-- ONE unified HUD, built as a cockpit-style INDICATOR CLUSTER (mirrors the clean
-- ADS dashboard look, own code). Modules do not render themselves and do not push
-- raw text: each module DECLARES indicators (see IronHorseModule:getHudIndicators)
-- and this HUD lays them out in one consistent block and colours them by severity.
--
-- The cluster anchors to the game's own speed gauge when available (so it reads
-- like real dashboard tell-tales), with a fixed-position fallback.
--
-- FOUNDATION note: the render primitive here is a PLACEHOLDER — severity-coloured
-- labelled chips (drawFilledRect + text). The frame, the per-module slots and the
-- severity model are the real foundation; a hand-drawn IronHorse icon atlas (.dds
-- overlay per slice, like ads_dashboardHud) is a later art pass that swaps only
-- drawChip's body, nothing else.
--

IronHorseHud = {}

-- Severity vocabulary every module speaks. The HUD owns it so all indicators are
-- coloured consistently (a module returns one of these on its indicator).
IronHorseHud.SEV_INFO     = 1   -- neutral readout (white)
IronHorseHud.SEV_WARNING  = 2   -- attention (amber)
IronHorseHud.SEV_CRITICAL = 3   -- failing / about to break (red)
IronHorseHud.SEV_COOL     = 4   -- too cold (blue) — e.g. cold engine

IronHorseHud.SEV_COLORS = {
    [IronHorseHud.SEV_INFO]     = { 1.00, 1.00, 1.00, 1 },
    [IronHorseHud.SEV_WARNING]  = { 1.00, 0.65, 0.10, 1 },
    [IronHorseHud.SEV_CRITICAL] = { 1.00, 0.20, 0.15, 1 },
    [IronHorseHud.SEV_COOL]     = { 0.45, 0.72, 1.00, 1 },
}

-- Layout (screen-space fractions). CHIP = one indicator row.
IronHorseHud.FALLBACK_X = 0.013
IronHorseHud.FALLBACK_Y = 0.30
IronHorseHud.CLUSTER_W  = 0.115
IronHorseHud.CHIP_H     = 0.026
IronHorseHud.CHIP_GAP   = 0.004
IronHorseHud.PAD        = 0.006
IronHorseHud.TEXT_SIZE  = 0.014

---Resolve the cluster's top-left anchor. Prefers a slot next to the vanilla
-- speed gauge (dashboard look); falls back to a fixed screen position.
-- @return number x, number y
function IronHorseHud.getAnchor()
    local mission = g_currentMission
    local sm = mission ~= nil and mission.hud ~= nil and mission.hud.speedMeter or nil
    if sm ~= nil and sm.speedBg ~= nil and sm.speedBg.getPosition ~= nil then
        local sx, sy = sm.speedBg:getPosition()
        if sx ~= nil and sy ~= nil then
            -- to the LEFT of the gauge, roughly aligned to its middle
            return sx - IronHorseHud.CLUSTER_W - 0.012, sy + 0.02
        end
    end
    return IronHorseHud.FALLBACK_X, IronHorseHud.FALLBACK_Y
end

---Draw one placeholder indicator chip: a dimmed severity-coloured panel with the
-- module's label + value (+ status when it is warning/critical).
-- @param number x top-left x
-- @param number y top-left y
-- @param table ind { label, value?, status?, severity }
function IronHorseHud.drawChip(x, y, ind)
    local color = IronHorseHud.SEV_COLORS[ind.severity] or IronHorseHud.SEV_COLORS[IronHorseHud.SEV_INFO]
    -- placeholder panel (later: a real icon overlay from the atlas)
    drawFilledRect(x, y, IronHorseHud.CLUSTER_W, IronHorseHud.CHIP_H,
        color[1] * 0.25, color[2] * 0.25, color[3] * 0.25, 0.65)

    local text = ind.label or "?"
    if ind.value ~= nil then
        text = text .. "  " .. ind.value
    end
    if ind.status ~= nil and ind.severity ~= nil and ind.severity >= IronHorseHud.SEV_WARNING then
        text = text .. "  " .. ind.status
    end

    setTextBold((ind.severity ~= nil and ind.severity >= IronHorseHud.SEV_WARNING) or false)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(color[1], color[2], color[3], 1)
    renderText(x + IronHorseHud.PAD, y + IronHorseHud.CHIP_H * 0.28, IronHorseHud.TEXT_SIZE, text)

    setTextColor(1, 1, 1, 1)
    setTextBold(false)
end

---Render the indicator cluster for the entered vehicle. Client-side only; the
-- nil-guards on the render globals make it a no-op headless / on a dedicated
-- server (which never draws) and in unit tests.
-- @param table _vehicle the entered vehicle (reserved for future per-vehicle layout)
-- @param table indicators flat list of indicator tables from the modules
function IronHorseHud.renderCluster(_vehicle, indicators)
    if indicators == nil or #indicators == 0 then
        return
    end
    if renderText == nil or drawFilledRect == nil or setTextColor == nil or setTextBold == nil then
        return
    end

    local x, y = IronHorseHud.getAnchor()
    for _, ind in ipairs(indicators) do
        IronHorseHud.drawChip(x, y, ind)
        y = y + IronHorseHud.CHIP_H + IronHorseHud.CHIP_GAP
    end
end
