--
-- EngineHealthModule ("engine wear & temperature")
--
-- Second feature module + the first with PERSISTENT, SYNCED state. Models a
-- diesel's thermal behaviour and long-term engine condition:
--   * temperature integrates toward a load-dependent target (Newton cooling):
--     idles warm, climbs into the overheat band under sustained heavy load,
--     cools to ambient when off. Ambient comes from the in-game weather.
--   * condition (0..1) degrades from stress — overheating, cold-shock (load on a
--     cold engine), sustained overload, plus a slow baseline while running.
--
-- Authoritative on the SERVER; temp + condition are replicated to clients
-- (initial stream on join + throttled live sync, since both change slowly) so
-- the cockpit HUD reads correctly on a dedicated server. Condition PERSISTS
-- across saves — the first module to use the backbone's savegame hooks.
--
-- Numbers are grounded in IronHorseRealData.engine (cold/normal/overheat bands),
-- not invented. Real automotive/agricultural thermal behaviour, own model
-- (mechanics only — no third-party code).
--
-- FINE-TUNING TODO (deferred, needs in-game feel): active consequences — power
-- derate + higher stall risk at low condition (couples into engineStall), a
-- cold-engine power limit until warmed up, and threshold calibration. This pass
-- models + displays + persists; the consequence layer comes with calibration.
--

EngineHealthModule = IronHorseModule.new("engineHealth")

local ENG = IronHorseRealData.engine

EngineHealthModule.CFG = {
    AMBIENT_DEFAULT      = 20,                    -- deg C, when weather is unavailable
    IDLE_TEMP            = 80,                     -- running target at no load
    FULL_LOAD_RISE       = 35,                     -- + at full load -> 115 target (overheat)
    WARMUP_RATE          = 0.020,                  -- per-second approach toward a higher target
    COOLDOWN_RATE        = 0.010,                  -- ... slower when the target is below temp
    COLD_THRESHOLD       = ENG.coldBelowC,         -- 50 — below = cold-operation region
    HOT_WARN_TEMP        = 100,                    -- HUD warning band before overheat
    OVERHEAT_THRESHOLD   = ENG.overheatAboveC,     -- 105 — real coolant overheat region

    -- condition wear, expressed per operating HOUR (integrated by dt)
    BASE_WEAR_PER_H      = 0.02,                   -- baseline while running (~50 h span)
    OVERHEAT_WEAR_PER_H  = 0.60,                   -- per 10 deg C over the overheat threshold
    COLD_LOAD_WEAR_PER_H = 0.15,                   -- cold engine pulled under load (cold-shock)
    OVERLOAD_WEAR_PER_H  = 0.10,                   -- sustained heavy load
    OVERLOAD_LOAD        = 0.90,
    COLD_LOAD_LOAD       = 0.50,                   -- "under load" while still cold

    -- HUD condition bands
    COND_WARN            = 0.50,
    COND_CRIT            = 0.20,

    -- sync throttle (both values change slowly -> only send on a meaningful delta)
    TEMP_SYNC_DELTA      = 1.0,                    -- deg C
    COND_SYNC_DELTA      = 0.005,                  -- 0.5 %
}

---Pure: integrate engine temperature one step toward its load-based target.
-- @param number temp current temperature (deg C)
-- @param number load motor load 0..1
-- @param number ambient ambient temperature (deg C) = the floor
-- @param number dtSec delta time in SECONDS
-- @param table cfg thresholds/rates
-- @param boolean running whether the motor is running
-- @return number newTemp
function EngineHealthModule.updateTemperature(temp, load, ambient, dtSec, cfg, running)
    local target
    if running then
        local l = math.max(0, math.min(load, 1))
        target = cfg.IDLE_TEMP + l * cfg.FULL_LOAD_RISE
    else
        target = ambient
    end
    local rate = (target > temp) and cfg.WARMUP_RATE or cfg.COOLDOWN_RATE
    local newTemp = temp + (target - temp) * rate * dtSec
    if newTemp < ambient then
        newTemp = ambient
    end
    return newTemp
end

---Pure: degrade condition one step from thermal/load stress. Only called while
-- the engine runs. @return number newCondition (clamped to >= 0)
function EngineHealthModule.updateCondition(condition, temp, load, dtSec, cfg)
    local dtHours = dtSec / 3600
    local wearPerH = cfg.BASE_WEAR_PER_H
    if temp > cfg.OVERHEAT_THRESHOLD then
        wearPerH = wearPerH + cfg.OVERHEAT_WEAR_PER_H * ((temp - cfg.OVERHEAT_THRESHOLD) / 10)
    end
    if temp < cfg.COLD_THRESHOLD and load >= cfg.COLD_LOAD_LOAD then
        wearPerH = wearPerH + cfg.COLD_LOAD_WEAR_PER_H
    end
    if load >= cfg.OVERLOAD_LOAD then
        wearPerH = wearPerH + cfg.OVERLOAD_WEAR_PER_H
    end
    local newCond = condition - wearPerH * dtHours
    if newCond < 0 then
        newCond = 0
    end
    return newCond
end

