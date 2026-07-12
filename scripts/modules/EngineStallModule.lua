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
-- The struggle PHASE is computed only on the server, but the HUD renders on
-- every client. On a dedicated server the driving client is never isServer, so
-- it cannot compute the phase itself -> the phase is replicated to clients:
--   * initial sync on join via onWriteStream/onReadStream (a client joining
--     mid-struggle sees the current phase immediately);
--   * live sync on every phase change via IronHorseSyncEvent (server -> clients).
-- Phase is a small numeric enum so it serialises cleanly over both paths.
--
-- FINE-TUNING TODO (verified levers, not yet wired): during the struggle phase,
-- actively drop power for a louder bog-down via
--   self:getMotor():setAccelerationLimit(reduced)  (Motorized.lua:1568)
-- restore on recovery/stall; optional exhaust smoke. Kept out of this pass to
-- avoid mis-restoring a vehicle's power without in-game calibration.
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
    STALL_COOLDOWN_S = 2.0,    -- post-stall re-stall debounce (see note below)
    HUD_WARN_LOAD    = 0.85,
}

-- NOTE on STALL_COOLDOWN_S: this is a re-STALL debounce, not a restart lockout.
-- At the current thresholds it never actually bites: after a stall the acc resets
-- to 0 and needs STALL_SECONDS/LUGGING_MULT = 4.0/1.6 = 2.5 s to reach STALL
-- again, which already exceeds the 2.0 s cooldown. A true "engine won't restart
-- for N seconds" lockout (gating the motor-start path) is a FINE-TUNING TODO to
-- build and calibrate in-game with the power-drop pass. Kept as the intent hook.

-- Phase is a compact numeric enum (not a string) so it serialises directly over
-- the initial stream (onWriteStream, 2 bits) and the live sync event.
EngineStallModule.PHASE_NONE = 0
EngineStallModule.PHASE_STRUGGLE = 1
EngineStallModule.PHASE_STALL = 2

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

    -- Server owns the phase; remember it so we replicate only on a change.
    local prevPhase = state.phase

    if state.cooldown > 0 then
        state.cooldown = state.cooldown - dt
    end

    if vehicle.getIsMotorStarted == nil or not vehicle:getIsMotorStarted() then
        state.acc = 0
        state.phase = EngineStallModule.PHASE_NONE
    else
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

    -- Replicate the phase to clients on change. The driving client on a
    -- dedicated server never runs the block above (it is not isServer), so the
    -- "!! Motor quaelt sich" HUD cue depends entirely on this sync.
    if state.phase ~= prevPhase then
        IronHorseSyncEvent.send(vehicle, self.name, "phase", state.phase)
    end
end

---Initial MP sync: replicate the current phase to a joining client so an
-- in-progress struggle shows on its HUD immediately. Symmetric 2-bit enum
-- (PHASE_NONE/STRUGGLE/STALL = 0..2 fit in 2 bits).
function EngineStallModule:onWriteStream(_vehicle, state, streamId, _connection)
    streamWriteUIntN(streamId, state.phase or EngineStallModule.PHASE_NONE, 2)
end

function EngineStallModule:onReadStream(_vehicle, state, streamId, _connection)
    state.phase = streamReadUIntN(streamId, 2)
end

---Pure: map the stall phase + motor load to a HUD severity. Unit-testable
-- without the engine (mirrors the updateOverload pure-function pattern).
-- @param number phase current phase (PHASE_*)
-- @param number load motor load 0..1
-- @param table cfg thresholds
-- @return number severity (one of IronHorseHud.SEV_*)
function EngineStallModule.indicatorSeverity(phase, load, cfg)
    if phase == EngineStallModule.PHASE_STRUGGLE or phase == EngineStallModule.PHASE_STALL then
        return IronHorseHud.SEV_CRITICAL   -- laboring or dead: alarm the driver
    elseif load >= cfg.HUD_WARN_LOAD then
        return IronHorseHud.SEV_WARNING    -- heavy load
    end
    return IronHorseHud.SEV_INFO
end

function EngineStallModule:getHudIndicators(vehicle, state)
    if not IronHorseConfig.isModuleEnabled(self.name) then
        return nil
    end
    local load = (vehicle.getMotorLoadPercentage ~= nil and vehicle:getMotorLoadPercentage()) or state.load or 0
    local pct = math.floor(load * 100 + 0.5)
    local severity = EngineStallModule.indicatorSeverity(state.phase, load, EngineStallModule.CFG)
    local status = (state.phase == EngineStallModule.PHASE_STRUGGLE) and "quaelt sich" or nil
    return {
        { id = "engineStall", label = "MOTOR", value = string.format("%d%%", pct), status = status, severity = severity },
    }
end
