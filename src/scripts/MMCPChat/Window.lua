MMCP = MMCP or {}

MMCP.window = MMCP.window or Adjustable.Container:new({
    name = "MMCP Connections"
})

MMCP.console = Geyser.MiniConsole:new({
    name = "MMCPConsole",
    width = "100%", height = "100%",
    x = 0, y = 0,
    autoWrap = false,
    color = "black",
    scrollBar = false,
    fontSize = 13,
}, MMCP.window)

function MMCP.UpdateConsole()
    MMCP.console:clear()

    local clientList = getChatList()

    -- Find longest client name and host
    local nameLen = 12
    local hostLen = 12
    for id, client in pairs(clientList) do
        if string.len(client.name) > nameLen then
            nameLen = string.len(client.name)
        end
        if string.len(client.host) > hostLen then
            hostLen = string.len(client.host)
        end
    end

    local headerFormat = string.format("<white>%%-4s %%-%ds  %%-%ds  %%-5s\n", nameLen, hostLen)
    local nameFormat = string.format("%%-%ds  ", nameLen)
    local lastFormat = string.format("%%-%ds  %%-5s\n", hostLen)

    MMCP.console:cecho(string.format("<b>"..headerFormat, "Id", "Name", "Host", "Port"))

    for id, client in pairs(clientList) do
        MMCP.console:cecho(string.format("%-4s ", client.id))

        local formattedName = string.format(nameFormat, client.name)

        MMCP.console:cechoPopup(formattedName, {
            function() chatPing(client.id) end
        },
        {"Ping"}, true)

        MMCP.console:cecho(string.format(lastFormat, client.host, "????"))

    end
end