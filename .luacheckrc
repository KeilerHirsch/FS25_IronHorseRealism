-- luacheck configuration for FS25_IronHorseRealism
-- FS25 runs LuaJIT (Lua 5.1 semantics).
std = "lua51"

-- Globals this mod defines (module system + core singletons).
globals = {
    "IronHorseRealism",
    "IronHorseModuleRegistry",
    "IronHorseModule",
    "IronHorseSpecialization",
    "IronHorseSyncEvent",
    "IronHorseConfig",
    "IronHorseRealData",
    "IronHorseHud",
    "EngineStallModule",
}

-- Engine-provided globals the mod reads (never assigns).
read_globals = {
    "Vehicle", "VehicleMotor", "Motorized", "SpecializationUtil", "TypeManager",
    "Utils", "Logging", "g_currentMission", "g_modManager", "g_modIsLoaded",
    "g_specializationManager", "g_vehicleTypeManager", "g_currentModDirectory",
    "g_currentModName", "Mission00", "Class", "InitEventClass",
    "Event", "EventIds", "streamWriteBool", "streamReadBool", "streamWriteString",
    "streamReadString", "streamWriteFloat32", "streamReadFloat32",
    "streamWriteInt32", "streamReadInt32", "streamWriteUIntN", "streamReadUIntN",
    "NetworkUtil", "g_server", "g_client",
    "getName", "g_time", "g_i18n", "getUserProfileAppPath", "createXMLFile",
    "XMLFile", "InputAction", "source", "renderText", "setTextColor", "setTextBold",
    "setTextAlignment", "RenderText", "drawFilledRect",
}

-- Tests load the mod with stubbed engine globals.
files["tests/"] = {
    std = "+busted",
    globals = { "_G" },
    read_globals = {},
}
