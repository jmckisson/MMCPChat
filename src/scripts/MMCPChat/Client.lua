local socket = require("socket.core")

Client = Client or {}

function Client:new(id, tcp, host, port, receiver)
    local newObj = {}
    setmetatable(newObj, self)
    self.__index = self

    newObj.id = id
    newObj.active = true
    newObj.socket = tcp
    newObj.buffer = ""
    newObj.receiverCo = receiver
    newObj.state = ""
    newObj.name = "MudletUser"
    newObj.host = host
    newObj.port = port
    newObj.version = ""
    newObj.group = "None"

    return newObj
end

function Client:IsActive()
    return self.active == true
end

function Client:SetActive(val)
    self.active = val
end

function Client:GetBufferLength()
    return string.len(self.buffer)
end

function Client:GetBuffer()
    return self.buffer
end

function Client:SetBuffer(val)
    self.buffer = val
end

function Client:GetGroup()
    return self.group
end

function Client:SetGroup(val)
    self.group = val
end

function Client:GetId()
    return self.id
end

function Client:GetInfoString()
    local flagStr = ""
    local infoStr = string.format("%-20s %-20s %-5d %-15s %-8s %s",
      self.name, self.host, self.port, self.group, flagStr, self.version)

    return infoStr
end

function Client:GetReceiver()
    return self.receiverCo
end

function Client:GetSocket()
    return self.socket
end

function Client:GetState()
    return self.state
end

function Client:SetState(val)
    self.state = val
end

function Client:GetNameHostString()
    return string.format("%s@%s", self.name or "<Unknown>", self.host)
end

function Client:GetName()
    return self.name
end

function Client:SetName(val)
    self.name = val
end

function Client:GetHost()
    return self.host
end

function Client:SetHost(val)
    self.host = val
end

function Client:GetVersion()
    return self.version
end

function Client:SetVersion(val)
    self.version = val
end

function Client:Send(buf)
    self.socket:send(buf)
end

function Client:DoCall()

    local callString = string.format("CHAT:%s\n%s%-5d", MMCP.chatName, MMCP.getLocalIPAddress(), MMCP.serverPort)
    cecho("\n"..callString)
    self.socket:send(callString)
end


function Client:HandleConnectedState()
    local msgEnd = string.find(self.buffer, string.char(MMCP.commands.EndOfCommand), 2)
    if not msgEnd then
        return
    end

    local payload = self.buffer:sub(1, msgEnd - 1)
    self.buffer = self.buffer:sub(msgEnd + 1)

    echo("Received message from " .. self.name .. " : " .. payload .. "\n")
    --hexDump(payload)
    local msgType = string.byte(payload:sub(1, 1))

    echo("msgType " .. msgType .. "  msgEnd " .. msgEnd .. "\n")
    payload = payload:sub(2)

    if msgType == MMCP.commands.NameChange then
        MMCP.ChatInfoMessage(string.format("%s has changed their name to %s",
            self.name, payload))

        self:SetName(payload)

    elseif msgType == MMCP.commands.ChatEverybody then      -- chat everybody
        local ansiMsg = ansi2decho(AnsiColors.FBLDRED .. payload)
        decho(ansiMsg.."\n")
        -- Check if we're serving this person

    elseif msgType == MMCP.commands.ChatPersonal then  -- personal chat
        local ansiMsg = ansi2decho(AnsiColors.FBLDRED .. payload)
        decho(ansiMsg.."\n")

    elseif msgType == MMCP.commands.Version then
        echo("Got version from " .. self.name .. " : " .. payload .. "\n")
        self.version = payload

    elseif msgType == MMCP.commands.PingRequest then
        local pingMsg = string.format("%s%d%s",
            string.char(MMCP.commands.PingResponse), payload, string.char(MMCP.commands.EndOfCommand))

        self:Send(pingMsg)

    elseif msgType == MMCP.commands.PingResponse then
        local pingResponse = tonumber(payload)
        local pingTime = (socket.gettime() * 1000) - pingResponse
        MMCP.ChatInfoMessage(string.format("Ping returned from %s: %d ms",
            self.name, pingTime))
    else
        echo("Unknown message type " .. msgType .. " received from " .. self.name .. "\n")
    end

end


-- Function to handle incoming messages
function Client:HandleMessage()

    if self.state == "ConnectingOut" then
      echo("Received negotiation from", self.host, ":", self.buffer)
      local success, clientName = self.buffer:match("^(%S+):(%S+)")

      if success == "YES" then
        self.name = clientName
        self.state = "Connected"

        MMCP.ChatInfoMessage(string.format("Connection to %s at %s successful\n",
            self.name, self.socket:getsockname()))

        self.buffer = self.buffer:sub(string.len(clientName) + 5)

        self:SendVersion()
      else
        self.socket:close()
      end

    elseif self.state == "Connected" then
        self:HandleConnectedState()
    end

end


function Client:SendVersion(target)

    local versionMsg = string.format("%s%s%s",
        string.char(MMCP.commands.Version), MMCP.version, string.char(MMCP.commands.EndOfCommand))

    self:Send(versionMsg)

end