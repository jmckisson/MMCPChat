for i = 1, matches[2] do
  local cmd = string.gsub(matches[3], "#", i)
  send(cmd)
end