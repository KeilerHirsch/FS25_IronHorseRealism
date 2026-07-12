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
    restingFullV = 12.7,          -- open-circuit voltage at 100% state of charge
    restingEmptyV = 11.8,         -- open-circuit voltage at ~0% state of charge
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
-- Traction/contact-patch multipliers are RELATIVE to a 1.0 baseline and grounded
-- in ag-tire tractive-efficiency behaviour (Michelin/Trelleborg field-vs-road
-- charts): dropping pressure enlarges the footprint and raises tractive
-- efficiency on soft soil (~+15-20 %), at the cost of road rolling efficiency;
-- raising pressure does the reverse. Endpoints are tied to min/max pressure so a
-- module interpolates between them.
IronHorseRealData.tire = {
    fieldPressureBar = 0.8,       -- low pressure, large contact patch (traction)
    roadPressureBar = 1.6,        -- higher pressure, road efficiency
    minPressureBar = 0.6,
    maxPressureBar = 2.4,

    tractionAtMinPressure = 1.20, -- 0.6 bar: max footprint -> best off-road grip
    tractionAtMaxPressure = 0.92, -- 2.4 bar: min footprint -> road, less soil grip
    patchAtMinPressure    = 1.30, -- relative contact-patch area at min pressure
    patchAtMaxPressure    = 0.85, -- ... and at max pressure
}

-- Vehicle repair economics (grounded in real workshop data, 2025). Sources:
-- German ag-machinery workshop rates €70-130/h (Deutz ~75, BayWa ~110, John Deere
-- >130 -> midpoint ~100; Verrechnungssaetze often >100 €/h); lifetime accumulated
-- repair cost ~= 25% of the machine's list price; annual maintenance/repair 5-10%
-- of value. A makeshift FIELD repair is cheaper than the workshop (own labour,
-- basic parts, no dealer margin) but only partial — the workshop does the full job.
IronHorseRealData.repair = {
    workshopLaborEURperH   = 100,   -- German ag-workshop midpoint (range 70-130)
    workshopRepairFraction = 0.06,  -- a full 0->1 workshop repair ~= 6% of price
                                     -- (lifetime ~25% ~= four such heavy repairs)
    fieldRepairCostRatio   = 0.45,  -- a field repair costs ~45% of the workshop
                                     -- price for the same damage delta
}

---Helper: linear interpolation, clamped to [a, b].
-- @return number
function IronHorseRealData.lerp(a, b, t)
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    return a + (b - a) * t
end
