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

function IronHorseSpecialization.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(Motorized, specializations)
end

function IronHorseSpecialization.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", IronHorseSpecialization)
    SpecializationUtil.registerEventListener(vehicleType, "onUpdateTick", IronHorseSpecialization)
    SpecializationUtil.registerEventListener(vehicleType, "onReadStream", IronHorseSpecialization)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteStream", IronHorseSpecialization)
    SpecializationUtil.registerEventListener(vehicleType, "saveToXMLFile", IronHorseSpecialization)
    SpecializationUtil.registerEventListener(vehicleType, "onDraw", IronHorseSpecialization)
end

function IronHorseSpecialization:onLoad(savegame)
    local spec = self[SPEC]
    spec.modules = IronHorseModuleRegistry.getSupported(self)
    spec.state = {}
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
    if spec.modules == nil then
        return
    end
    local isServer = g_currentMission ~= nil and g_currentMission:getIsServer()
    for _, m in ipairs(spec.modules) do
        m:onUpdate(self, spec.state[m.name], dt, isServer)
    end
end

function IronHorseSpecialization:onWriteStream(streamId, connection)
    local spec = self[SPEC]
    if spec.modules == nil then
        return
    end
    for _, m in ipairs(spec.modules) do
        m:onWriteStream(self, spec.state[m.name], streamId, connection)
    end
end

function IronHorseSpecialization:onReadStream(streamId, connection)
    local spec = self[SPEC]
    if spec.modules == nil then
        return
    end
    for _, m in ipairs(spec.modules) do
        m:onReadStream(self, spec.state[m.name], streamId, connection)
    end
end

function IronHorseSpecialization:saveToXMLFile(xmlFile, key, _usedModNames)
    local spec = self[SPEC]
    if spec.modules == nil then
        return
    end
    for _, m in ipairs(spec.modules) do
        m:saveToXML(self, spec.state[m.name], xmlFile, key .. ".ironHorseRealism." .. m.name)
    end
end

function IronHorseSpecialization:onDraw(_isActiveForInput, _isActiveForInputIgnoreSelection, _isSelected)
    local spec = self[SPEC]
    if spec.modules == nil then
        return
    end
    -- Only the vehicle the local player is actually in draws the unified HUD.
    if self.getIsEntered ~= nil and not self:getIsEntered() then
        return
    end
    IronHorseHud.beginFrame()
    for _, m in ipairs(spec.modules) do
        m:drawHud(self, spec.state[m.name], IronHorseHud)
    end
    IronHorseHud.endFrame()
end
