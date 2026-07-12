--
-- ToolboxModule ("field repair")
--
-- Seventh feature module and the last of the planned chain. A makeshift FIELD
-- repair: out in the field, with the on-board toolbox, you can patch the machine
-- up enough to keep working — cheaper and quicker than the workshop, but only
-- partial (a proper full repair still needs the workshop). It closes the loop of
-- the realism chain: the machine wears (engine + usage), and here you keep it
-- going between workshop visits.
--
-- Like visualDirt, this REUSES the engine's own system instead of re-modelling it:
-- Farming Simulator already tracks damage/wear (the Wearable spec — getDamage-
-- Amount() 0..1, repairVehicle(), engine-synced + saved). This module reads that
-- damage for the cockpit HUD and supplies the pure field-repair maths (how much a
-- makeshift fix restores, what it costs). No state / sync / save of its own — the
-- engine owns the damage value.
--
-- FINE-TUNING TODO (deferred — the consequence + the price calibration Michael
-- wants next, both need real numbers + in-game feel):
--   1. ACTION (input): a "field repair" bind that, on the SERVER, applies
--      fieldRepairResult via setDamageAmount and charges fieldRepairCost via
--      g_currentMission:addMoney (a workshop visit still does the full repair).
--   2. PRICES: the field + workshop cost factors are now grounded in real
--      workshop data (IronHorseRealData.repair — German ag-workshop €/h, the
--      lifetime-repair ~25%-of-price rule, field ~45% of the workshop cost). The
--      remaining work is feel-tuning them against FS25's own economy in-game.
--

ToolboxModule = IronHorseModule.new("toolbox")

local REPAIR = IronHorseRealData.repair

ToolboxModule.CFG = {
    FIELD_REPAIR_FLOOR   = 0.15,   -- a makeshift fix can't get damage below this
                                    -- (the last bit needs the workshop)
    FIELD_REPAIR_AMOUNT  = 0.35,   -- damage removed by one field repair
    MIN_DAMAGE_TO_REPAIR = 0.10,   -- below this it isn't worth a field repair

    -- Economics grounded in real workshop data (IronHorseRealData.repair): a full
    -- 0->1 workshop repair costs WORKSHOP_REPAIR_FRACTION of the machine price; a
    -- field repair costs fieldRepairCostRatio of that for the same damage delta.
    WORKSHOP_REPAIR_FRACTION = REPAIR.workshopRepairFraction,                    -- 0.06
    FIELD_COST_FACTOR        = REPAIR.workshopRepairFraction * REPAIR.fieldRepairCostRatio, -- 0.027

    DAMAGE_WARN = 0.50,            -- HUD warning band
    DAMAGE_CRIT = 0.75,            -- HUD critical band (needs attention)
}

---Pure: damage (0..1) after one makeshift field repair. Removes a chunk but
-- never below the floor (workshop needed for the rest) and never worsens damage.
-- @return number newDamage
function ToolboxModule.fieldRepairResult(damage, cfg)
    local target = damage - cfg.FIELD_REPAIR_AMOUNT
    if target < cfg.FIELD_REPAIR_FLOOR then
        target = cfg.FIELD_REPAIR_FLOOR
    end
    if target > damage then
        target = damage   -- already at/under the floor → no change, never worsen
    end
    return target
end

---Pure: is a field repair worth doing now? Needs enough damage AND an actual
-- improvement to be available. @return boolean
function ToolboxModule.canFieldRepair(damage, cfg)
    return damage > cfg.MIN_DAMAGE_TO_REPAIR
        and ToolboxModule.fieldRepairResult(damage, cfg) < damage
end

---Pure: cost of a field repair = the damage fraction it removes, scaled by the
-- vehicle price and the (placeholder) cost factor. @return number cost
function ToolboxModule.fieldRepairCost(damage, vehiclePrice, cfg)
    local repaired = damage - ToolboxModule.fieldRepairResult(damage, cfg)
    if repaired < 0 then
        repaired = 0
    end
    return repaired * (vehiclePrice or 0) * cfg.FIELD_COST_FACTOR
end

---Pure: cost of a FULL workshop repair (damage -> 0) — the pricier, complete
-- alternative to a partial field repair. Grounded in the workshop-repair fraction
-- of the machine price. @return number cost
function ToolboxModule.workshopRepairCost(damage, vehiclePrice, cfg)
    return (damage or 0) * (vehiclePrice or 0) * cfg.WORKSHOP_REPAIR_FRACTION
end

---Pure: damage (0..1) → HUD severity. @return number
function ToolboxModule.repairSeverity(damage, cfg)
    if (damage or 0) >= cfg.DAMAGE_CRIT then
        return IronHorseHud.SEV_CRITICAL
    elseif (damage or 0) >= cfg.DAMAGE_WARN then
        return IronHorseHud.SEV_WARNING
    end
    return IronHorseHud.SEV_INFO
end

function ToolboxModule:isSupported(vehicle)
    return vehicle ~= nil and vehicle.getDamageAmount ~= nil
end

-- No onLoad / onUpdate / sync / save: damage is owned, replicated and persisted
-- by the engine's Wearable spec. This module only reads it. (The deferred repair
-- action will add a server-side input handler — see the header TODO.)

function ToolboxModule:getHudIndicators(vehicle, _state)
    if not IronHorseConfig.isModuleEnabled(self.name) then
        return nil
    end
    local cfg = ToolboxModule.CFG
    local damage = (vehicle ~= nil and vehicle.getDamageAmount ~= nil and vehicle:getDamageAmount()) or 0
    local status = ToolboxModule.canFieldRepair(damage, cfg) and "Feldrep." or nil
    return {
        {
            id = "toolbox",
            label = "SCHADEN",
            value = string.format("%d%%", math.floor(damage * 100 + 0.5)),
            status = status,
            severity = ToolboxModule.repairSeverity(damage, cfg),
        },
    }
end
