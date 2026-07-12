--
-- TireModule ("tyre pressure & traction")
--
-- Fifth feature module, second of the PHYSICS layer, and the bottom of the
-- driveline chain (engine → drivetrain → TYRES → ground). Models radial ag-tyre
-- pressure per axle and the traction it buys: low pressure enlarges the contact
-- patch for grip in the field, high pressure cuts rolling resistance for the road
-- but loses soil grip. Front and rear pressures are tracked separately.
--
-- Authoritative on the SERVER; the two axle pressures are replicated to clients
-- (initial stream on join + throttled sync on a real change) so the cockpit HUD
-- reads right on a dedicated server, and they PERSIST across saves.
--
-- MECHANIC PROVENANCE (§ 69a UrhG: mechanics are not protected — clean-room, no
-- third-party code): the pressure→traction idea is the same one VariableTire-
-- Pressure exposes, but VTP is "all rights reserved" and was NOT read for code —
-- only the public mechanic (pressure interpolates a friction/footprint multiplier)
-- is reused, and the NUMBERS come from real ag-tyre tractive-efficiency data
-- (Michelin/Trelleborg field-vs-road charts) held in IronHorseRealData.tire, not
-- from any mod. A permissive-code search (MIT/BSD/…) found nothing that fits this
-- axis (the Pacejka libraries model lateral slip, a different thing), so the pure
-- curve is hand-rolled on real data — see reuse-first-permissive skill.
--
-- IN-GAME / FINE-TUNING TODO (deferred — the physics-hook part, needs the maintainer's
-- dedicated-server test, NOT wired yet):
--   1. INPUT — inflate / deflate actions (optionally consuming an AIR reserve like
--      the vanilla air fillUnit). Until then pressure holds its default, so the
--      module is a correct read-out that does not yet change grip = inert-but-safe.
--   2. PHYSICS APPLY — overwrite WheelPhysics.updateTireFriction (Utils.overwritten-
--      Function) to scale the wheel's friction by TireModule.pressureToTraction of
--      that wheel's axle pressure. This is a GLOBAL class override that must be
--      written against the real in-game signature and felt on the dedicated before
--      it ships → it lives in the plan, not in this file, on purpose.
-- See docs/INGAME_PHYSICS_PLAN.md.
--

TireModule = IronHorseModule.new("tire")

local TIRE = IronHorseRealData.tire

TireModule.CFG = {
    MIN_BAR   = TIRE.minPressureBar,          -- 0.6
    MAX_BAR   = TIRE.maxPressureBar,          -- 2.4
    FIELD_BAR = TIRE.fieldPressureBar,        -- 0.8 (default = field)
    ROAD_BAR  = TIRE.roadPressureBar,         -- 1.6

    TRACTION_AT_MIN = TIRE.tractionAtMinPressure,  -- 1.20 grip at 0.6 bar
    TRACTION_AT_MAX = TIRE.tractionAtMaxPressure,  -- 0.92 grip at 2.4 bar
    PATCH_AT_MIN    = TIRE.patchAtMinPressure,     -- 1.30 footprint at 0.6 bar
    PATCH_AT_MAX    = TIRE.patchAtMaxPressure,     -- 0.85 footprint at 2.4 bar

    LOW_PRESSURE_WARN   = 0.9,     -- below this at road speed = tyre overheat risk
    ROAD_SPEED_WARN     = 25,      -- km/h
    PRESSURE_SYNC_DELTA = 0.05,    -- bar → throttled sync
}

---Pure: axle pressure (bar) → traction multiplier. Monotonically DECREASING —
-- lower pressure means a bigger footprint and more grip on soil. Interpolates the
-- real-data endpoints; the shared lerp clamps out-of-range pressure. @return number
function TireModule.pressureToTraction(pressureBar, cfg)
    local t = (pressureBar - cfg.MIN_BAR) / (cfg.MAX_BAR - cfg.MIN_BAR)
    return IronHorseRealData.lerp(cfg.TRACTION_AT_MIN, cfg.TRACTION_AT_MAX, t)
end

---Pure: axle pressure (bar) → relative contact-patch area (same interpolation,
-- larger at low pressure). @return number
function TireModule.contactPatch(pressureBar, cfg)
    local t = (pressureBar - cfg.MIN_BAR) / (cfg.MAX_BAR - cfg.MIN_BAR)
    return IronHorseRealData.lerp(cfg.PATCH_AT_MIN, cfg.PATCH_AT_MAX, t)
