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
    dofile("scripts/core/IronHorseModule.lua")
    dofile("scripts/core/IronHorseModuleRegistry.lua")
    dofile("scripts/core/IronHorseRealData.lua")
    dofile("scripts/modules/EngineStallModule.lua")
end

describe("EngineStallModule.updateOverload (pure integrator)", function()
    loadCore()
    local CFG = _G.EngineStallModule.CFG

    it("stalls after sustained full overload", function()
        local acc, stall = _G.EngineStallModule.updateOverload(0, 1.0, 0.8, 2500, CFG)
        assert.is_true(acc >= 1.0)
        assert.is_true(stall)
    end)

    it("does not stall on a short overload burst", function()
        local acc, stall = _G.EngineStallModule.updateOverload(0, 1.0, 0.8, 1000, CFG)
        assert.is_true(acc < 1.0)
        assert.is_false(stall)
    end)

    it("lugging (low rpm + high load) stalls faster than plain overload", function()
        local accLug = _G.EngineStallModule.updateOverload(0, 0.9, 0.2, 1500, CFG)
        local accOvl = _G.EngineStallModule.updateOverload(0, 0.9, 0.8, 1500, CFG)
        -- at load 0.9 (< OVERLOAD_LOAD) only the lugging case accumulates
        assert.is_true(accLug > accOvl)
    end)

    it("bleeds off and clamps at zero when load drops", function()
        local acc, stall = _G.EngineStallModule.updateOverload(0.5, 0.5, 0.8, 5000, CFG)
        assert.are.equal(0, acc)
        assert.is_false(stall)
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
