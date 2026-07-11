--
-- EngineStallModule ("soft-stall under overload")
--
-- The first real feature and the vertical slice that proves the whole backbone.
-- Direct feedback for pulling 50 t of wheat with a 180 hp moped: keep the engine
-- overloaded (or lug it at low rpm under high load) and it stalls.
--
-- Authoritative stall runs on the SERVER (stopMotor is engine-synced to all
-- clients); every client reads its own motor load locally for the HUD.
--

EngineStallModule = IronHorseModule.new("engineStall")

EngineStallModule.CFG = {
    OVERLOAD_LOAD   = 0.98,          -- engine effectively maxed out
    LUGGING_RPM     = 0.35,          -- near-idle rpm ...
    LUGGING_LOAD    = 0.85,          -- ... while heavily loaded = lugging
    OVERLOAD_RATE   = 1.0 / 2500.0,  -- ~2.5 s of full overload -> stall
    LUGGING_RATE    = 1.0 / 1500.0,  -- lugging bogs the engine down faster
    RECOVER_RATE    = 1.0 / 2000.0,  -- accumulator bleeds off when load drops
    STALL_THRESHOLD = 1.0,
    STALL_COOLDOWN_MS = 1500,        -- brief no-restart window after a stall
    HUD_WARN_LOAD   = 0.90,
}

---Pure, unit-testable overload integrator.
-- @param number acc current overload accumulator (0..~1)
-- @param number loadRatio motor load 0..1
-- @param number rpmRatio motor rpm 0..1
-- @param number dt delta time in ms
-- @param table cfg thresholds/rates
-- @return number newAcc, boolean shouldStall
function EngineStallModule.updateOverload(acc, loadRatio, rpmRatio, dt, cfg)
    local overloaded = loadRatio >= cfg.OVERLOAD_LOAD
    local lugging = rpmRatio <= cfg.LUGGING_RPM and loadRatio >= cfg.LUGGING_LOAD
    if overloaded or lugging then
        local rate = lugging and cfg.LUGGING_RATE or cfg.OVERLOAD_RATE
        acc = acc + rate * dt
    else
        acc = acc - cfg.RECOVER_RATE * dt
        if acc < 0 then
            acc = 0
        end
    end
    return acc, acc >= cfg.STALL_THRESHOLD
end

function EngineStallModule:isSupported(vehicle)
    return vehicle ~= nil and vehicle.getMotorLoadPercentage ~= nil
end

function EngineStallModule:onLoad(_vehicle, state, _savegame)
    state.acc = 0
    state.cooldown = 0
    state.load = 0
end

function EngineStallModule:onUpdate(vehicle, state, dt, isServer)
    if not IronHorseConfig.isModuleEnabled(self.name) then
        return
    end
    -- Read load locally (both server + clients) so every HUD is live.
    state.load = vehicle:getMotorLoadPercentage() or 0

    if not isServer then
        return
    end
    if state.cooldown > 0 then
        state.cooldown = state.cooldown - dt
    end
    if vehicle.getIsMotorStarted == nil or not vehicle:getIsMotorStarted() then
        state.acc = 0
        return
    end

    local rpm = (vehicle.getMotorRpmPercentage ~= nil and vehicle:getMotorRpmPercentage()) or 1
    local acc, stall = EngineStallModule.updateOverload(state.acc, state.load, rpm, dt, EngineStallModule.CFG)
    state.acc = acc

    if stall and state.cooldown <= 0 then
        vehicle:stopMotor()           -- engine event replicates the stall to all clients
        state.acc = 0
        state.cooldown = EngineStallModule.CFG.STALL_COOLDOWN_MS
    end
end

function EngineStallModule:drawHud(vehicle, state, hud)
    if not IronHorseConfig.isModuleEnabled(self.name) then
        return
    end
    local load = (vehicle.getMotorLoadPercentage ~= nil and vehicle:getMotorLoadPercentage()) or state.load or 0
    local pct = math.floor(load * 100 + 0.5)
    if load >= EngineStallModule.CFG.HUD_WARN_LOAD then
        hud.addWarning(string.format("! Motor-Ueberlast %d%%", pct))
    else
        hud.addLine(string.format("Motorlast %d%%", pct))
    end
end
