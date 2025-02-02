local os = "winx64"
local socket = require(os..".socket.core")

Client = {}


function Client.new(host, port)

    local instance = {
        socket = nil,
        buffer = "",
        receiverCo = nil,
        host = host,
        port = port,
        state = "",
        active = true,
        id = -1,
        properties = {
            name = nil,
            version = "",
            group = "None",
            private = false,
            served = false,
            serveExcluded = false,
            ignored = false,
            snooping = false,
            snoopEnabled = false,
        }
    }

    setmetatable(instance, { __index = Client} )
    return instance

end


function Client:GetProperty(key)
    return self.properties[key]
end

function Client:SetProperty(key, value)
    self.properties[key] = value
end

-- Non-properties accessors

function Client:Host()
    return self.host
end

function Client:Port()
    return self.port
end

function Client:BufferLength()
    return string.len(self.buffer)
end

function Client:Buffer()
    return self.buffer
end

function Client:BufferAppend(buf)
    self.buffer = self.buffer .. buf
end

function Client:Receiver()
    return self.receiverCo
end

function Client:Socket()
    return self.socket
end

function Client:IsActive()
    return self.active == true
end

function Client:SetActive(val)
    self.active = val
end

function Client:GetId()
    return self.id
end

function Client:SetId(val)
    self.id = val
end


function Client:Send(buf)
    self.socket:send(buf)
end

function Client:FlagsString()

    local isFirewalled = false
    if self.socket:getsockname() ~= self.host then
        isFirewalled = true
    end

    local snoopVal = ' '
    if self.properties.snooping then
        snoopVal = 'N'
    else
        if self.properties.snoopEnabled then
            snoopVal = 'n'
        end
    end

    return string.format("%s%s%s%s%s%s%s%s",
        ' ',
        ' ',
        self.properties.private and 'P' or ' ',
        self.properties.ignored and 'I' or ' ',
        self.properties.served and 'S' or ' ',
        isFirewalled and 'F' or ' ',
        snoopVal,
        self.properties.serveExcluded or ' '
    )
end

function Client:InfoString()
    local flagStr = self:FlagsString()
    local infoStr = string.format("%-20s %-20s %-5d %-15s %-8s %s",
      self.properties.name, self.host, self.port, self.properties.group, flagStr, self.properties.version)

    return infoStr
end

function Client:NameHostString()
    return string.format("%s@%s", self.properties.name or "<Unknown>", self.host)
end

function Client:ChatCall()
    self.socket = assert(socket.tcp())
    self.socket:connect(self.host, self.port)
    self.socket:settimeout(0) -- Non-blocking
    self.socket:setoption("keepalive", true)
    self.socket:setoption("tcp-nodelay", true)

    self.state = "ConnectingOut"

    self.receiverCo = coroutine.create(MMCP.receiveMessages)

    local ip, _ = self.socket:getsockname()
    --local callString = string.format("CHAT:%s\n%s%-5d", MMCP.options.chatName, MMCP.getLocalIPAddress(), MMCP.options.serverPort)
    local callString = string.format("CHAT:%s\n%s%-5d", MMCP.options.chatName, ip, MMCP.options.serverPort)
    --cecho("\n"..callString)
    self.socket:send(callString)
end

function Client:HandleNameChange(payload)
    MMCP.ChatInfoMessage(string.format("%s has changed their name to %s",
        self.properties.name, payload))

    self:SetName(payload)
end

function Client:Ping()
    local pingMsg = string.format("%s%s%s",
        string.char(MMCPCommands.PingRequest), socket.gettime(), string.char(MMCPCommands.EndOfCommand))

    self:Send(pingMsg)

    MMCP.ChatInfoMessage(string.format("Pinging %s...", self.properties.name))
end

function Client:UnChat()
    self.socket:close()
    self.state = "Closed"
    self.active = false
end

function Client:HandlePingRequest(payload)
    local pingMsg = string.format("%s%s%s",
            string.char(MMCPCommands.PingResponse), payload, string.char(MMCPCommands.EndOfCommand))

    self:Send(pingMsg)
end

