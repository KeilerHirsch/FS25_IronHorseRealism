--
-- EngineStallModule ("soft-stall under overload")
--
-- First real feature + vertical slice of the backbone. Direct feedback for
-- pulling a heavy load with too little power: the engine does NOT die instantly.
-- It first AUDIBLY LABORS (bogs down under sustained overload = the game's own
-- straining engine note) and only stalls if the overload continues past a grace
-- window. Two phases: struggle -> stall.
--
-- Authoritative stall runs on the SERVER (stopMotor is engine-synced to all
-- clients); every client reads its own motor load locally for the HUD.
--
-- FINE-TUNING TODO (verified levers, not yet wired): during the struggle phase,
-- actively drop power for a louder bog-down via
--   self:getMotor():setAccelerationLimit(reduced)  (Motorized.lua:1568)
-- restore on recovery/stall; optional exhaust smoke. Kept out of this first
-- pass to avoid mis-restoring a vehicle's power without in-game calibration.
--

EngineStallModule = IronHorseModule.new("engineStall")

EngineStallModule.CFG = {
    OVERLOAD_LOAD    = 0.90,   -- clearly overloaded (ADS treats ~0.85 as overload)
    LUGGING_RPM      = 0.35,   -- near-idle rpm ...
    LUGGING_LOAD     = 0.85,   -- ... while heavily loaded = lugging
    STRUGGLE_SECONDS = 1.5,    -- sustained overload before the engine starts to labor
    STALL_SECONDS    = 4.0,    -- ... and dies (~2.5 s of audible struggle first)
    LUGGING_MULT     = 1.6,    -- lugging fills the timer faster than plain overload
    RECOVER_MULT     = 1.5,    -- timer bleeds off faster than it fills when load drops
    STALL_COOLDOWN_S = 2.0,    -- brief no-restart window after a stall
    HUD_WARN_LOAD    = 0.85,
}

EngineStallModule.PHASE_NONE = "none"
EngineStallModule.PHASE_STRUGGLE = "struggle"
EngineStallModule.PHASE_STALL = "stall"

---Pure, unit-testable two-phase overload integrator.
-- The accumulator counts seconds of sustained overload; it maps to a phase.
-- @param number acc current overload accumulator, in seconds
-- @param number loadRatio motor load 0..1
-- @param number rpmRatio motor rpm 0..1
-- @param number dtSec delta time in SECONDS
-- @param table cfg thresholds/rates
-- @return number newAcc, string phase ("none" | "struggle" | "stall")
function EngineStallModule.updateOverload(acc, loadRatio, rpmRatio, dtSec, cfg)
    local overloaded = loadRatio >= cfg.OVERLOAD_LOAD
    local lugging = rpmRatio <= cfg.LUGGING_RPM and loadRatio >= cfg.LUGGING_LOAD
    if overloaded or lugging then
        acc = acc + dtSec * (lugging and cfg.LUGGING_MULT or 1.0)
    else
        acc = acc - dtSec * cfg.RECOVER_MULT
        if acc < 0 then
            acc = 0
        end
    end

    local phase = EngineStallModule.PHASE_NONE
    if acc >= cfg.STALL_SECONDS then
        phase = EngineStallModule.PHASE_STALL
    elseif acc >= cfg.STRUGGLE_SECONDS then
        phase = EngineStallModule.PHASE_STRUGGLE
    end
    return acc, phase
end

function EngineStallModule:isSupported(vehicle)
    return vehicle ~= nil and vehicle.getMotorLoadPercentage ~= nil
end

function EngineStallModule:onLoad(_vehicle, state, _savegame)
    state.acc = 0
    state.cooldown = 0
    state.load = 0
    state.phase = EngineStallModule.PHASE_NONE
end

function EngineStallModule:onUpdate(vehicle, state, dt, isServer)
    if not IronHorseConfig.isModuleEnabled(self.name) then
        return
    end
    -- Read load locally (server + clients) so every HUD is live.
    state.load = vehicle:getMotorLoadPercentage() or 0

    if not isServer then
        return
    end
    if state.cooldown > 0 then
        state.cooldown = state.cooldown - dt
    end
    if vehicle.getIsMotorStarted == nil or not vehicle:getIsMotorStarted() then
        state.acc = 0
        state.phase = EngineStallModule.PHASE_NONE
        return
    end

    local rpm = (vehicle.getMotorRpmPercentage ~= nil and vehicle:getMotorRpmPercentage()) or 1
    local acc, phase = EngineStallModule.updateOverload(state.acc, state.load, rpm, dt / 1000, EngineStallModule.CFG)
    state.acc = acc
    state.phase = phase

    -- During PHASE_STRUGGLE the engine keeps running and bogs down under the
    -- sustained load -> it audibly labors. It only dies at PHASE_STALL.
    if phase == EngineStallModule.PHASE_STALL and state.cooldown <= 0 then
        vehicle:stopMotor()   -- engine event replicates the stall to all clients
        state.acc = 0
        state.phase = EngineStallModule.PHASE_NONE
        state.cooldown = EngineStallModule.CFG.STALL_COOLDOWN_S * 1000
    end
end

function EngineStallModule:drawHud(vehicle, state, hud)
    if not IronHorseConfig.isModuleEnabled(self.name) then
        return
    end
    local load = (vehicle.getMotorLoadPercentage ~= nil and vehicle:getMotorLoadPercentage()) or state.load or 0
    local pct = math.floor(load * 100 + 0.5)
    if state.phase == EngineStallModule.PHASE_STRUGGLE then
        hud.addWarning(string.format("!! Motor quaelt sich  %d%%", pct))
    elseif load >= EngineStallModule.CFG.HUD_WARN_LOAD then
        hud.addWarning(string.format("!  Motorlast  %d%%", pct))
    else
        hud.addLine(string.format("Motorlast  %d%%", pct))
    end
end
