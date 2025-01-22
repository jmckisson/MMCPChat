local socket = require("socket.core")

local defaultOptions = {
    chatName = "MudletUser",
    serverPort = 4050,
    prefixNewline = true
}

MMCP = MMCP or {
  clients = {},
  options = table.deepcopy(defaultOptions),
  localAddress = nil,
  version = "Mudlet MMCP __VERSION__"
}

MMCP.commands = {
    NameChange = 1,
    RequestConnections = 2,
    ConnectionList = 3,
    ChatEverybody = 4,
    ChatPersonal = 5,
    ChatGroup = 6,
    ChatMessage = 7,
    DoNotDisturb = 8,
    Version = 19,
    PingRequest = 26,
    PingResponse = 27,
    PeekConnections = 28,
    PeekList = 29,
    EndOfCommand = 255
}

function MMCP.ChatInfoMessage(message)
    cecho(string.format("\n<yellow>[ CHAT ]  - <green>%s<reset>\n", message))
end


function hexDump(message)
    local len = #message
    local result = {}
    for i = 1, len, 16 do
        local chunk = message:sub(i, i + 15)
        local hexBytes = {}
        local asciiBytes = {}

        for j = 1, #chunk do
            local byte = chunk:sub(j, j):byte()
            table.insert(hexBytes, string.format("%02x", byte))
            if byte >= 32 and byte <= 126 then
                -- Printable ASCII
                table.insert(asciiBytes, string.char(byte))
            else
                -- Non-printable, use "."
                table.insert(asciiBytes, ".")
            end
        end

        -- Create the hex and ASCII lines
        local hexLine = table.concat(hexBytes, " ")
        local asciiLine = table.concat(asciiBytes)
        table.insert(result, string.format("%04x   %-48s   %s", i - 1, hexLine, asciiLine))
    end

    -- Print the result
    print(table.concat(result, "\n"))
end


function MMCP.GetClientByNameOrId(target)
    local numeric = tonumber(target)

    for id, client in pairs(MMCP.clients) do
        if numeric and numeric == id then
            return client
        elseif string.lower(client:GetName()) == string.lower(target) then
            return client
        end
    end

    return nil
end


-- Note this currently isnt working as the restores clients arent "objects" and would
-- probably need to be reinstantiated, using the same descriptor for the socket
-- is another issue altogether...
function MMCP.LoadClients()
    local loadTable = {}
    local tablePath = getMudletHomeDir().."/mmcp_clients_"..getProfileName()..".lua"
    if io.exists(tablePath) then
        table.load(tablePath, loadTable)
    end

    for k, v in pairs(loadTable) do
        MMCP.chatCall(v.host, v.port)
    end

    MMCP.ChatInfoMessage(string.format("Restored clients for %s", getProfileName()))
end


function MMCP.SaveClients()
    local saveTable = {}

    for id, client in pairs(MMCP.clients) do
        if client:IsActive() then
            table.insert(saveTable, {host=client:GetHost(), port=client:GetPort(), group=client:GetGroup()})
        end
    end

    table.save(getMudletHomeDir().."/mmcp_clients_"..getProfileName()..".lua", saveTable)

    --MMCP.ChatInfoMessage(string.format("Saved clients for %s", getProfileName()))
end


function MMCP.LoadOptions()
    local loadTable = {}
    local tablePath = getMudletHomeDir().."/mmcp_"..getProfileName()..".lua"
    if io.exists(tablePath) then
        table.load(tablePath, loadTable)
    end

    MMCP.options = table.deepcopy(loadTable.options)

    MMCP.options = MMCP.options or table.deepcopy(defaultOptions)

    MMCP.ChatInfoMessage(string.format("Loaded options for %s", getProfileName()))
end


function MMCP.SaveOptions()

    local saveTable = {
        options = table.deepcopy(MMCP.options)
    }

    table.save(getMudletHomeDir().."/mmcp_"..getProfileName()..".lua", saveTable)

    MMCP.ChatInfoMessage(string.format("Saved options for %s", getProfileName()))
end


-- Coroutine to receive messages for a specific client
function MMCP.receiveMessages(client)

    while true do
        --echo("MMCP.receiveMessages\n")
        local s, status, partial = client:GetSocket():receive()
        client:SetBuffer(client:GetBuffer() .. (s or partial or "") .. "\n")
        if client:GetBufferLength() > 0 then
            client:HandleMessage()
        end
        if status == "closed" then 
            client:SetActive(false)
            break
        elseif status == "timeout" then
            coroutine.yield(client)
        end

      --echo("Client resumed\n")
    end

end


function MMCP.chatList()
    echo("\n")
    echo(
  [[
Id   Name                 Address              Port  Group           Flags    ChatClient
==== ==================== ==================== ===== =============== ======== ================]]
  )
    echo("\n")

    for id, client in pairs(MMCP.clients) do
        cecho(string.format("%s%-4d %s%s\n", "<green>", id, "<reset>", client:GetInfoString()))
    end

    cecho(string.format(
  [[
==== ==================== ==================== ===== =============== ======== ================
Color Key: %sConnected  %sPending%s
Flags:  A - Allow Commands, F - Firewall, I - Ignore,  P - Private   n - Allow Snooping
        N - Being Snooped,  S - Serving,  T - Allows File Transfers, X - Serve Exclude]]
, "<green>", "<yellow>", "<reset>"))

end

