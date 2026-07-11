--
-- IronHorseRealism — mod loader
--
-- Sources the core + modules, registers the single specialization, injects it
-- into every motorized vehicle type, and runs the coexistence detector that
-- makes this mod dominant over the mods it replaces.
--

IronHorseRealism = {}
IronHorseRealism.VERSION = "0.1.0.0"
IronHorseRealism.SPEC_NAME = "ironHorseRealism"

local modDirectory = g_currentModDirectory

-- Core + infra + modules (order: base -> registry -> infra -> modules).
source(modDirectory .. "scripts/core/IronHorseModule.lua")
source(modDirectory .. "scripts/core/IronHorseModuleRegistry.lua")
source(modDirectory .. "scripts/core/IronHorseConfig.lua")
source(modDirectory .. "scripts/core/IronHorseRealData.lua")
source(modDirectory .. "scripts/events/IronHorseSyncEvent.lua")
source(modDirectory .. "scripts/hud/IronHorseHud.lua")
source(modDirectory .. "scripts/modules/EngineStallModule.lua")

---Register all feature modules with the registry. Add new modules here.
function IronHorseRealism.registerModules()
    IronHorseModuleRegistry.register(EngineStallModule)
end

---Register the specialization class with the game (mirrors ADS).
function IronHorseRealism.registerSpecialization()
    g_specializationManager:addSpecialization(
        IronHorseRealism.SPEC_NAME, "IronHorseSpecialization",
        modDirectory .. "scripts/core/IronHorseSpecialization.lua", "")
end

---Inject the specialization into every motorized vehicle type (runs after
-- TypeManager.finalizeTypes, so all base + mod types exist).
function IronHorseRealism.registerSpecializationToVehicles()
    local specName = IronHorseRealism.SPEC_NAME
    for typeName, typeEntry in pairs(g_vehicleTypeManager.types) do
        if typeEntry ~= nil and typeEntry.specializationsByName ~= nil
            and typeEntry.specializationsByName["motorized"] ~= nil
            and typeEntry.specializationsByName[specName] == nil then
            g_vehicleTypeManager:addSpecialization(typeName, specName)
        end
    end
end

---Detect the mods this one replaces and assert dominance (technical, not a
-- readme note). Load order already lets our hooks win; here we flag it loudly
-- and expose the list so modules can neutralise rival effects.
function IronHorseRealism.detectCoexistence()
    local replaces = { "FS25_AdvancedDamageSystem", "FS25_EnhancedVehicle", "FS25_VariableTirePressure" }
    local found = {}
    for _, name in ipairs(replaces) do
        if g_modIsLoaded ~= nil and g_modIsLoaded[name] == true then
            found[#found + 1] = name
        end
    end
    IronHorseRealism.replacedModsPresent = found
    if #found > 0 then
        Logging.warning("[IronHorseRealism] takes precedence over active replacement mods: %s. Disable them to avoid double effects.", table.concat(found, ", "))
    end
end

IronHorseRealism.registerModules()
IronHorseRealism.registerSpecialization()
TypeManager.finalizeTypes = Utils.appendedFunction(TypeManager.finalizeTypes, IronHorseRealism.registerSpecializationToVehicles)
Mission00.load = Utils.prependedFunction(Mission00.load, IronHorseRealism.detectCoexistence)

Logging.info("[IronHorseRealism %s] core loaded.", IronHorseRealism.VERSION)
