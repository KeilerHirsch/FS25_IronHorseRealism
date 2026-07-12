--
-- VisualDirtModule ("dirt & dust readout + realism rate")
--
-- Sixth feature module. Unlike the others it does NOT own or re-model its state:
-- Farming Simulator already has a complete, engine-synced dirt system (the
-- Washable specialization — getDirtAmount() 0..1, mud shader, rain washing, a
-- 90-minute default dirtDuration). Reinventing that would be exactly the wheel
-- this project refuses to reinvent, so this module REUSES the engine's dirt as
-- the source of truth: it reads getDirtAmount() for the cockpit HUD (a clean/
-- filthy cue) and adds the realism layer the vanilla system lacks — a condition-
-- based accumulation RATE (mud cakes on fast in the wet field, dust builds when
-- dry and moving) exposed as a pure, tested function.
--
-- Because the dirt value is engine-owned it is ALREADY replicated to every client
-- and saved by Washable, so this module needs no sync and no savegame of its own —
-- it just reads what the engine keeps. That makes it a pure reader + a modulation
-- lever, a deliberately thinner shape than the state-owning modules.
--
-- FINE-TUNING TODO (deferred, needs in-game feel — the realism CONSEQUENCE):
--   * apply dirtRateScale by nudging the engine dirt each tick on the SERVER
--     (self:addDirtAmount(dt * base * (scale-1)) style) so mud/dust build at
--     realistic rates instead of the flat vanilla duration;
--   * couple heavy dirt into cooling → engineHealth temperature (a clogged, caked
--     radiator runs hotter) = the chain's feedback loop (FUSION_RESEARCH §6.5).
--   Both change engine-synced state / cross-module behaviour → calibrate in-game.
--

VisualDirtModule = IronHorseModule.new("visualDirt")

VisualDirtModule.CFG = {
    DIRTY_WARN = 0.85,        -- filthy → WARNING (wash-me / cooling-impaired cue)

    -- realism rate modulation (gameplay constants, not manufacturer data → here,
    -- not in IronHorseRealData). Multipliers on the engine's own dirt rate.
    BASE_SCALE      = 1.0,
    WET_FIELD_SCALE = 2.0,    -- wet field work cakes mud on fast
    DRY_DUST_SCALE  = 1.4,    -- dry + moving kicks up dust
    RAIN_THRESHOLD  = 0.1,    -- rainScale above this counts as "wet"
    DUST_SPEED_KMH  = 5,      -- moving faster than this raises dust when dry
}

---Pure: dirt amount (0..1) → HUD severity. Dirt is cosmetic/maintenance, not an
-- alarm, so only a filthy machine warns (wash it / impaired cooling). @return number
function VisualDirtModule.dirtSeverity(dirtAmount, cfg)
    if (dirtAmount or 0) >= cfg.DIRTY_WARN then
        return IronHorseHud.SEV_WARNING
    end
    return IronHorseHud.SEV_INFO
end

---Pure: how fast dirt should accumulate for the current conditions, as a
-- multiplier on the engine's base rate. Wet field work = mud (fastest); dry and
-- moving = dust; otherwise the base rate. This is the realism layer the vanilla
-- flat dirtDuration lacks. @param number rainScale 0..1  @param boolean onField
-- @param number speedKmh  @return number scale
function VisualDirtModule.dirtRateScale(rainScale, onField, speedKmh, cfg)
    local wet = (rainScale or 0) > cfg.RAIN_THRESHOLD
    if wet and onField then
        return cfg.WET_FIELD_SCALE
    elseif not wet and (speedKmh or 0) > cfg.DUST_SPEED_KMH then
        return cfg.DRY_DUST_SCALE
    end
    return cfg.BASE_SCALE
end

function VisualDirtModule:isSupported(vehicle)
    return vehicle ~= nil and vehicle.getDirtAmount ~= nil
end

-- No onLoad / onUpdate / sync / save: the dirt value is owned, replicated and
-- persisted by the engine's Washable spec. This module only reads it. (The
-- deferred rate-modulation consequence will add a server-side onUpdate — see the
-- header TODO — but the first slice stays a pure reader.)

function VisualDirtModule:getHudIndicators(vehicle, _state)
    if not IronHorseConfig.isModuleEnabled(self.name) then
        return nil
    end
    local dirt = (vehicle ~= nil and vehicle.getDirtAmount ~= nil and vehicle:getDirtAmount()) or 0
    return {
        {
            id = "dirt",
            label = "SCHMUTZ",
            value = string.format("%d%%", math.floor(dirt * 100 + 0.5)),
            severity = VisualDirtModule.dirtSeverity(dirt, VisualDirtModule.CFG),
        },
    }
end
