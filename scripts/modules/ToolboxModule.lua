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
-- Like visualDirt, this REUSES the engine's own systems instead of re-modelling
-- them: Farming Simulator already tracks damage (the Wearable spec —
-- getDamageAmount() 0..1, setDamageAmount, engine-synced + saved) and prices a
-- repair (Wearable.calculateRepairPrice = price * damage^1.5 * 0.09). This module
-- reads the damage for the cockpit HUD, reuses that repair curve so its costs feel
-- native to the economy, and adds the field-repair action.
--
-- ACTION (wired): a "field repair" input (Shift+R by default). The client callback
-- sends a ToolboxRepairEvent; the SERVER (performFieldRepair) reads the damage and
-- the price FROM THE VEHICLE ITSELF (never a client-supplied value), charges the
-- owner farm FS25-style (MoneyType.VEHICLE_REPAIR) and lowers the damage to the
-- field-repair floor. Server-authoritative; setDamageAmount + addMoney are engine-
-- replicated, so all clients see the result.
--
-- IN-GAME TODO (needs Michael's dedicated-server test, not headless-verifiable):
-- key feel, cost feel vs FS25's economy, and MP correctness (client press -> server
-- applies -> every client sees the lower damage + the charge on the owner farm).
--

ToolboxModule = IronHorseModule.new("toolbox")

local REPAIR = IronHorseRealData.repair

ToolboxModule.CFG = {
    FIELD_REPAIR_FLOOR   = 0.15,   -- a makeshift fix can't get damage below this
                                    -- (the last bit needs the workshop)
    FIELD_REPAIR_AMOUNT  = 0.35,   -- damage removed by one field repair
    MIN_DAMAGE_TO_REPAIR = 0.10,   -- below this it isn't worth a field repair

    -- Economics reuse FS25's OWN repair curve (price * damage^EXP * FRACTION, from
    -- Wearable.calculateRepairPrice) so costs feel native; a field repair is a
    -- discount on the marginal cost of the damage chunk it removes. See
    -- IronHorseRealData.repair (the 9% also matches real DE workshop data).
    FULL_REPAIR_FRACTION    = REPAIR.fullRepairFraction,   -- 0.09 (FS25 at full damage)
    REPAIR_EXPONENT         = REPAIR.repairExponent,        -- 1.5  (FS25 curve)
    FIELD_REPAIR_COST_RATIO = REPAIR.fieldRepairCostRatio,  -- 0.45 (field vs workshop)

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

---Pure: FS25's own workshop repair price for a damage/price (mirrors
-- Wearable.calculateRepairPrice = price * damage^1.5 * 0.09). Reused so IronHorse
-- costs are native to the game economy. @return number cost
function ToolboxModule.workshopRepairCost(damage, vehiclePrice, cfg)
    local d = damage or 0
    if d < 0 then d = 0 end
    return (vehiclePrice or 0) * (d ^ cfg.REPAIR_EXPONENT) * cfg.FULL_REPAIR_FRACTION
end

---Pure: cost of a partial FIELD repair = a discount (FIELD_REPAIR_COST_RATIO) on
-- the workshop's MARGINAL cost for the damage chunk it removes. @return number cost
function ToolboxModule.fieldRepairCost(damage, vehiclePrice, cfg)
    local after = ToolboxModule.fieldRepairResult(damage, cfg)
    local marginal = ToolboxModule.workshopRepairCost(damage, vehiclePrice, cfg)
                   - ToolboxModule.workshopRepairCost(after, vehiclePrice, cfg)
    if marginal < 0 then
        marginal = 0
    end
    return marginal * cfg.FIELD_REPAIR_COST_RATIO
end

