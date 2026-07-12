--
-- Unit tests for FS25_IronHorseRealism core (busted).
-- Run from the mod root with a Lua 5.1 / LuaJIT environment: busted
--
-- Engine globals are stubbed; only pure/core logic is exercised (the in-game
-- integration is verified in-game, since FS25 cannot run headless).
--

local function loadCore()
    _G.Logging = { info = function() end, warning = function() end }
    _G.IronHorseModule = nil
    _G.IronHorseModuleRegistry = nil
    _G.EngineStallModule = nil
    _G.IronHorseRealData = nil
    _G.IronHorseHud = nil
    _G.EngineHealthModule = nil
    dofile("scripts/core/IronHorseModule.lua")
    dofile("scripts/core/IronHorseModuleRegistry.lua")
    dofile("scripts/core/IronHorseRealData.lua")
    dofile("scripts/hud/IronHorseHud.lua")            -- severity constants used below
    dofile("scripts/modules/EngineStallModule.lua")
    dofile("scripts/modules/EngineHealthModule.lua")
end

describe("EngineStallModule.updateOverload (two-phase integrator)", function()
    loadCore()
    local ESM = _G.EngineStallModule
    local CFG = ESM.CFG

    it("exposes phase as a compact numeric enum (network-serialisable, 2-bit)", function()
        -- The MP sync (initial onWriteStream + live event) writes phase as a
        -- 2-bit uint, so the constants MUST be distinct numbers in 0..3.
        assert.are.equal("number", type(ESM.PHASE_NONE))
        assert.are.equal("number", type(ESM.PHASE_STRUGGLE))
        assert.are.equal("number", type(ESM.PHASE_STALL))
        assert.is_true(ESM.PHASE_NONE ~= ESM.PHASE_STRUGGLE)
        assert.is_true(ESM.PHASE_STRUGGLE ~= ESM.PHASE_STALL)
        assert.is_true(ESM.PHASE_NONE ~= ESM.PHASE_STALL)
        assert.is_true(ESM.PHASE_STALL >= 0 and ESM.PHASE_STALL <= 3)
    end)

    it("stalls only after the full stall window of sustained overload", function()
        local acc, phase = ESM.updateOverload(0, 1.0, 0.8, 4.0, CFG)
        assert.is_true(acc >= CFG.STALL_SECONDS)
        assert.are.equal(ESM.PHASE_STALL, phase)
    end)

    it("struggles (audible labor) before it stalls", function()
        local _, phase = ESM.updateOverload(0, 1.0, 0.8, 2.0, CFG)
        assert.are.equal(ESM.PHASE_STRUGGLE, phase) -- past STRUGGLE_SECONDS, before STALL_SECONDS
    end)

    it("no phase yet on a short overload burst", function()
        local _, phase = ESM.updateOverload(0, 1.0, 0.8, 1.0, CFG)
        assert.are.equal(ESM.PHASE_NONE, phase)
    end)

    it("lugging (low rpm + high load) fills faster than plain sub-overload", function()
        -- load 0.88 < OVERLOAD_LOAD (0.90): only the lugging case accumulates
        local accLug = ESM.updateOverload(0, 0.88, 0.2, 1.5, CFG)
        local accOvl = ESM.updateOverload(0, 0.88, 0.8, 1.5, CFG)
        assert.is_true(accLug > accOvl)
        assert.are.equal(0, accOvl)
    end)

    it("bleeds off and clamps at zero when load drops", function()
        local acc, phase = ESM.updateOverload(2.0, 0.5, 0.8, 5.0, CFG)
        assert.are.equal(0, acc)
        assert.are.equal(ESM.PHASE_NONE, phase)
    end)
end)

