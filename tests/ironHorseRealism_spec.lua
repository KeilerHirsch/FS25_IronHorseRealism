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
    _G.DrivetrainModule = nil
    _G.TireModule = nil
    _G.ElectricalModule = nil
    _G.VisualDirtModule = nil
    _G.ToolboxModule = nil
    dofile("scripts/core/IronHorseModule.lua")
    dofile("scripts/core/IronHorseModuleRegistry.lua")
    dofile("scripts/core/IronHorseRealData.lua")
    dofile("scripts/hud/IronHorseHud.lua")            -- severity constants used below
    dofile("scripts/modules/EngineStallModule.lua")
    dofile("scripts/modules/EngineHealthModule.lua")
    dofile("scripts/modules/DrivetrainModule.lua")
    dofile("scripts/modules/TireModule.lua")
    dofile("scripts/modules/ElectricalModule.lua")
    dofile("scripts/modules/VisualDirtModule.lua")
    dofile("scripts/modules/ToolboxModule.lua")
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

describe("ElectricalModule (pure battery model)", function()
    loadCore()
    local ELM = _G.ElectricalModule
    local HUD = _G.IronHorseHud
    local CFG = ELM.CFG

    it("charges while running, drains while off, clamps 0..1", function()
        assert.is_true(ELM.updateSOC(0.5, true, 3600, CFG) > 0.5)
        assert.is_true(ELM.updateSOC(0.5, false, 3600, CFG) < 0.5)
        assert.are.equal(1, ELM.updateSOC(1.0, true, 3600 * 100, CFG))
        assert.are.equal(0, ELM.updateSOC(0.0, false, 3600 * 100, CFG))
    end)

    it("voltage: regulated while running, tracks SOC at rest", function()
        assert.are.equal(CFG.CHARGE_TARGET_V, ELM.terminalVoltage(0.5, true, CFG))
        assert.are.equal(CFG.RESTING_EMPTY_V, ELM.terminalVoltage(0.0, false, CFG))
        assert.is_true(math.abs(ELM.terminalVoltage(1.0, false, CFG) - CFG.RESTING_FULL_V) < 1e-6)
        assert.is_true(ELM.terminalVoltage(1.0, false, CFG) > ELM.terminalVoltage(0.3, false, CFG))
    end)

    it("SOC severity bands", function()
        assert.are.equal(HUD.SEV_CRITICAL, ELM.socSeverity(0.1, CFG))
        assert.are.equal(HUD.SEV_WARNING, ELM.socSeverity(0.35, CFG))
        assert.are.equal(HUD.SEV_INFO, ELM.socSeverity(0.9, CFG))
    end)
end)

describe("DrivetrainModule (pure diff resolution + power split)", function()
    loadCore()
    local DTM = _G.DrivetrainModule
    local HUD = _G.IronHorseHud
    local CFG = DTM.CFG

    it("axle diff: locked binds the axle, open runs the base ratio free", function()
        assert.are.equal(CFG.LOCKED_MAXSPEED, DTM.axleMaxSpeedRatio(true, 1.0, CFG))
        assert.are.equal(1.0 * CFG.OPEN_MAXSPEED_MULT, DTM.axleMaxSpeedRatio(false, 1.0, CFG))
        assert.are.equal(0.5 * CFG.OPEN_MAXSPEED_MULT, DTM.axleMaxSpeedRatio(false, 0.5, CFG))
        assert.are.equal(CFG.DEFAULT_MAXSPEED_RATIO * CFG.OPEN_MAXSPEED_MULT, DTM.axleMaxSpeedRatio(false, nil, CFG))
    end)

    it("drive mode resolves centre torque + maxSpeed", function()
        local tr4, msr4 = DTM.resolveDriveMode(DTM.MODE_4WD, 0.5, CFG)
        assert.are.equal(0.5, tr4); assert.are.equal(1, msr4)
        local tr2, msr2 = DTM.resolveDriveMode(DTM.MODE_2WD, 0.5, CFG)
        assert.are.equal(CFG.TWO_WD_TORQUE, tr2); assert.are.equal(1, msr2)
        local trf, msrf = DTM.resolveDriveMode(DTM.MODE_FWD, 0.5, CFG)
        assert.are.equal(1, trf); assert.are.equal(CFG.FWD_MAXSPEED, msrf)
        assert.are.equal(0.5, (DTM.resolveDriveMode(99, 0.5, CFG))) -- unknown -> 4WD default
    end)

    it("power split in percent, clamped", function()
        local f, r = DTM.powerSplit(0.5, DTM.MODE_4WD)
        assert.are.equal(50, f); assert.are.equal(50, r)
        assert.are.equal(60, (DTM.powerSplit(0.6, DTM.MODE_4WD)))
        assert.are.equal(0, (DTM.powerSplit(0.5, DTM.MODE_2WD)))
        assert.are.equal(100, (DTM.powerSplit(0.5, DTM.MODE_FWD)))
        assert.are.equal(100, (DTM.powerSplit(1.5, DTM.MODE_4WD))) -- clamp >1
    end)

    it("diff severity: locked at speed warns of scrub", function()
        assert.are.equal(HUD.SEV_WARNING, DTM.diffSeverity(true, 20, CFG))
        assert.are.equal(HUD.SEV_INFO, DTM.diffSeverity(true, 5, CFG))
        assert.are.equal(HUD.SEV_INFO, DTM.diffSeverity(false, 20, CFG))
    end)
end)

