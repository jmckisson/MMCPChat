local socket = require("socket.core")

if MMCP and MMCP.socketTimer then
  killTimer(MMCP.socketTimer)
end

MMCP = MMCP or {
  clients = {},
  serverPort = 4050,
  chatName = "Humera"
}


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



-- Function to handle incoming messages
function MMCP.handleMessage(client, message)
  
  if client.state == "ConnectingOut" then
    print("Received negotiation from", client.host, ":", client.buffer)
    local success, clientName = client.buffer:match("^(%S+):(%S+)")
    if success == "YES" then
      client.name = clientName
      client.state = "Connected"
      cecho(string.format("\n<yellow>[ CHAT ]  - <green>Connection to %s at %s successful\n",
        client.name, client.tcp:getsockname()))
        
      client.buffer = client.buffer:sub(string.len(clientName) + 5)
    else
      client.tcp:close()
    end
  elseif client.state == "Connected" then

    local msgEnd = string.find(client.buffer, string.char(0xff), 2)
    if not msgEnd then
      return
    end
    local payload = client.buffer:sub(1, msgEnd - 1)
    client.buffer = client.buffer:sub(msgEnd + 1)
    
    echo("Received message from " .. client.name .. " : " .. payload .. "\n")
    hexDump(payload)
    local msgType = string.byte(payload:sub(1, 1))
    
    echo("msgType " .. msgType .. "  msgEnd " .. msgEnd .. "\n")
    payload = payload:sub(2)

    if msgType == 4 then      -- chat everybody
      local ansiMsg = ansi2decho(AnsiColors.FBLDRED .. payload)
      decho(ansiMsg.."\n")
      -- Check if we're serving this person
    elseif msgType == 5 then  -- personal chat
      local ansiMsg = ansi2decho(AnsiColors.FBLDRED .. payload)
      decho(ansiMsg.."\n")
    elseif msgType == 19 then
      print("Got version from " .. client.name .. " : " .. payload .. "\n")
      client.version = payload
    else
      print("Unknown message type " .. msgType .. " received from " .. client.name .. "\n")
    end
    
  end
end


-- Coroutine to receive messages for a specific client
function MMCP.receiveMessages(client)
  client.buffer = client.buffer or ""
  --return coroutine.create(function()
    while true do
      --echo("MMCP.receiveMessages\n")
      local s, status, partial = client.tcp:receive()
      client.buffer = client.buffer .. (s or partial or "")
      if client.buffer and string.len(client.buffer) > 0 then
        MMCP.handleMessage(client, client.buffer)
      end
      if status == "closed" then 
        echo("Client closed\n")
        client.active = false
        break
      elseif status == "timeout" then
        coroutine.yield(client)
      end
      
      --echo("Client resumed\n")
    end
  --end)
end


-- Coroutine for sending a ping message
function MMCP.sendPing(tcp)
    return coroutine.create(function()
        local pingMessage = "PING" -- Adjust based on MMCP command format
        while true do
            tcp:send(pingMessage)
            coroutine.yield() -- Yield until the next time we want to send a ping
        end
    end)
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
    local flagStr = ""
    local infoStr = string.format("%-20s %-20s %-5d %-15s %-8s",
      client.name, client.host, client.port, client.group or "None", flagStr)
      
    cecho(string.format("%s%-4d %s%s%s\n", "<green>", id, "<reset>", infoStr, client.version))
  end
  
  cecho(string.format(
  [[
==== ==================== ==================== ===== =============== ======== ================
Color Key: %sConnected  %sPending%s
Flags:  A - Allow Commands, F - Firewall, I - Ignore,  P - Private   n - Allow Snooping
        N - Being Snooped,  S - Serving,  T - Allows File Transfers, X - Serve Exclude]]
, "<green>", "<yellow>", "<reset>"))
  
end


-- Initiates a new client connection
function MMCP.chatCall(host, port)
  local client = {tcp = assert(socket.tcp()), host = host, port = port, active = true}
  client.tcp:connect(host, port)
  client.tcp:settimeout(0) -- Non-blocking
  client.id = #MMCP.clients + 1
  
  local function getLocalIPAddress()
    -- Create a UDP socket
    local udp = socket.udp()
    -- Temporarily connect to a public DNS server (Google's) to determine the local IP
    udp:setpeername("8.8.8.8", 80)
    local ip, _ = udp:getsockname()
    udp:close()
    return ip
  end
  
  local callString = string.format("CHAT:%s\n%s%-5d", MMCP.chatName, getLocalIPAddress(), MMCP.serverPort)
  cecho("\n"..callString)
  
  client.state = "ConnectingOut"
  
  client.tcp:send(callString)
  
  local receiverCo = coroutine.create(MMCP.receiveMessages)
  client.receiverCo = receiverCo
  
  MMCP.clients[client.id] = client -- Store client instance
  return client.id -- Return client ID for reference
end


function MMCP.mainLoop()
  while true do
    --echo("MMCP.mainLoop\n")
    local activeClients = false
    for id, client in pairs(MMCP.clients) do
      if client.active then
        --echo("Resuming client " .. id .. "\n")
        local success, err = coroutine.resume(client.receiverCo, client)
        if not success then
          echo("Error resuming client coroutine: " .. err .. "\n")
          client.active = false
        end
        activeClients = true
      else
        MMCP.clients[id] = nil -- Cleanup inactive clients
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
