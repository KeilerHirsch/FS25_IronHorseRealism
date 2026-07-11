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
    local vehicle = self.vehicle
    if vehicle ~= nil and vehicle.spec_ironHorseRealism ~= nil then
        local state = vehicle.spec_ironHorseRealism.state
        if state ~= nil and state[self.moduleName] ~= nil then
            state[self.moduleName][self.key] = self.value
        end
    end
    -- If this came from a client, the server rebroadcasts to the other clients.
    if not connection:getIsServer() then
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
