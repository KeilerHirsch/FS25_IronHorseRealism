--
-- IronHorseSyncEvent
--
-- ONE generic server-authoritative sync event that any module can reuse to
-- replicate a single named numeric state value on a vehicle. Client requests
-- go to the server; the server applies and rebroadcasts. Modules whose
-- authoritative action is already engine-synced (e.g. stopMotor) do not need
-- this — it exists for module state the engine does not replicate.
--

IronHorseSyncEvent = {}
local IronHorseSyncEvent_mt = Class(IronHorseSyncEvent, Event)

InitEventClass(IronHorseSyncEvent, "IronHorseSyncEvent")

-- (moduleName -> {key = validator}) that a CLIENT may push to the server.
-- EMPTY today: all IronHorse state is server-authoritative (server -> clients
-- only), so the server rejects every client-originated write.
--
-- A whitelist entry MUST be a validator FUNCTION (vehicle, connection, value) ->
-- bool, never a bare `true`. The validator has to confirm the connection
-- actually owns/controls that vehicle AND that the value is in range. Requiring
-- a function makes it impossible to open a client-writable key without also
-- supplying that ownership + range check — a non-function entry is denied.
IronHorseSyncEvent.CLIENT_WRITABLE = {}

local function clientWriteAllowed(moduleName, key, vehicle, connection, value)
    local keys = IronHorseSyncEvent.CLIENT_WRITABLE[moduleName]
    local validator = keys ~= nil and keys[key] or nil
    if type(validator) ~= "function" then
        return false   -- unknown key, or a non-function (e.g. bare true): deny
    end
    return validator(vehicle, connection, value) == true
end

function IronHorseSyncEvent.emptyNew()
    return Event.new(IronHorseSyncEvent_mt)
end

function IronHorseSyncEvent.new(vehicle, moduleName, key, value)
    local self = IronHorseSyncEvent.emptyNew()
    self.vehicle = vehicle
    self.moduleName = moduleName
    self.key = key
    self.value = value
    return self
end

function IronHorseSyncEvent:writeStream(streamId, _connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
    streamWriteString(streamId, self.moduleName)
    streamWriteString(streamId, self.key)
    streamWriteFloat32(streamId, self.value)
end

function IronHorseSyncEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self.moduleName = streamReadString(streamId)
    self.key = streamReadString(streamId)
    self.value = streamReadFloat32(streamId)
    self:run(connection)
end

function IronHorseSyncEvent:run(connection)
    local fromClient = not connection:getIsServer()
    -- Server received this from a client: only apply fields that are explicitly
    -- declared client-writable. Otherwise a client could inject arbitrary module
    -- state on any vehicle. Nothing is client-writable today, so this drops all
    -- client-originated writes. (Server -> client broadcasts have fromClient=false
    -- and are trusted.)
    if fromClient and not clientWriteAllowed(self.moduleName, self.key, self.vehicle, connection, self.value) then
        return
    end

    local vehicle = self.vehicle
    if vehicle ~= nil and vehicle.spec_ironHorseRealism ~= nil then
        local state = vehicle.spec_ironHorseRealism.state
        if state ~= nil and state[self.moduleName] ~= nil then
            state[self.moduleName][self.key] = self.value
        end
    end

    -- If this came from a client (and passed the check above), the server
    -- rebroadcasts to the other clients.
    if fromClient then
        g_server:broadcastEvent(
            IronHorseSyncEvent.new(self.vehicle, self.moduleName, self.key, self.value),
            nil, connection, self.vehicle)
    end
end

---Send a module state value to be replicated. Server broadcasts; client asks
-- the server (which applies + rebroadcasts).
function IronHorseSyncEvent.send(vehicle, moduleName, key, value)
    if g_server ~= nil then
        g_server:broadcastEvent(IronHorseSyncEvent.new(vehicle, moduleName, key, value), nil, nil, vehicle)
    elseif g_client ~= nil then
        g_client:getServerConnection():sendEvent(IronHorseSyncEvent.new(vehicle, moduleName, key, value))
    end
end
