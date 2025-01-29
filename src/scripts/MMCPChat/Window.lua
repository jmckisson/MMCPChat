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

    -- Find longest client name and host
    local nameLen = 12
    local hostLen = 12
    for id, client in pairs(MMCP.clients) do
        if string.len(client:GetProperty("name")) > nameLen then
            nameLen = string.len(client:GetProperty("name"))
        end
        if string.len(client:Host()) > hostLen then
            hostLen = string.len(client:Host())
        end
    end

    local headerFormat = string.format("<white>%%-4s %%-%ds  %%-%ds  %%-5s\n", nameLen, hostLen)
    local nameFormat = string.format("%%-%ds  ", nameLen)
    local lastFormat = string.format("%%-%ds  %%-5s\n", hostLen)

    MMCP.console:cecho(string.format("<b>"..headerFormat, "Id", "Name", "Host", "Port"))

    for id, client in pairs(MMCP.clients) do
        MMCP.console:cecho(string.format("%-4s ", client:GetId()))
        
        local formattedName = string.format(nameFormat, client:GetProperty("name"))

        MMCP.console:cechoPopup(formattedName, {
            function() client:Ping() end
        },
        {"Ping"}, true)
        
        MMCP.console:cecho(string.format(lastFormat, client:Host(), client:Port()))

    end
end