--
-- DrivetrainModule ("differential locks & power split")
--
-- Fourth feature module + the first of the PHYSICS layer. Models the driver's
-- control over the driveline: front / rear differential locks and the drive mode
-- (2WD / 4WD / FWD), plus the front/rear power split that follows from it. A
-- locked diff binds an axle's two wheels to the same speed (traction in the mud,
-- tyre scrub on hard ground at speed); an open diff lets them turn freely.
--
-- Authoritative on the SERVER; the three discrete states (front lock, rear lock,
-- drive mode) are replicated to clients (initial stream on join + sync on change)
-- so the cockpit HUD reads right on a dedicated server, and they PERSIST across
-- saves.
--
-- Locks are stored as NUMBERS (0/1), never Lua booleans: the shared sync event
-- carries a single float, so a lock arrives on the client as 0.0/1.0 — and in Lua
-- `0` is truthy, so a boolean field would read "locked" for an unlocked diff. The
-- canonical representation is numeric; compare with `== 1`.
--
-- MECHANIC PROVENANCE (§ 69a UrhG: ideas/mechanics are not protected — this is a
-- clean-room re-build, no third-party code): the diff mechanic is the GIANTS
-- engine call `updateDifferential(rootNode, diffIndex, torqueRatio, maxSpeedRatio)`
-- (diffIndex 0=front axle, 1=rear axle, 2=centre/front-to-back). A LOCKED diff
-- uses maxSpeedRatio 1 (axle sides bound); an OPEN one uses base*1000 (free). The
-- centre diff sets the drive mode. This is the same mechanic EnhancedVehicle
-- exposes, reimplemented from the engine API + real driveline behaviour. EV is
-- GPL-3.0 → referenced for the HOW only, never copied.
--
-- IN-GAME / FINE-TUNING TODO (deferred — this is the physics-hook part that needs
-- the maintainer's dedicated-server test, NOT wired into the hot path yet):
--   1. INPUT — bind toggle actions (front lock / rear lock / cycle drive mode).
--      Needs modDesc <actions>+<inputBinding> + l10n + an onRegisterActionEvents
--      dispatch on the backbone. Until then diffs stay at their default (open,
--      4WD = vanilla behaviour), so the module is inert-but-safe in the world.
--   2. PHYSICS APPLY — call DrivetrainModule.applyDifferentials(vehicle, state)
--      on the SERVER whenever a state changes (see the ready method below). It is
--      written against the real engine signature but left UNCALLED until it is
--      verified in-game (a wrong diffIndex/ratio destabilises a driveline — must
--      be felt on the Thüringen dedicated before it ships).
-- See docs/INGAME_PHYSICS_PLAN.md.
--

DrivetrainModule = IronHorseModule.new("drivetrain")

DrivetrainModule.MODE_2WD = 0
DrivetrainModule.MODE_4WD = 1
DrivetrainModule.MODE_FWD = 2

DrivetrainModule.CFG = {
    -- engine-mechanic constants (from the GIANTS updateDifferential contract, not
    -- real-world data → they live here, not in IronHorseRealData)
    LOCKED_MAXSPEED     = 1,           -- locked diff: axle sides bound to one speed
    OPEN_MAXSPEED_MULT  = 1000,        -- open diff: base maxSpeedRatio * this = free
    TWO_WD_TORQUE       = -0.00001,    -- centre diff torque ratio that yields 2WD
    FWD_MAXSPEED        = 0,           -- centre diff maxSpeedRatio for FWD

    DEFAULT_TORQUE_RATIO   = 0.5,      -- fallback when a vehicle's diff is unreadable
    DEFAULT_MAXSPEED_RATIO = 1.0,

    LOCK_WARN_SPEED_KMH = 12,          -- locked diff above this = scrub warning
}

---Pure: the maxSpeedRatio to feed updateDifferential for an AXLE diff (front or
-- rear). Locked binds the two sides to one speed; open lets the base ratio run
-- free (scaled up so the engine treats it as unlocked).
-- @param boolean locked whether this axle diff is locked
-- @return number maxSpeedRatio
function DrivetrainModule.axleMaxSpeedRatio(locked, baseMaxSpeedRatio, cfg)
    if locked then
        return cfg.LOCKED_MAXSPEED
    end
    return (baseMaxSpeedRatio or cfg.DEFAULT_MAXSPEED_RATIO) * cfg.OPEN_MAXSPEED_MULT
end

---Pure: the (torqueRatio, maxSpeedRatio) to feed the CENTRE diff for a drive
-- mode. 2WD cuts front drive, 4WD uses the base split, FWD forces front only.
-- @return number torqueRatio, number maxSpeedRatio
function DrivetrainModule.resolveDriveMode(mode, baseCentreTorqueRatio, cfg)
    if mode == DrivetrainModule.MODE_2WD then
        return cfg.TWO_WD_TORQUE, 1
    elseif mode == DrivetrainModule.MODE_FWD then
        return 1, cfg.FWD_MAXSPEED
    end
    -- MODE_4WD (and any unknown value → safe default)
    return (baseCentreTorqueRatio or cfg.DEFAULT_TORQUE_RATIO), 1
end

---Pure: front/rear power split (percent) for the HUD readout. torqueRatio ~ the
-- share going to the front group. @return number frontPct, number rearPct
function DrivetrainModule.powerSplit(centreTorqueRatio, mode)
    if mode == DrivetrainModule.MODE_2WD then
        return 0, 100
    elseif mode == DrivetrainModule.MODE_FWD then
        return 100, 0
    end
    local r = centreTorqueRatio or 0.5
    if r < 0 then r = 0 elseif r > 1 then r = 1 end
    local front = math.floor(r * 100 + 0.5)
    return front, 100 - front
end

---Pure: HUD severity for a diff. A diff locked while moving faster than the
-- scrub threshold warns (tyre scrub / driveline stress on hard ground).
-- @param boolean locked  @param number speedKmh  @return number severity
function DrivetrainModule.diffSeverity(locked, speedKmh, cfg)
    if locked and (speedKmh or 0) > cfg.LOCK_WARN_SPEED_KMH then
        return IronHorseHud.SEV_WARNING
    end
    return IronHorseHud.SEV_INFO
end

---READY LEVER (deferred, server-side): push the current diff/mode state into the
-- driveline via the engine. UNCALLED until verified in-game — see the header TODO.
-- Guarded so it is a safe no-op headless / where the engine call is absent.
function DrivetrainModule.applyDifferentials(vehicle, state, cfg)
    if updateDifferential == nil or vehicle == nil or vehicle.rootNode == nil then
        return
    end
    cfg = cfg or DrivetrainModule.CFG
    local base = state.base or {}
    -- front axle (index 0) and rear axle (index 1): torque ratio unchanged, only
    -- the lock (maxSpeedRatio) toggles.
    updateDifferential(vehicle.rootNode, 0,
        base.frontTorque or cfg.DEFAULT_TORQUE_RATIO,
        DrivetrainModule.axleMaxSpeedRatio(state.frontLocked == 1, base.frontMaxSpeed, cfg))
    updateDifferential(vehicle.rootNode, 1,
        base.rearTorque or cfg.DEFAULT_TORQUE_RATIO,
        DrivetrainModule.axleMaxSpeedRatio(state.rearLocked == 1, base.rearMaxSpeed, cfg))
    -- centre diff (index 2): drive mode
    local tr, msr = DrivetrainModule.resolveDriveMode(state.driveMode, base.centreTorque, cfg)
    updateDifferential(vehicle.rootNode, 2, tr, msr)
end

---Read a vehicle's factory diff ratios so the open/locked math uses real
-- per-vehicle values. Runs on load for every peer (the result is deterministic
-- from the vehicle's static differential config); state.base is consumed only by
-- the deferred, server-side applyDifferentials and is never synced or saved.
function DrivetrainModule.readBaseRatios(vehicle, cfg)
    local base = {
        frontTorque = cfg.DEFAULT_TORQUE_RATIO, frontMaxSpeed = cfg.DEFAULT_MAXSPEED_RATIO,
        rearTorque  = cfg.DEFAULT_TORQUE_RATIO, rearMaxSpeed  = cfg.DEFAULT_MAXSPEED_RATIO,
        centreTorque = cfg.DEFAULT_TORQUE_RATIO,
    }
    local spec = vehicle ~= nil and vehicle.spec_motorized or nil
    if spec ~= nil and spec.differentials ~= nil then
        for _, d in ipairs(spec.differentials) do
            if d.diffIndex1 == 1 then
                base.frontTorque, base.frontMaxSpeed = d.torqueRatio, d.maxSpeedRatio
            elseif d.diffIndex1 == 3 then
                base.rearTorque, base.rearMaxSpeed = d.torqueRatio, d.maxSpeedRatio
            elseif d.diffIndex1 == 0 and d.diffIndex1IsWheel == false then
                base.centreTorque = d.torqueRatio
            end
        end
    end
    return base
end

function DrivetrainModule:isSupported(vehicle)
    return vehicle ~= nil and vehicle.spec_motorized ~= nil
end

function DrivetrainModule:onLoad(vehicle, state, _savegame)
    state.frontLocked = 0
    state.rearLocked = 0
    state.driveMode = DrivetrainModule.MODE_4WD
    state.base = DrivetrainModule.readBaseRatios(vehicle, DrivetrainModule.CFG)
    -- last-synced snapshot so live sync only fires on a real change
    state.syncedFront = nil
    state.syncedRear = nil
    state.syncedMode = nil
end

function DrivetrainModule:onUpdate(vehicle, state, _dt, isServer)
    if not IronHorseConfig.isModuleEnabled(self.name) then
        return
    end
    if not isServer then
        return   -- authoritative on the server; clients get the state via sync
    end

    -- The state only changes via a (deferred) input toggle, so there is nothing
    -- to integrate here yet. When input lands, the toggle sets the state and this
    -- block replicates it + (once verified) calls applyDifferentials. Kept as the
    -- sync seam so a change is broadcast the moment a toggle exists.
    if state.frontLocked ~= state.syncedFront then
        state.syncedFront = state.frontLocked
        IronHorseSyncEvent.send(vehicle, self.name, "frontLocked", state.frontLocked)
    end
    if state.rearLocked ~= state.syncedRear then
        state.syncedRear = state.rearLocked
        IronHorseSyncEvent.send(vehicle, self.name, "rearLocked", state.rearLocked)
    end
    if state.driveMode ~= state.syncedMode then
        state.syncedMode = state.driveMode
        IronHorseSyncEvent.send(vehicle, self.name, "driveMode", state.driveMode)
    end
end

---Initial MP sync: joining client gets the two locks + the drive mode. Symmetric:
-- two bools + a 2-bit uint (mode 0..2). Locks travel as bool here but are kept as
-- 0/1 numbers in state (see the file header on the float-sync truthiness trap).
function DrivetrainModule:onWriteStream(_vehicle, state, streamId, _connection)
    streamWriteBool(streamId, state.frontLocked == 1)
    streamWriteBool(streamId, state.rearLocked == 1)
    streamWriteUIntN(streamId, state.driveMode or DrivetrainModule.MODE_4WD, 2)
end

function DrivetrainModule:onReadStream(_vehicle, state, streamId, _connection)
    state.frontLocked = streamReadBool(streamId) and 1 or 0
    state.rearLocked = streamReadBool(streamId) and 1 or 0
    state.driveMode = streamReadUIntN(streamId, 2)
end

function DrivetrainModule:saveToXML(_vehicle, state, xmlFile, key)
    xmlFile:setValue(key .. "#frontLocked", state.frontLocked == 1)
    xmlFile:setValue(key .. "#rearLocked", state.rearLocked == 1)
    xmlFile:setValue(key .. "#driveMode", state.driveMode or DrivetrainModule.MODE_4WD)
end

function DrivetrainModule:loadFromXML(_vehicle, state, xmlFile, key)
    state.frontLocked = xmlFile:getValue(key .. "#frontLocked", false) and 1 or 0
    state.rearLocked = xmlFile:getValue(key .. "#rearLocked", false) and 1 or 0
    state.driveMode = xmlFile:getValue(key .. "#driveMode", DrivetrainModule.MODE_4WD)
end

local MODE_LABEL = { [0] = "2WD", [1] = "4WD", [2] = "FWD" }

function DrivetrainModule:getHudIndicators(vehicle, state)
    if not IronHorseConfig.isModuleEnabled(self.name) then
        return nil
    end
    local cfg = DrivetrainModule.CFG
    local speedKmh = (vehicle ~= nil and vehicle.getLastSpeed ~= nil and vehicle:getLastSpeed()) or 0
    return {
        {
            id = "diffFront", label = "DIFF V",
            value = (state.frontLocked == 1) and "SPERR" or "OFFEN",
            severity = DrivetrainModule.diffSeverity(state.frontLocked == 1, speedKmh, cfg),
        },
        {
            id = "diffRear", label = "DIFF H",
            value = (state.rearLocked == 1) and "SPERR" or "OFFEN",
            severity = DrivetrainModule.diffSeverity(state.rearLocked == 1, speedKmh, cfg),
        },
        {
            id = "driveMode", label = "ANTRIEB",
            value = MODE_LABEL[state.driveMode] or "4WD",
            severity = IronHorseHud.SEV_INFO,
        },
    }
end
