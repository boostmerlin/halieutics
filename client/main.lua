local skynet = require "skynet"
require "skynet.manager"


skynet.start(function()
	local server_address = skynet.getenv "server_address"
    local robot_mode = skynet.getenv "robot_mode"
    local mode, count = robot_mode:match "(%u):(%d+)"
    local identity = skynet.getenv "simulator"
    if mode == "C" then
        local name_prefix = "opengame"
        for i=1, tonumber(count) do
            local client = skynet.newservice("lobby", server_address)
            skynet.call(client, "lua", "open", string.format("%s_%d", name_prefix, i))
        end
    elseif mode == "S" then
        local name_prefix = "opengame"
        for i=1, tonumber(count) do
            local identifier = string.format("%s_%s_%d", name_prefix, identity, i)
            print(identifier)
            local client = skynet.newservice("simu", server_address)
            skynet.name(identifier, client)
            skynet.call(client, "lua", "open", identifier, identity, i)
        end

    else
        print("Unknown mode!!")

    end
    skynet.exit()
end)
