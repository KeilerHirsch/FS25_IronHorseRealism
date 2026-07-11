--
-- IronHorseRealData
--
-- SINGLE source of real-world values. Design principle: every number the mod
-- uses comes from real manufacturer / engineering data, not invented. Modules
-- read from here; they never hardcode magic numbers.
--
-- Baselines below are grounded in real automotive/agricultural data (and
-- cross-checked against what ADS already ships, which itself is realistic).
-- Verify per-vehicle specifics against manufacturer spec sheets over time.
--

IronHorseRealData = {}

-- 12 V lead-acid starter battery (typical agricultural tractor).
IronHorseRealData.battery = {
    nominalCapacityAh = 150,      -- common heavy-tractor battery
    crankCurrentA = 250,          -- starter draw
    chargeTargetV = 14.4,         -- alternator regulated charge voltage
    terminalMinV = 8.5,
    terminalMaxV = 14.8,
    loadedMinV = 12.2,            -- healthy loaded resting voltage
    chargeAcceptTempMinC = -15,
    chargeAcceptTempMaxC = 25,
}

-- Diesel engine thermal envelope (deg C).
IronHorseRealData.engine = {
    coldBelowC = 50,              -- below this: cold-operation penalty
    normalOperatingC = 90,        -- typical coolant operating temperature
    overheatAboveC = 105,         -- real coolant boil/overheat region
}

-- Radial ag-tire pressure envelope (bar). Real field vs road pressures.
IronHorseRealData.tire = {
    fieldPressureBar = 0.8,       -- low pressure, large contact patch (traction)
    roadPressureBar = 1.6,        -- higher pressure, road efficiency
    minPressureBar = 0.6,
    maxPressureBar = 2.4,
}

---Helper: linear interpolation, clamped to [a, b].
-- @return number
function IronHorseRealData.lerp(a, b, t)
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    return a + (b - a) * t
end