---Pure: temperature -> HUD severity.
function EngineHealthModule.tempSeverity(temp, cfg)
    if temp >= cfg.OVERHEAT_THRESHOLD then
        return IronHorseHud.SEV_CRITICAL
    elseif temp >= cfg.HOT_WARN_TEMP then
        return IronHorseHud.SEV_WARNING
    elseif temp < cfg.COLD_THRESHOLD then
        return IronHorseHud.SEV_COOL
    end
    return IronHorseHud.SEV_INFO
end

---Pure: condition -> HUD severity.
function EngineHealthModule.conditionSeverity(condition, cfg)
    if condition <= cfg.COND_CRIT then
        return IronHorseHud.SEV_CRITICAL
    elseif condition <= cfg.COND_WARN then
        return IronHorseHud.SEV_WARNING
    end
    return IronHorseHud.SEV_INFO
end

---Ambient temperature from the in-game weather, with a safe fallback.
function EngineHealthModule.getAmbient()
    local m = g_currentMission
    if m ~= nil and m.environment ~= nil and m.environment.weather ~= nil
        and m.environment.weather.forecast ~= nil
        and m.environment.weather.forecast.getCurrentWeather ~= nil then
        local w = m.environment.weather.forecast:getCurrentWeather()
        if w ~= nil and w.temperature ~= nil then
            return w.temperature
        end
    end
    return EngineHealthModule.CFG.AMBIENT_DEFAULT
end

function EngineHealthModule:isSupported(vehicle)
    return vehicle ~= nil and vehicle.getMotorLoadPercentage ~= nil
end

function EngineHealthModule:onLoad(_vehicle, state, _savegame)
    state.temp = EngineHealthModule.getAmbient()
    state.condition = 1.0
    state.syncedTemp = nil
    state.syncedCondition = nil
end

function EngineHealthModule:onUpdate(vehicle, state, dt, isServer)
    if not IronHorseConfig.isModuleEnabled(self.name) then
        return
    end
    if not isServer then
        return   -- authoritative on the server; clients get temp/condition via sync
    end

    local dtSec = dt / 1000
    local ambient = EngineHealthModule.getAmbient()
    local running = vehicle.getIsMotorStarted ~= nil and vehicle:getIsMotorStarted()
    local load = (running and vehicle.getMotorLoadPercentage ~= nil and vehicle:getMotorLoadPercentage()) or 0

    state.temp = EngineHealthModule.updateTemperature(state.temp, load, ambient, dtSec, EngineHealthModule.CFG, running)
    if running then
        state.condition = EngineHealthModule.updateCondition(state.condition, state.temp, load, dtSec, EngineHealthModule.CFG)
    end

    -- Throttled sync: both values drift slowly, so only send on a real delta.
    if math.abs(state.temp - (state.syncedTemp or -1000)) >= EngineHealthModule.CFG.TEMP_SYNC_DELTA then
        state.syncedTemp = state.temp
        IronHorseSyncEvent.send(vehicle, self.name, "temp", state.temp)
    end
    if math.abs(state.condition - (state.syncedCondition or -1000)) >= EngineHealthModule.CFG.COND_SYNC_DELTA then
        state.syncedCondition = state.condition
        IronHorseSyncEvent.send(vehicle, self.name, "condition", state.condition)
    end
end

---Initial MP sync: a joining client gets the current temp + condition so the
-- cockpit gauges are right immediately. Symmetric: two float32 written and read.
function EngineHealthModule:onWriteStream(_vehicle, state, streamId, _connection)
    streamWriteFloat32(streamId, state.temp or EngineHealthModule.CFG.AMBIENT_DEFAULT)
    streamWriteFloat32(streamId, state.condition or 1.0)
end

function EngineHealthModule:onReadStream(_vehicle, state, streamId, _connection)
    state.temp = streamReadFloat32(streamId)
    state.condition = streamReadFloat32(streamId)
end

---Persistence: condition (and the last temp) survive a save/load. First module
-- to use the backbone's savegame hooks.
function EngineHealthModule:saveToXML(_vehicle, state, xmlFile, key)
    xmlFile:setValue(key .. "#condition", state.condition or 1.0)
    xmlFile:setValue(key .. "#temp", state.temp or EngineHealthModule.CFG.AMBIENT_DEFAULT)
end

function EngineHealthModule:loadFromXML(_vehicle, state, xmlFile, key)
    state.condition = xmlFile:getValue(key .. "#condition", state.condition or 1.0)
    state.temp = xmlFile:getValue(key .. "#temp", state.temp or EngineHealthModule.CFG.AMBIENT_DEFAULT)
end

function EngineHealthModule:getHudIndicators(_vehicle, state)
    if not IronHorseConfig.isModuleEnabled(self.name) then
        return nil
    end
    local cfg = EngineHealthModule.CFG
    return {
        {
            id = "engineTemp",
            label = "TEMP",
            value = string.format("%d\194\176C", math.floor((state.temp or 0) + 0.5)),
            severity = EngineHealthModule.tempSeverity(state.temp or 0, cfg),
        },
        {
            id = "engineCond",
            label = "ZUSTAND",
            value = string.format("%d%%", math.floor((state.condition or 1) * 100 + 0.5)),
            severity = EngineHealthModule.conditionSeverity(state.condition or 1, cfg),
        },
    }
end
