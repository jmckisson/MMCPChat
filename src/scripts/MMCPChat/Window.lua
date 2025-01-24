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

    -- Find client with longest name and host
    local nameLen = 12
    local hostLen = 12
    for id, client in pairs(MMCP.clients) do
        if string.len(client:GetName()) > nameLen then
            nameLen = string.len(client:GetName())
        end
        if string.len(client:GetHost()) > hostLen then
            hostLen = string.len(client:GetHost())
        end
    end

    local formatStr = string.format("<white>%%-4s %%-%ds  %%-%ds  %%-5s\n", nameLen, hostLen)

    MMCP.console:cecho(string.format("<b>"..formatStr, "Id", "Name", "Host", "Port"))

    for id, client in pairs(MMCP.clients) do
        MMCP.console:cecho(string.format(formatStr,
            client:GetId(), client:GetName(), client:GetHost(), client:GetPort()))
    end
end