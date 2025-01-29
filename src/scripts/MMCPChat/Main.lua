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

MMCP.colors = {
    StyleReset = "\27[0m",
    ForeBoldRed = "\27[1;31m"
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
        elseif string.lower(client:GetProperty("name")) == string.lower(target) then
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
            table.insert(saveTable, {host=client:Host(), port=client:Port(), group=client:GetProperty("group")})
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
        echo("MMCP.receiveMessages()\n")
        local s, status, partial = client:Socket():receive("*a")
        client:BufferAppend((s or partial or "") .. "")
        if client:BufferLength() > 0 then
            client:HandleMessage()
        end
        if status == "closed" then 
            client:SetActive(false)
            break
        elseif status == "timeout" then
            coroutine.yield(client)
        end

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
        cecho(string.format("%s%-4d %s%s\n", "<green>", id, "<reset>", client:InfoString()))
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

function MMCP.ReindexClients()
    for id, client in pairs(MMCP.clients) do
        client:SetId(id)
    end
end


-- Initiates a new client connection
function MMCP.chatCall(host, port)

    local client = Client.new(host, port)

    table.insert(MMCP.clients, client)

    --local id = table.index_of(MMCP.clients, client)
    MMCP.ReindexClients()

    client:ChatCall()
end


function MMCP.chatAll(message)

    local outMsg = string.format("%s%s chats to everybody, '%s'%s",
        string.char(MMCPCommands.ChatEverybody), MMCP.options.chatName, message, string.char(MMCPCommands.EndOfCommand))

    for id, client in pairs(MMCP.clients) do
        if client:IsActive() then
            client:Send(outMsg)
        end
    end

    local echoMsg = ansi2decho(string.format("%sYou chat to everybody, '%s'%s\n",
    MMCP.colors.ForeBoldRed, message, MMCP.colors.StyleReset))

    decho(echoMsg)

    raiseEvent("sysMMCPMessage", echoMsg)
end


function MMCP.chatEmoteAll(message)
    local outMsg = string.format("%s%s %s%s",
        string.char(MMCPCommands.ChatEverybody), MMCP.options.chatName, message, string.char(MMCPCommands.EndOfCommand))

    for id, client in pairs(MMCP.clients) do
        if client:IsActive() then
            client:Send(outMsg)
        end
    end

    local echoMsg = ansi2decho(string.format("%s%s %s%s\n",
        MMCP.colors.ForeBoldRed, MMCP.options.chatName, message, MMCP.colors.StyleReset))

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
        string.char(MMCPCommands.ChatPersonal), MMCP.options.chatName, message, string.char(MMCPCommands.EndOfCommand))

    client:Send(chatMsg)

    local echoMsg = ansi2decho(string.format("%sYou chat to %s, '%s'%s",
        MMCP.colors.ForeBoldRed, client:GetProperty("name"), message, MMCP.colors.StyleReset))

    if MMCP.options.prefixNewline then
        echo("\n")
    end
    decho(echoMsg.."\n")

    raiseEvent("sysMMCPMessage", echoMsg)
end


function MMCP.chatIgnore(target)
    local client = MMCP.GetClientByNameOrId(target)

    if not client then
        return
    end

    local isIgnored = client:GetProperty("ignored")

    client:SetIgnored(not isIgnored)

    MMCP.ChatInfoMessage(string.format("Set %s to %s",
        client:GetProperty("name"), isIgnored and "not ignored" or "ignored"))

end


function MMCP.chatName(name)
    MMCP.options.chatName = name

    local nameMsg = string.format("%s%s%s",
        string.char(MMCPCommands.NameChange), name, string.char(MMCPCommands.EndOfCommand))

    for id, client in pairs(MMCP.clients) do
        if client:IsActive() then
            client:Send(nameMsg)
        end
    end

    local echoMsg = string.format("You are now known as %s", name)
    MMCP.ChatInfoMessage(echoMsg)
    raiseEvent("sysMMCPMessage", MMCP.colors.ForeBoldRed .. echoMsg .. MMCP.colors.StyleReset)

    MMCP.SaveOptions()
end


function MMCP.chatPing(target)
    local client = MMCP.GetClientByNameOrId(target)

    if not client then
        return
    end

    client:Ping()
end


function MMCP.chatPrivate(target)
    local client = MMCP.GetClientByNameOrId(target)

    if not client then
        return
    end

    local isPrivate = client:GetProperty("private")

    client:SetPrivate(not isPrivate)

    MMCP.ChatInfoMessage(string.format("Set %s to %s",
        client:GetProperty("name"), isPrivate and "not private" or "private"))

end


function MMCP.chatServe(target)
    local client = MMCP.GetClientByNameOrId(target)

    if not client then
        return
    end

    local isServed = client:GetProperty("served")

    client:SetServed(not isServed)

    MMCP.ChatInfoMessage(string.format("Set %s to %s",
        client:GetProperty("name"), isServed and "not served" or "served"))

end


function MMCP.chatServeExclude(target)
    local client = MMCP.GetClientByNameOrId(target)

    if not client then
        return
    end

    local isServeExcluded = client:GetProperty("serveExcluded")

    client:SetServeExcluded(not isServeExcluded)

    MMCP.ChatInfoMessage(string.format("Set %s to %s",
        client:GetProperty("name"), isServeExcluded and "not serve excluded" or "serve excluded"))
end


function MMCP.chatUnChat(target)
    local client = MMCP.GetClientByNameOrId(target)

    if not client then
        return
    end

    client:UnChat()

    -- client table will get cleaned up in mainLoop
end


function MMCP.SendServedMessage(sender, msg, isServed)
    local outMsg = string.format("%s%s%s",
        string.char(MMCPCommands.ChatEverybody), msg, string.char(MMCPCommands.EndOfCommand))

    for id, client in pairs(MMCP.clients) do
        if client:IsActive() and client ~= sender and (not isServed and client:IsServed()) then
            client:Send(outMsg)
        end
    end
end


function MMCP.mainLoop()
  while true do
    local modifiedClients = false
    local activeClients = false
    for id, client in pairs(MMCP.clients) do
      if client:IsActive() then
        local success, err = coroutine.resume(client:Receiver(), client)
        if not success then
          echo("Error resuming client coroutine: " .. err .. "\n")
          client:SetActive(false)
        end
        activeClients = true

      else
        MMCP.ChatInfoMessage(string.format("Connection to %s lost\n", client:NameHostString()))
        table.remove(MMCP.clients, client:GetId())
        MMCP.ReindexClients()
        MMCP.UpdateConsole()
        modifiedClients = true
      end
    end

    if modifiedClients then
        MMCP.SaveClients()
    end

    if activeClients then
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