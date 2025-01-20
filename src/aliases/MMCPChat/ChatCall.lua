addr = matches[2]
port = 4050
if matches[3] ~= nil then
  port = matches[3]
end

chatCall(addr, port)