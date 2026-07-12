--
-- IronHorseSpecialization
--
-- The single vehicle specialization. It owns NO feature logic itself — it just
-- dispatches every vehicle lifecycle event to the registered modules, giving
-- each a per-vehicle state table. This is the seam that makes the mod extensible.
--
-- Registered under the name "ironHorseRealism" -> per-vehicle spec table is
-- self.spec_ironHorseRealism (mirrors the proven ADS pattern).
--

IronHorseSpecialization = {}

local SPEC = "spec_ironHorseRealism"

-- No prerequisitesPresent: the spec is injected directly into motorized vehicle
-- types in IronHorseRealism.registerSpecializationToVehicles (which runs in
-- TypeManager.finalizeTypes, AFTER validateTypes), so the manager never consults
-- a prerequisite callback here. The "must be motorized" gate is the injection
-- filter (specializationsByName["motorized"] ~= nil) at the real call site.

function IronHorseSpecialization.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", IronHorseSpecialization)
    SpecializationUtil.registerEventListener(vehicleType, "onUpdateTick", IronHorseSpecialization)
    SpecializationUtil.registerEventListener(vehicleType, "onReadStream", IronHorseSpecialization)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteStream", IronHorseSpecialization)
    SpecializationUtil.registerEventListener(vehicleType, "saveToXMLFile", IronHorseSpecialization)
    SpecializationUtil.registerEventListener(vehicleType, "onDraw", IronHorseSpecialization)
    SpecializationUtil.registerEventListener(vehicleType, "onRegisterActionEvents", IronHorseSpecialization)
end

function IronHorseSpecialization:onLoad(savegame)
    local spec = self[SPEC]
    if spec == nil then
        Logging.warning("[IronHorseRealism] spec table missing on '%s' - vehicle skipped.", tostring(self.configFileName))
        return
    end
    spec.modules = IronHorseModuleRegistry.getSupported(self)
    spec.state = {}
    spec.actionEvents = {}   -- shared per-vehicle input action-event table (client)
    for _, m in ipairs(spec.modules) do
        local state = {}
        spec.state[m.name] = state
        m:onLoad(self, state, savegame)
        if savegame ~= nil and savegame.xmlFile ~= nil then
            m:loadFromXML(self, state, savegame.xmlFile, savegame.key .. ".ironHorseRealism." .. m.name)
        end
    end
end

function IronHorseSpecialization:onUpdateTick(dt)
    local spec = self[SPEC]
    if spec == nil or spec.modules == nil then
        return
    end
    local isServer = g_currentMission ~= nil and g_currentMission:getIsServer()
    for _, m in ipairs(spec.modules) do
        m:onUpdate(self, spec.state[m.name], dt, isServer)
    end
end

function IronHorseSpecialization:onWriteStream(streamId, connection)
    local spec = self[SPEC]
    if spec == nil or spec.modules == nil then
        return
    end
    for _, m in ipairs(spec.modules) do
        m:onWriteStream(self, spec.state[m.name], streamId, connection)
    end
end

function IronHorseSpecialization:onReadStream(streamId, connection)
    local spec = self[SPEC]
    if spec == nil or spec.modules == nil then
        return
    end
    for _, m in ipairs(spec.modules) do
        m:onReadStream(self, spec.state[m.name], streamId, connection)
    end
end

function IronHorseSpecialization:saveToXMLFile(xmlFile, key, _usedModNames)
    local spec = self[SPEC]
    if spec == nil or spec.modules == nil then
        return
    end
    for _, m in ipairs(spec.modules) do
        m:saveToXML(self, spec.state[m.name], xmlFile, key .. ".ironHorseRealism." .. m.name)
    end
end

function IronHorseSpecialization:onDraw(_isActiveForInput, _isActiveForInputIgnoreSelection, _isSelected)
    local spec = self[SPEC]
    if spec == nil or spec.modules == nil then
        return
    end
    -- Only the vehicle the local player is actually in draws the unified HUD.
    if self.getIsEntered ~= nil and not self:getIsEntered() then
        return
    end
    -- Collect the indicators every module declares, then let the HUD render the
    -- single cockpit cluster (one unified HUD; modules never render themselves).
    local indicators = {}
    for _, m in ipairs(spec.modules) do
        local list = m:getHudIndicators(self, spec.state[m.name])
        if list ~= nil then
            for _, ind in ipairs(list) do
                indicators[#indicators + 1] = ind
            end
        end
    end
    IronHorseHud.renderCluster(self, indicators)
end

---Register the modules' input action events for the vehicle the local player is
-- controlling. Client-side only; the shared actionEvents table is cleared and
-- rebuilt each time input activation changes, so keys bind only for the entered
-- vehicle. Each module registers whatever bindings it needs.
function IronHorseSpecialization:onRegisterActionEvents(_isActiveForInput, isActiveForInputIgnoreSelection)
    if self.isClient ~= true then
        return
    end
    local spec = self[SPEC]
    if spec == nil or spec.modules == nil then
        return
    end
    self:clearActionEventsTable(spec.actionEvents)
    if isActiveForInputIgnoreSelection then
        for _, m in ipairs(spec.modules) do
            m:onRegisterActionEvents(self, spec.state[m.name], spec.actionEvents)
        end
    end
end