function MMCP.getLocalIPAddress()
    if not MMCP.localAddress then
        -- Create a UDP socket
        local udp = socket.udp()
        -- Temporarily connect to a public DNS server (Google's) to determine the local IP
        udp:setpeername("8.8.8.8", 80)
        local ip, _ = udp:getsockname()
        udp:close()
        MMCP.localAddress = ip
        return ip
    else
        return MMCP.localAddress
    end
end

-- Initiates a new client connection
function MMCP.chatCall(host, port)
    local tcp = assert(socket.tcp())
    tcp:connect(host, port)
    tcp:settimeout(0) -- Non-blocking
    tcp:setoption("keepalive", true)
    tcp:setoption("tcp-nodelay", true)
    local id = #MMCP.clients + 1

    local receiverCo = coroutine.create(MMCP.receiveMessages)

    local client = Client:new(id, tcp, host, port, receiverCo)
    client:SetState("ConnectingOut")

    MMCP.clients[id] = client

    MMCP.SaveClients()

    client:DoCall()

    return id
end


function MMCP.chatAll(message)

    local outMsg = string.format("%s%s chats to everybody, '%s'%s",
        string.char(MMCP.commands.ChatEverybody), MMCP.options.chatName, message, string.char(MMCP.commands.EndOfCommand))

    for id, client in pairs(MMCP.clients) do
        if client:IsActive() then
            client:Send(outMsg)
        end
    end

    local echoMsg = ansi2decho(string.format("%sYou chat to everybody, '%s'%s\n",
        AnsiColors.FBLDRED, message, AnsiColors.StyleReset))

    decho(echoMsg)

    raiseEvent("sysMMCPMessage", echoMsg)
end


function MMCP.chatEmoteAll(message)
    local outMsg = string.format("%s%s %s%s",
        string.char(MMCP.commands.ChatEverybody), MMCP.options.chatName, message, string.char(MMCP.commands.EndOfCommand))

    for id, client in pairs(MMCP.clients) do
        if client:IsActive() then
            client:Send(outMsg)
        end
    end

    local echoMsg = ansi2decho(string.format("%s%s %s%s\n",
        AnsiColors.FBLDRED, MMCP.options.chatName, message, AnsiColors.StyleReset))

    if MMCP.options.prefixNewline then
        echo("\n")
    end
    decho(echoMsg.."\n")

    raiseEvent("sysMMCPMessage", echoMsg)
end


function MMCP.chat(target, message)
    local client = MMCP.GetClientByNameOrId(target)

    if not client then
        return
    end

    local chatMsg = string.format("%s%s chats to you, '%s'\n%s",
        string.char(MMCP.commands.ChatPersonal), MMCP.options.chatName, message, string.char(MMCP.commands.EndOfCommand))

    client:Send(chatMsg)

    local echoMsg = ansi2decho(string.format("%sYou chat to %s, '%s'%s",
        AnsiColors.FBLDRED, client:GetName(), message, AnsiColors.StyleReset))

    if MMCP.options.prefixNewline then
        echo("\n")
    end
    decho(echoMsg.."\n")

    raiseEvent("sysMMCPMessage", echoMsg)
end


function MMCP.chatName(name)
    MMCP.options.chatName = name

    local nameMsg = string.format("%s%s%s",
        string.char(MMCP.commands.NameChange), name, string.char(MMCP.commands.EndOfCommand))

    for id, client in pairs(MMCP.clients) do
        if client:IsActive() then
            client:Send(nameMsg)
        end
    end

    local echoMsg = string.format("You are now known as %s", name)
    MMCP.ChatInfoMessage(echoMsg)
    raiseEvent("sysMMCPMessage", AnsiColors.FBLDRED .. echoMsg .. AnsiColors.StyleReset)

    MMCP.SaveOptions()
end


function MMCP.chatPing(target)
    local client = MMCP.GetClientByNameOrId(target)

    if not client then
        return
    end

    local pingMsg = string.format("%s%s%s",
        string.char(MMCP.commands.PingRequest), socket.gettime(), string.char(MMCP.commands.EndOfCommand))

    client:Send(pingMsg)

    MMCP.ChatInfoMessage(string.format("Pinging %s...", client:GetName()))
end


function MMCP.chatUnChat(target)
    local client = MMCP.GetClientByNameOrId(target)

    if not client then
        return
    end

    client:GetSocket():close()
    client:SetState("Closed")
    client:SetActive(false)

    -- client table will get cleaned up in mainLoop
    --MMCP.clients[client:GetId()] = nil
end



function MMCP.mainLoop()
  while true do
    --echo("MMCP.mainLoop\n")
    local activeClients = false
    for id, client in pairs(MMCP.clients) do
      if client:IsActive() then
        --echo("Resuming client " .. id .. "\n")
        local success, err = coroutine.resume(client:GetReceiver(), client)
        if not success then
          echo("Error resuming client coroutine: " .. err .. "\n")
          client:SetActive(false)
        end
        activeClients = true
      else
        MMCP.ChatInfoMessage(string.format("Connection to %s lost\n", client:GetNameHostString()))
        MMCP.clients[id] = nil
        MMCP.SaveClients()
      end
    end
    if not activeClients then
      -- No active clients, can choose to exit or yield for a longer period
      coroutine.yield()
    end
    coroutine.yield() -- Yield after each full cycle of client checks
  end
end


local mainLoopCo = coroutine.create(MMCP.mainLoop)

-- Function to periodically resume the main loop coroutine
function MMCP.manageMainLoop()
  --cecho("\nmanageMainLoop")
  if coroutine.status(mainLoopCo) ~= "dead" then
    coroutine.resume(mainLoopCo)
    -- Here, you're free to do other tasks, then loop back to resume the mainLoop coroutine
    -- Adjust the delay to balance responsiveness with efficiency
    socket.select(nil, nil, 0.001) -- Sleep briefly to reduce CPU usage
  end
end


if MMCP.socketTimer then
  killTimer(MMCP.socketTimer)
end

MMCP.socketTimer = tempTimer(.1, function() MMCP.manageMainLoop() end, true)

MMCP.LoadOptions()