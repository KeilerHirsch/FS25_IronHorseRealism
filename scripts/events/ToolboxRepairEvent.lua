--
-- ToolboxRepairEvent
--
-- A client -> server COMMAND: "field-repair this vehicle". The authoritative
-- repair (damage change + money) must run on the server, so a client that presses
-- the field-repair key sends this event; the server performs the repair. It
-- carries ONLY the vehicle reference — never a damage amount or a price. The
-- server reads those from the vehicle itself, so a client cannot claim higher
-- damage or a different price to be paid or to over-repair.
--

ToolboxRepairEvent = {}
local ToolboxRepairEvent_mt = Class(ToolboxRepairEvent, Event)

InitEventClass(ToolboxRepairEvent, "ToolboxRepairEvent")

function ToolboxRepairEvent.emptyNew()
    return Event.new(ToolboxRepairEvent_mt)
end

function ToolboxRepairEvent.new(vehicle)
    local self = ToolboxRepairEvent.emptyNew()
    self.vehicle = vehicle
    return self
end

function ToolboxRepairEvent:writeStream(streamId, _connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
end

function ToolboxRepairEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self:run(connection)
end

function ToolboxRepairEvent:run(connection)
    -- Only act when WE are the server receiving a client request. On the server,
    -- the connection is TO a client, so getIsServer() is false; that is the
    -- "came from a client" signal. The server reads damage + price itself.
    if not connection:getIsServer() then
        -- pass the requesting client's connection so the server can verify the
        -- request comes from a player on the vehicle's owner farm
        ToolboxModule.performFieldRepair(self.vehicle, connection)
    end
end

---Request a field repair. On the server/host, do it directly; on a pure client,
-- ask the server.
function ToolboxRepairEvent.sendRequest(vehicle)
    if g_server ~= nil then
        ToolboxModule.performFieldRepair(vehicle, nil)   -- local/host: trusted
    elseif g_client ~= nil then
        g_client:getServerConnection():sendEvent(ToolboxRepairEvent.new(vehicle))
    end
end
