--
-- IronHorseModuleRegistry
--
-- The backbone: an ordered registry of feature modules. The specialization
-- iterates it to dispatch every lifecycle event. Adding a feature = registering
-- a module here; the core never changes.
--

IronHorseModuleRegistry = {}
IronHorseModuleRegistry.modules = {}
IronHorseModuleRegistry.byName = {}

---Register a module. Ignores duplicates (by name) so a double-source is safe.
-- @param table module a IronHorseModule instance
function IronHorseModuleRegistry.register(module)
    if module == nil or module.name == nil then
        Logging.warning("[IronHorseRealism] register: ignoring module without a name.")
        return
    end
    if IronHorseModuleRegistry.byName[module.name] ~= nil then
        return
    end
    IronHorseModuleRegistry.byName[module.name] = module
    table.insert(IronHorseModuleRegistry.modules, module)
    Logging.info("[IronHorseRealism] module registered: %s", module.name)
end

---@return table ordered list of registered modules
function IronHorseModuleRegistry.getModules()
    return IronHorseModuleRegistry.modules
end

---Return the modules that support the given vehicle (used by the spec on load).
function IronHorseModuleRegistry.getSupported(vehicle)
    local out = {}
    for _, m in ipairs(IronHorseModuleRegistry.modules) do
        if m:isSupported(vehicle) then
            out[#out + 1] = m
        end
    end
    return out
end
