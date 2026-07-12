--
-- IronHorseConfig
--
-- Deliberately MINIMAL. Design principle: as few knobs as possible so players
-- cannot misconfigure the mod during play. For now: a global on/off and a
-- per-module enable flag (server-owned). No live-editable numeric tuning.
--

IronHorseConfig = {}

IronHorseConfig.enabled = true
IronHorseConfig.moduleEnabled = {
    engineStall = true,
    engineHealth = true,
    electrical = true,
}

---@return boolean whether the mod is active at all
function IronHorseConfig.isEnabled()
    return IronHorseConfig.enabled == true
end

---@param string name module id
-- @return boolean whether that module is enabled
function IronHorseConfig.isModuleEnabled(name)
    return IronHorseConfig.enabled == true and IronHorseConfig.moduleEnabled[name] == true
end