function Client:HandlePingResponse(payload)
    local pingResponse = tonumber(payload)
    local pingTime = socket.gettime() - pingResponse
    --echo("ping response: " .. pingResponse .. " difftime: " .. pingTime .. "\n")
    MMCP.ChatInfoMessage(string.format("Ping returned from %s: %d ms",
        self.properties.name, pingTime * 1000))
end

function Client:HandleChatEverybody(payload)
    if self.properties.ignored then
        return
    end

    local ansiMsg = ansi2decho(MMCP.colors.ForeBoldRed .. payload .. MMCP.colors.StyleReset)
    if MMCP.options.prefixNewline then
        echo("\n")
    end
    decho(ansiMsg.."\n")
    raiseEvent("sysMMCPMessage", ansiMsg)

    -- Forward served message if this client isnt excluded from served
    -- messages
    if not self.properties.serveExcluded then
        MMCP.SendServedMessage(self, ansiMsg, self.properties.served)
    end
end

function Client:HandleChatPersonal(payload)
    if self.properties.socketignored then
        return
    end

    local ansiMsg = ansi2decho(MMCP.colors.ForeBoldRed .. payload .. MMCP.colors.StyleReset)
    if MMCP.options.prefixNewline then
        echo("\n")
    end
    decho(ansiMsg.."\n")
    raiseEvent("sysMMCPMessage", ansiMsg)
end

function Client:HandleChatMessage(payload)
    local ansiMsg = ansi2decho(payload)
    decho(ansiMsg.."\n")
    raiseEvent("sysMMCPMessage", ansiMsg)
end

function Client:HandleChatVersion(payload)
    self.properties.version = payload
end


function Client:HandleConnectedState()
    local msgEnd = string.find(self.buffer, string.char(MMCPCommands.EndOfCommand), 2)
    if not msgEnd then
        return
    end

    local payload = self.buffer:sub(1, msgEnd - 1)
    self.buffer = self.buffer:sub(msgEnd + 1)

    --hexDump(payload)
    local msgType = string.byte(payload:sub(1, 1))
    --echo("Received message from " .. self.properties.name .. " : type: " .. msgType .. " : " .. payload .. "\n")

    --echo("msgType " .. msgType .. "  msgEnd " .. msgEnd .. "\n")
    payload = payload:sub(2)

    local handler = MMCPHandlers[msgType]
    if handler then
        handler(self, payload)
    else
        echo("Unknown message type " .. msgType .. " received from " .. self.properties.name .. "\n")
        hexDump(payload)
    end

end


-- Function to handle incoming messages
function Client:HandleMessage()
    --echo("Client:HandleMessage() state: " .. self.state .. "\n")

    if self.state == "ConnectingOut" then
      --echo("Received negotiation from", self.host, ":", self.buffer)
      local success, clientName = self.buffer:match("^(%S+):(%S+)")

      if success == "YES" then
        self.properties.name = clientName
        self.state = "Connected"

        MMCP.ChatInfoMessage(string.format("Connection to %s at %s successful\n",
            self.properties.name, self.socket:getsockname()))

        -- skip past the negotiation string
        self.buffer = self.buffer:sub(string.len(clientName) + 6)

        self:SendVersion()
        MMCP.SaveClients()
        MMCP.UpdateConsole()
      else
        self.socket:close()
      end

    elseif self.state == "Connected" then
        self:HandleConnectedState()
    end

end


function Client:SendVersion()

    local versionMsg = string.format("%s%s%s",
        string.char(MMCPCommands.Version), MMCP.version, string.char(MMCPCommands.EndOfCommand))

    self:Send(versionMsg)

end

MMCPHandlers = {
    [MMCPCommands.ChatPersonal]    = Client.HandleChatPersonal,
    [MMCPCommands.ChatEverybody]   = Client.HandleChatEverybody,
    [MMCPCommands.ChatMessage]     = Client.HandleChatMessage,
    [MMCPCommands.NameChange]      = Client.HandleNameChange,
    [MMCPCommands.PingRequest]     = Client.HandlePingRequest,
    [MMCPCommands.PingResponse]    = Client.HandlePingResponse,
    [MMCPCommands.Version]         = Client.HandleChatVersion,
}