---Pure: can the farm afford it? Fail CLOSED — an unknown/unresolved balance
-- blocks the repair (we can't confirm funds, and must not charge a farm we
-- couldn't resolve). A known balance must cover the cost. @return boolean
function ToolboxModule.canAfford(cost, balance)
    return balance ~= nil and balance >= (cost or 0)
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

-- No onLoad / onUpdate / sync / save: damage is owned, replicated and persisted by
-- the engine's Wearable spec. This module reads it and drives the repair action.

---Client: bind the field-repair key for the vehicle the player controls.
function ToolboxModule:onRegisterActionEvents(vehicle, _state, actionEvents)
    if not IronHorseConfig.isModuleEnabled(self.name) then
        return
    end
    if vehicle == nil or vehicle.addActionEvent == nil then
        return
    end
    local ok, actionEventId = vehicle:addActionEvent(actionEvents, InputAction.IH_FIELD_REPAIR,
        vehicle, ToolboxModule.onFieldRepairEvent, false, true, false, true, nil)
    if ok and actionEventId ~= nil and g_inputBinding ~= nil then
        g_inputBinding:setActionEventTextVisibility(actionEventId, true)
        if g_i18n ~= nil then
            g_inputBinding:setActionEventText(actionEventId, g_i18n:getText("input_IH_FIELD_REPAIR"))
        end
    end
end

---Client callback (key pressed on the entered vehicle): ask the server to repair.
function ToolboxModule.onFieldRepairEvent(vehicle, _actionName, _inputValue, _callbackState, _isAnalog)
    if vehicle ~= nil then
        ToolboxRepairEvent.sendRequest(vehicle)
    end
end

---Access control (server): may the requesting connection field-repair this
-- vehicle? A relayed CLIENT request must come from a player whose farm OWNS the
-- vehicle — otherwise a cheat client could name any net-id and spend a rival
-- farm's money. Fail CLOSED: any broken link (no userManager, unknown user, no
-- farm, mismatch) denies. A nil connection = the local/host server player, trusted.
-- @return boolean
function ToolboxModule.isConnectionEntitled(vehicle, connection)
    if connection == nil then
        return true   -- local/host action, not a relayed client request
    end
    if vehicle == nil or vehicle.getOwnerFarmId == nil then
        return false
    end
    -- Proven pattern (mirrors ADS_ServiceRequestEvent): resolve the sender's
    -- userId from the connection, its farm via the farm manager, and require it to
    -- be the vehicle's owner farm. Any missing link fails closed.
    if g_currentMission == nil or g_currentMission.userManager == nil
        or g_farmManager == nil or g_farmManager.getFarmByUserId == nil then
        return false
    end
    local userId = g_currentMission.userManager:getUserIdByConnection(connection)
    local farm = g_farmManager:getFarmByUserId(userId)
    return farm ~= nil and farm.farmId == vehicle:getOwnerFarmId()
end

---SERVER: perform the field repair authoritatively. Reads damage + price from the
-- vehicle itself (never a client value), verifies the requester's farm owns the
-- vehicle, charges that farm FS25-style, and lowers the damage. No-op if
-- unauthorised, not worth it, or unaffordable.
-- @param connection nil for a local/host request, else the requesting client's
-- connection (which must be entitled).
function ToolboxModule.performFieldRepair(vehicle, connection)
    if vehicle == nil or vehicle.getDamageAmount == nil or vehicle.setDamageAmount == nil then
        return
    end
    if vehicle.spec_ironHorseRealism == nil then
        return   -- only IronHorse-managed vehicles, not any Wearable object (trailers/implements)
    end
    if not IronHorseConfig.isModuleEnabled(ToolboxModule.name) then
        return
    end
    if not ToolboxModule.isConnectionEntitled(vehicle, connection) then
        return   -- a client may only repair a vehicle its own farm owns
    end
    local cfg = ToolboxModule.CFG
    local damage = vehicle:getDamageAmount() or 0
    if not ToolboxModule.canFieldRepair(damage, cfg) then
        return
    end
    local price = (vehicle.getPrice ~= nil and vehicle:getPrice()) or 0
    local cost = ToolboxModule.fieldRepairCost(damage, price, cfg)
    local farmId = (vehicle.getOwnerFarmId ~= nil and vehicle:getOwnerFarmId()) or 0

    local balance = nil
    if g_farmManager ~= nil and g_farmManager.getFarmById ~= nil then
        local farm = g_farmManager:getFarmById(farmId)
        if farm ~= nil then
            balance = farm.money
        end
    end
    if not ToolboxModule.canAfford(cost, balance) then
        return
    end

    if g_currentMission ~= nil and g_currentMission.addMoney ~= nil and MoneyType ~= nil then
        g_currentMission:addMoney(-cost, farmId, MoneyType.VEHICLE_REPAIR, true, true)
    end
    vehicle:setDamageAmount(ToolboxModule.fieldRepairResult(damage, cfg), true)
end

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
