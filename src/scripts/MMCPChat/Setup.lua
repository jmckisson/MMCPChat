MMCPCommands = {
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
    SideChannel = 40,
    EndOfCommand = 255
}

MMCPColors = {
    StyleReset = "\27[0m",
    ForeBoldCyan = "\27[1;36m",
    ForeBoldRed = "\27[1;31m"
}

MMCPDefaultOptions = {
    chatName = "MudletUser",
    serverPort = 4050,
    prefixNewline = true
}

function InitMMCPSocketLib()
    local socket = nil
    local platform, ver = getOS()
    if platform == "windows" then
        package.cpath = package.cpath .. ";./MMCPChat/winx64/?.dll"
        socket = require("socket.core")
    elseif platform == "mac" then
        -- try arm first
        local cpathOrig = package.cpath
        package.cpath = package.cpath .. ";./MMCPChat/macarm64/?.dll"
        socket = require("socket.core")
        if not socket then
            package.cpath = cpathOrig .. ";./MMCPChat/macx64/?.dll"
            socket = require("socket.core")
        end
    elseif platform == "linux" then
        package.cpath = package.cpath .. ";./MMCPChat/linuxx64/?.dll"
        socket = require("socket.core")
    end

    return socket
end