end

---Pure: HUD severity. Running soft tyres at road speed risks overheating them →
-- warn. @param number pressureBar @param number speedKmh @return number severity
function TireModule.tireSeverity(pressureBar, speedKmh, cfg)
    if pressureBar < cfg.LOW_PRESSURE_WARN and (speedKmh or 0) > cfg.ROAD_SPEED_WARN then
        return IronHorseHud.SEV_WARNING
    end
    return IronHorseHud.SEV_INFO
end

function TireModule:isSupported(vehicle)
    return vehicle ~= nil and vehicle.spec_wheels ~= nil
end

function TireModule:onLoad(_vehicle, state, _savegame)
    state.pressureFront = TireModule.CFG.FIELD_BAR
    state.pressureRear = TireModule.CFG.FIELD_BAR
    state.syncedFront = nil
    state.syncedRear = nil
end

function TireModule:onUpdate(vehicle, state, _dt, isServer)
    if not IronHorseConfig.isModuleEnabled(self.name) then
        return
    end
    if not isServer then
        return   -- authoritative on the server; clients get pressures via sync
    end

    -- Pressure only changes via the (deferred) inflate/deflate input, so there is
    -- nothing to integrate yet. This is the throttled sync seam: the moment input
    -- lands and changes a pressure, the change replicates on a real delta.
    if math.abs(state.pressureFront - (state.syncedFront or -1000)) >= TireModule.CFG.PRESSURE_SYNC_DELTA then
        state.syncedFront = state.pressureFront
        IronHorseSyncEvent.send(vehicle, self.name, "pressureFront", state.pressureFront)
    end
    if math.abs(state.pressureRear - (state.syncedRear or -1000)) >= TireModule.CFG.PRESSURE_SYNC_DELTA then
        state.syncedRear = state.pressureRear
        IronHorseSyncEvent.send(vehicle, self.name, "pressureRear", state.pressureRear)
    end
end

---Initial MP sync: joining client gets both axle pressures. Symmetric: two float32.
function TireModule:onWriteStream(_vehicle, state, streamId, _connection)
    streamWriteFloat32(streamId, state.pressureFront or TireModule.CFG.FIELD_BAR)
    streamWriteFloat32(streamId, state.pressureRear or TireModule.CFG.FIELD_BAR)
end

function TireModule:onReadStream(_vehicle, state, streamId, _connection)
    state.pressureFront = streamReadFloat32(streamId)
    state.pressureRear = streamReadFloat32(streamId)
end

function TireModule:saveToXML(_vehicle, state, xmlFile, key)
    xmlFile:setValue(key .. "#pressureFront", state.pressureFront or TireModule.CFG.FIELD_BAR)
    xmlFile:setValue(key .. "#pressureRear", state.pressureRear or TireModule.CFG.FIELD_BAR)
end

function TireModule:loadFromXML(_vehicle, state, xmlFile, key)
    state.pressureFront = xmlFile:getValue(key .. "#pressureFront", TireModule.CFG.FIELD_BAR)
    state.pressureRear = xmlFile:getValue(key .. "#pressureRear", TireModule.CFG.FIELD_BAR)
end

---One tyre chip: pressure + the grip % it buys, coloured by severity.
local function tireChip(id, label, pressureBar, speedKmh, cfg)
    local gripPct = math.floor(TireModule.pressureToTraction(pressureBar, cfg) * 100 + 0.5)
    return {
        id = id, label = label,
        value = string.format("%.1fbar %d%%", pressureBar, gripPct),
        severity = TireModule.tireSeverity(pressureBar, speedKmh, cfg),
    }
end

function TireModule:getHudIndicators(vehicle, state)
    if not IronHorseConfig.isModuleEnabled(self.name) then
        return nil
    end
    local cfg = TireModule.CFG
    local speedKmh = (vehicle ~= nil and vehicle.getLastSpeed ~= nil and vehicle:getLastSpeed()) or 0
    return {
        tireChip("tireFront", "REIFEN V", state.pressureFront or cfg.FIELD_BAR, speedKmh, cfg),
        tireChip("tireRear", "REIFEN H", state.pressureRear or cfg.FIELD_BAR, speedKmh, cfg),
    }
end
