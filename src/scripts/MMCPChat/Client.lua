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
    newObj.name = nil
    newObj.host = host
    newObj.port = port
    newObj.version = ""
    newObj.group = "None"
    newObj.isPrivate = false
    newObj.isServed = false
    newObj.isIgnored = false
    newObj.isSnooping = false
    newObj.isSnoopEnabled = false

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

function Client:GetReceiver()
    return self.receiverCo
end

function Client:SetReceiver(receiver)
    self.receiverCo = receiver
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

function Client:GetPort()
    return self.port
end

function Client:GetVersion()
    return self.version
end

function Client:SetVersion(val)
    self.version = val
end

function Client:IsPrivate()
    return self.isPrivate
end

function Client:SetPrivate(val)
    self.isPrivate = val
end

function Client:IsServed()
    return self.isServed
end

function Client:SetServed(val)
    self.isServed = val
end

function Client:IsIgnored()
    return self.isIgnored
end

function Client:SetIgnored(val)
    self.isIgnored = val
end

function Client:IsSnooping()
    return self.isSnooping
end

function Client:SetSnooping(val)
    self.isSnooping = val
end

function Client:IsSnoopEnabled()
    return self.isSnoopEnabled
end

function Client:SetSnoopEnabled(val)
    self.isSnoopEnabled = val
end

function Client:Send(buf)
    self.socket:send(buf)
end

function Client:GetFlagsString()

    local isFirewalled = false
    if self.socket:getsockname() ~= self.host then
        isFirewalled = true
    end

    local snoopVal = ' '
    if self.isSnooping then
        snoopVal = 'N'
    else
        if self.isSnoopEnabled then
            snoopVal = 'n'
        end
    end

    return string.format("%s%s%s%s%s%s%s%s",
        ' ',
        ' ',
        self.isPrivate and 'P' or ' ',
        self.isIgnored and 'I' or ' ',
        self.isServed and 'S' or ' ',
        isFirewalled and 'F' or ' ',
        snoopVal,
        ' '
    )
end

function Client:GetInfoString()
    local flagStr = self:GetFlagsString()
    local infoStr = string.format("%-20s %-20s %-5d %-15s %-8s %s",
      self.name, self.host, self.port, self.group, flagStr, self.version)

    return infoStr
end

function Client:GetNameHostString()
    return string.format("%s@%s", self.name or "<Unknown>", self.host)
end

function Client:DoCall()

    local ip, _ = self.socket:getsockname()
    local callString = string.format("CHAT:%s\n%s%-5d", MMCP.options.chatName, MMCP.getLocalIPAddress(), MMCP.options.serverPort)
    --local callString = string.format("CHAT:%s\n%s%-5d", MMCP.options.chatName, ip, MMCP.options.serverPort)
    --cecho("\n"..callString)
    self.socket:send(callString)
end


function Client:HandleConnectedState()
    local msgEnd = string.find(self.buffer, string.char(MMCP.commands.EndOfCommand), 2)
    if not msgEnd then
        return
    end

    local payload = self.buffer:sub(1, msgEnd - 1)
    self.buffer = self.buffer:sub(msgEnd + 1)

    --echo("Received message from " .. self.name .. " : " .. payload .. "\n")
    --hexDump(payload)
    local msgType = string.byte(payload:sub(1, 1))

    --echo("msgType " .. msgType .. "  msgEnd " .. msgEnd .. "\n")
    payload = payload:sub(2)

    if msgType == MMCP.commands.NameChange then
        MMCP.ChatInfoMessage(string.format("%s has changed their name to %s",
            self.name, payload))

        self:SetName(payload)

    elseif msgType == MMCP.commands.ChatEverybody then      -- chat everybody
        if self.isIgnored then
            return
        end

        local ansiMsg = ansi2decho(AnsiColors.FBLDRED .. payload .. AnsiColors.StyleReset)
        if MMCP.options.prefixNewline then
            echo("\n")
        end
        decho(ansiMsg.."\n")
        raiseEvent("sysMMCPMessage", ansiMsg)

        -- Forward served message if this client isnt private
        if not self.isPrivate then
            MMCP.SendServedMessage(self, ansiMsg, self:IsServed())
        end


    elseif msgType == MMCP.commands.ChatPersonal then  -- personal chat
        if self.isIgnored then
            return
        end

        local ansiMsg = ansi2decho(AnsiColors.FBLDRED .. payload .. AnsiColors.StyleReset)
        if MMCP.options.prefixNewline then
            echo("\n")
        end
        decho(ansiMsg.."\n")
        raiseEvent("sysMMCPMessage", ansiMsg)

    elseif msgType == MMCP.commands.ChatMessage then
        local ansiMsg = ansi2decho(payload)
        decho(ansiMsg.."\n")
        raiseEvent("sysMMCPMessage", ansiMsg)

    elseif msgType == MMCP.commands.Version then
        self.version = payload

    elseif msgType == MMCP.commands.PingRequest then
        local pingMsg = string.format("%s%s%s",
            string.char(MMCP.commands.PingResponse), payload, string.char(MMCP.commands.EndOfCommand))

        self:Send(pingMsg)

    elseif msgType == MMCP.commands.PingResponse then
        local pingResponse = tonumber(payload)
        local pingTime = socket.gettime() - pingResponse
        MMCP.ChatInfoMessage(string.format("Ping returned from %s: %d ms",
            self.name, pingTime))
    else
        echo("Unknown message type " .. msgType .. " received from " .. self.name .. "\n")
        hexDump(payload)
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

        -- skip past the negotiation string
        self.buffer = self.buffer:sub(string.len(clientName) + 6)

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