describe("TireModule (pure pressure -> traction / patch)", function()
    loadCore()
    local TM = _G.TireModule
    local HUD = _G.IronHorseHud
    local CFG = TM.CFG

    it("traction decreases monotonically with pressure, endpoints match data", function()
        assert.is_true(math.abs(TM.pressureToTraction(CFG.MIN_BAR, CFG) - CFG.TRACTION_AT_MIN) < 1e-9)
        assert.is_true(math.abs(TM.pressureToTraction(CFG.MAX_BAR, CFG) - CFG.TRACTION_AT_MAX) < 1e-9)
        assert.is_true(TM.pressureToTraction(0.8, CFG) > TM.pressureToTraction(1.6, CFG))
    end)

    it("traction clamps outside the pressure envelope", function()
        assert.is_true(math.abs(TM.pressureToTraction(0.1, CFG) - CFG.TRACTION_AT_MIN) < 1e-9)
        assert.is_true(math.abs(TM.pressureToTraction(9.9, CFG) - CFG.TRACTION_AT_MAX) < 1e-9)
    end)

    it("contact patch is larger at low pressure", function()
        assert.is_true(math.abs(TM.contactPatch(CFG.MIN_BAR, CFG) - CFG.PATCH_AT_MIN) < 1e-9)
        assert.is_true(math.abs(TM.contactPatch(CFG.MAX_BAR, CFG) - CFG.PATCH_AT_MAX) < 1e-9)
        assert.is_true(TM.contactPatch(0.8, CFG) > TM.contactPatch(1.6, CFG))
    end)

    it("tyre severity: soft tyres at road speed warn", function()
        assert.are.equal(HUD.SEV_WARNING, TM.tireSeverity(0.6, 30, CFG))
        assert.are.equal(HUD.SEV_INFO, TM.tireSeverity(0.6, 5, CFG))
        assert.are.equal(HUD.SEV_INFO, TM.tireSeverity(1.6, 30, CFG))
    end)
end)

describe("VisualDirtModule (pure severity + accumulation rate)", function()
    loadCore()
    local VDM = _G.VisualDirtModule
    local HUD = _G.IronHorseHud
    local CFG = VDM.CFG

    it("only a filthy machine warns (dirt is cosmetic)", function()
        assert.are.equal(HUD.SEV_WARNING, VDM.dirtSeverity(0.9, CFG))
        assert.are.equal(HUD.SEV_INFO, VDM.dirtSeverity(0.5, CFG))
        assert.are.equal(HUD.SEV_INFO, VDM.dirtSeverity(0.0, CFG))
    end)

    it("accumulation rate: wet field = mud fastest, dry+moving = dust", function()
        assert.are.equal(CFG.WET_FIELD_SCALE, VDM.dirtRateScale(0.8, true, 8, CFG))
        assert.are.equal(CFG.DRY_DUST_SCALE, VDM.dirtRateScale(0.0, false, 20, CFG))
        assert.are.equal(CFG.BASE_SCALE, VDM.dirtRateScale(0.0, false, 1, CFG))
        assert.are.equal(CFG.BASE_SCALE, VDM.dirtRateScale(0.8, false, 1, CFG))
        assert.is_true(VDM.dirtRateScale(0.8, true, 8, CFG) > VDM.dirtRateScale(0.0, false, 20, CFG))
    end)
end)

describe("ToolboxModule (pure field-repair maths)", function()
    loadCore()
    local TBM = _G.ToolboxModule
    local HUD = _G.IronHorseHud
    local CFG = TBM.CFG

    it("field repair removes a chunk but is capped at the floor", function()
        assert.are.equal(0.9 - CFG.FIELD_REPAIR_AMOUNT, TBM.fieldRepairResult(0.9, CFG))
        assert.are.equal(CFG.FIELD_REPAIR_FLOOR, TBM.fieldRepairResult(0.3, CFG))
        assert.are.equal(0.05, TBM.fieldRepairResult(0.05, CFG)) -- never worsens
    end)

    it("availability + cost track the repaired fraction", function()
        assert.is_true(TBM.canFieldRepair(0.9, CFG))
        assert.is_false(TBM.canFieldRepair(0.05, CFG))
        assert.is_false(TBM.canFieldRepair(CFG.FIELD_REPAIR_FLOOR, CFG))
        local repaired = 0.9 - (0.9 - CFG.FIELD_REPAIR_AMOUNT)
        assert.is_true(math.abs(TBM.fieldRepairCost(0.9, 100000, CFG) - repaired * 100000 * CFG.FIELD_COST_FACTOR) < 1e-6)
        assert.are.equal(0, TBM.fieldRepairCost(0.05, 100000, CFG))
    end)

    it("damage severity bands", function()
        assert.are.equal(HUD.SEV_CRITICAL, TBM.repairSeverity(0.8, CFG))
        assert.are.equal(HUD.SEV_WARNING, TBM.repairSeverity(0.6, CFG))
        assert.are.equal(HUD.SEV_INFO, TBM.repairSeverity(0.2, CFG))
    end)
end)