describe("IronHorseModuleRegistry", function()
    it("registers, dedupes by name, and lists in order", function()
        loadCore()
        local reg = _G.IronHorseModuleRegistry
        reg.modules = {}
        reg.byName = {}
        local a = _G.IronHorseModule.new("a")
        local b = _G.IronHorseModule.new("b")
        reg.register(a)
        reg.register(b)
        reg.register(a) -- duplicate ignored
        assert.are.equal(2, #reg.getModules())
        assert.are.equal("a", reg.getModules()[1].name)
    end)

    it("getSupported filters by module isSupported", function()
        loadCore()
        local reg = _G.IronHorseModuleRegistry
        reg.modules = {}
        reg.byName = {}
        local yes = _G.IronHorseModule.new("yes")
        local no = _G.IronHorseModule.new("no")
        function no:isSupported() return false end
        reg.register(yes)
        reg.register(no)
        local supported = reg.getSupported({})
        assert.are.equal(1, #supported)
        assert.are.equal("yes", supported[1].name)
    end)
end)

describe("IronHorseRealData.lerp", function()
    loadCore()
    it("interpolates and clamps", function()
        assert.are.equal(0.8, _G.IronHorseRealData.lerp(0.8, 1.6, 0))
        assert.are.equal(1.6, _G.IronHorseRealData.lerp(0.8, 1.6, 1))
        assert.are.equal(1.2, _G.IronHorseRealData.lerp(0.8, 1.6, 0.5))
        assert.are.equal(0.8, _G.IronHorseRealData.lerp(0.8, 1.6, -5)) -- clamp low
        assert.are.equal(1.6, _G.IronHorseRealData.lerp(0.8, 1.6, 5))  -- clamp high
    end)
end)

describe("EngineStallModule.indicatorSeverity (pure HUD severity mapping)", function()
    loadCore()
    local ESM = _G.EngineStallModule
    local HUD = _G.IronHorseHud
    local CFG = ESM.CFG

    it("struggle phase maps to CRITICAL (engine dying)", function()
        assert.are.equal(HUD.SEV_CRITICAL, ESM.indicatorSeverity(ESM.PHASE_STRUGGLE, 0.5, CFG))
    end)

    it("stall phase maps to CRITICAL even at low load", function()
        assert.are.equal(HUD.SEV_CRITICAL, ESM.indicatorSeverity(ESM.PHASE_STALL, 0.1, CFG))
    end)

    it("heavy load without struggle maps to WARNING", function()
        assert.are.equal(HUD.SEV_WARNING, ESM.indicatorSeverity(ESM.PHASE_NONE, CFG.HUD_WARN_LOAD, CFG))
    end)

    it("normal load maps to INFO", function()
        assert.are.equal(HUD.SEV_INFO, ESM.indicatorSeverity(ESM.PHASE_NONE, 0.2, CFG))
    end)
end)

describe("EngineHealthModule (pure thermal + wear)", function()
    loadCore()
    local EHM = _G.EngineHealthModule
    local HUD = _G.IronHorseHud
    local CFG = EHM.CFG

    it("warms toward a load target while running", function()
        assert.is_true(EHM.updateTemperature(20, 1.0, 20, 10, CFG, true) > 20)
    end)

    it("cools to ambient when off and never below it", function()
        local t = 90
        for _ = 1, 20000 do t = EHM.updateTemperature(t, 0, 15, 1, CFG, false) end
        assert.is_true(math.abs(t - 15) < 1e-6)
        assert.is_true(EHM.updateTemperature(15, 0, 15, 5, CFG, false) >= 15)
    end)

    it("overheating wears condition faster than baseline running", function()
        local cBase = EHM.updateCondition(1.0, 90, 0.3, 3600, CFG)
        local cHot = EHM.updateCondition(1.0, 120, 0.3, 3600, CFG)
        assert.is_true(cBase < 1.0)
        assert.is_true(cHot < cBase)
    end)

    it("condition clamps at zero", function()
        assert.are.equal(0, EHM.updateCondition(0.001, 120, 1.0, 3600 * 100, CFG))
    end)

    it("temperature severity bands", function()
        assert.are.equal(HUD.SEV_CRITICAL, EHM.tempSeverity(120, CFG))
        assert.are.equal(HUD.SEV_WARNING, EHM.tempSeverity(102, CFG))
        assert.are.equal(HUD.SEV_COOL, EHM.tempSeverity(30, CFG))
        assert.are.equal(HUD.SEV_INFO, EHM.tempSeverity(85, CFG))
    end)

    it("condition severity bands", function()
        assert.are.equal(HUD.SEV_CRITICAL, EHM.conditionSeverity(0.1, CFG))
        assert.are.equal(HUD.SEV_WARNING, EHM.conditionSeverity(0.4, CFG))
        assert.are.equal(HUD.SEV_INFO, EHM.conditionSeverity(0.9, CFG))
    end)
end)
