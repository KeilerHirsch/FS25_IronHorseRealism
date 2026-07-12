--
-- IronHorseModule
--
-- Contract/base class for every IronHorse Realism feature module.
--
-- A module is a SINGLETON table with lifecycle hooks. Per-vehicle state does
-- NOT live on the module; it lives in a state table the specialization creates
-- per vehicle and passes into every hook. That keeps modules stateless and
-- makes adding a new feature = registering a new module, never touching the core.
--
-- Every hook has a safe default (no-op / passthrough); a module overrides only
-- what it needs.
--

IronHorseModule = {}
local IronHorseModule_mt = { __index = IronHorseModule }

---Create a new module with the given unique name.
-- @param string name unique module id (also the savegame/state key)
-- @return table module
function IronHorseModule.new(name)
    assert(type(name) == "string" and name ~= "", "IronHorseModule.new requires a non-empty name")
    return setmetatable({ name = name }, IronHorseModule_mt)
end

---Whether this module applies to the given vehicle. Default: yes.
-- Modules that need a specific specialization (Wheels, Motorized, ...) override.
function IronHorseModule:isSupported(_vehicle)
    return true
end

---Called once when the vehicle loads. Initialise the per-vehicle state table.
function IronHorseModule:onLoad(_vehicle, _state, _savegame) end

---Called every update tick. isServer tells the module where it runs; all
-- authoritative state changes must be gated on isServer.
function IronHorseModule:onUpdate(_vehicle, _state, _dt, _isServer) end

---Multiplayer: write/read the module's synced state.
function IronHorseModule:onWriteStream(_vehicle, _state, _streamId, _connection) end
function IronHorseModule:onReadStream(_vehicle, _state, _streamId, _connection) end

---Savegame persistence.
function IronHorseModule:saveToXML(_vehicle, _state, _xmlFile, _key) end
function IronHorseModule:loadFromXML(_vehicle, _state, _xmlFile, _key) end

---Register the module's input action events for the entered vehicle (client
-- side). Called by the spec on onRegisterActionEvents with the shared per-vehicle
-- actionEvents table; a module that wants a key binding overrides this and calls
-- vehicle:addActionEvent(actionEvents, InputAction.X, ...). Default: none.
function IronHorseModule:onRegisterActionEvents(_vehicle, _state, _actionEvents) end

---Declare this module's HUD indicators for the unified cockpit cluster.
-- Return nil for "nothing to show", or a flat list of indicator tables:
--   { id = "...", label = "MOTOR", value = "92%"?, status = "..."?, severity = IronHorseHud.SEV_* }
-- The HUD owns all rendering, positioning and colour — modules only declare.
function IronHorseModule:getHudIndicators(_vehicle, _state) return nil end
