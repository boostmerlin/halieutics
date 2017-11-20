local skynet = require "skynet"

local function balance(s)
    local master = skynet.uniqueservice "balanced"
    local name = skynet.call(master, "lua", "launch", s)

    local function cmd_f(cmd)
        return function(...)
            return skynet.call(master, "lua", "call", name, cmd, ...)
        end
    end

    return setmetatable({}, {
        __index = function(t, k)
            t[k] = cmd_f(k)
            return t[k]
        end
    })
end

return balance

