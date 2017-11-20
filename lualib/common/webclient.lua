local skynet = require "skynet"

local webclient

skynet.init(function()
    webclient = skynet.uniqueservice "webclient"
end)

local request = {}

function request.get(url, gtbl)
    return skynet.call(webclient, "lua", "request", url, gtbl, nil)
end

function request.post(url, ptbl, no_reply)
    return skynet.call(webclient, "lua", "request", url, nil, ptbl, no_reply)
end

return request

