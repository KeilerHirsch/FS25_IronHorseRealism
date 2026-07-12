--
-- ElectricalModule ("battery & alternator")
--
-- Third feature module. Models a 12 V lead-acid starter battery: it discharges
-- through a small parasitic draw when the machine is off and recharges while the
-- engine runs (alternator regulated to ~14.4 V). Terminal voltage tracks the
-- state of charge when resting, and reads the regulated charge voltage while
-- running.
--
-- Authoritative on the SERVER; state of charge + voltage are replicated to
-- clients (initial stream + throttled live sync, both drift slowly) and the SOC
-- PERSISTS across saves. Numbers come from IronHorseRealData.battery (150 Ah,
-- 14.4 V charge, open-circuit resting band) — a real heavy-tractor battery.
--
-- FINE-TUNING TODO (deferred, needs in-game feel): the consequence layer — a
-- flat battery (SOC below the crank threshold) refuses to crank the engine
-- (gates the motor-start path), a cranking current burst on start, cold-weather
-- charge-acceptance, and accessory draw. This pass models + displays + persists.
--

ElectricalModule = IronHorseModule.new("electrical")

local BAT = IronHorseRealData.battery

ElectricalModule.CFG = {
    CAPACITY_AH     = BAT.nominalCapacityAh,   -- 150
    CHARGE_TARGET_V = BAT.chargeTargetV,        -- 14.4 (alternator regulated)
    RESTING_FULL_V  = BAT.restingFullV,         -- 12.7 at 100% SOC
    RESTING_EMPTY_V = BAT.restingEmptyV,        -- 11.8 at ~0% SOC
    ALT_CHARGE_A    = 55,                        -- net alternator charge current
    PARASITIC_A     = 1.0,                       -- key-off parasitic draw

    SOC_WARN        = 0.40,                       -- HUD warning band
    SOC_CRIT        = 0.20,                       -- HUD critical band (near flat)

    SOC_SYNC_DELTA  = 0.01,                       -- 1 %  -> throttled sync
    V_SYNC_DELTA    = 0.1,                         -- 0.1 V
}

---Pure: integrate battery state of charge one step. Running -> alternator
-- charges; off -> parasitic drain. @return number newSoc (clamped 0..1)
function ElectricalModule.updateSOC(soc, running, dtSec, cfg)
    local amps = running and cfg.ALT_CHARGE_A or -cfg.PARASITIC_A
    local newSoc = soc + (amps * dtSec / 3600) / cfg.CAPACITY_AH
    if newSoc < 0 then
        newSoc = 0
    elseif newSoc > 1 then
        newSoc = 1
    end
    return newSoc
end

---Pure: terminal voltage. Running -> regulated charge voltage; resting -> the
-- open-circuit voltage for the current SOC. @return number volts
function ElectricalModule.terminalVoltage(soc, running, cfg)
    if running then
        return cfg.CHARGE_TARGET_V
    end
    local s = math.max(0, math.min(soc, 1))
    return cfg.RESTING_EMPTY_V + s * (cfg.RESTING_FULL_V - cfg.RESTING_EMPTY_V)
end

---Pure: state of charge -> HUD severity (voltage while running masks a low
-- battery, so severity is driven by SOC). @return number severity
function ElectricalModule.socSeverity(soc, cfg)
    if soc <= cfg.SOC_CRIT then
        return IronHorseHud.SEV_CRITICAL
    elseif soc <= cfg.SOC_WARN then
        return IronHorseHud.SEV_WARNING
    end
    return IronHorseHud.SEV_INFO
end

function ElectricalModule:isSupported(vehicle)
    return vehicle ~= nil and vehicle.getIsMotorStarted ~= nil
end

function ElectricalModule:onLoad(_vehicle, state, _savegame)
    state.soc = 1.0
    state.voltage = ElectricalModule.terminalVoltage(1.0, false, ElectricalModule.CFG)
    state.syncedSoc = nil
    state.syncedVoltage = nil
end

function ElectricalModule:onUpdate(vehicle, state, dt, isServer)
    if not IronHorseConfig.isModuleEnabled(self.name) then
        return
    end
    if not isServer then
        return   -- authoritative on the server; clients get soc/voltage via sync
    end

    local dtSec = dt / 1000
    local running = vehicle.getIsMotorStarted ~= nil and vehicle:getIsMotorStarted()
    state.soc = ElectricalModule.updateSOC(state.soc, running, dtSec, ElectricalModule.CFG)
    state.voltage = ElectricalModule.terminalVoltage(state.soc, running, ElectricalModule.CFG)

    if math.abs(state.soc - (state.syncedSoc or -1000)) >= ElectricalModule.CFG.SOC_SYNC_DELTA then
        state.syncedSoc = state.soc
        IronHorseSyncEvent.send(vehicle, self.name, "soc", state.soc)
    end
    if math.abs(state.voltage - (state.syncedVoltage or -1000)) >= ElectricalModule.CFG.V_SYNC_DELTA then
        state.syncedVoltage = state.voltage
        IronHorseSyncEvent.send(vehicle, self.name, "voltage", state.voltage)
    end
end

---Initial MP sync: joining client gets SOC + voltage. Symmetric (two float32).
function ElectricalModule:onWriteStream(_vehicle, state, streamId, _connection)
    streamWriteFloat32(streamId, state.soc or 1.0)
    streamWriteFloat32(streamId, state.voltage or ElectricalModule.CFG.RESTING_FULL_V)
end

function ElectricalModule:onReadStream(_vehicle, state, streamId, _connection)
    state.soc = streamReadFloat32(streamId)
    state.voltage = streamReadFloat32(streamId)
end

---Persistence: the state of charge survives a save/load.
function ElectricalModule:saveToXML(_vehicle, state, xmlFile, key)
    xmlFile:setValue(key .. "#soc", state.soc or 1.0)
end

function ElectricalModule:loadFromXML(_vehicle, state, xmlFile, key)
    state.soc = xmlFile:getValue(key .. "#soc", state.soc or 1.0)
    state.voltage = ElectricalModule.terminalVoltage(state.soc, false, ElectricalModule.CFG)
end

function ElectricalModule:getHudIndicators(_vehicle, state)
    if not IronHorseConfig.isModuleEnabled(self.name) then
        return nil
    end
    local cfg = ElectricalModule.CFG
    local severity = ElectricalModule.socSeverity(state.soc or 1, cfg)
    return {
        {
            id = "battVoltage",
            label = "BATT",
            value = string.format("%.1fV", state.voltage or 0),
            severity = severity,
        },
        {
            id = "battCharge",
            label = "LADUNG",
            value = string.format("%d%%", math.floor((state.soc or 1) * 100 + 0.5)),
            severity = severity,
        },
    }
end
