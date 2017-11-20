local skynet = require "skynet"
local sharedata = require "skynet.sharedata"
local balance = require "common.balance"
local service = require "common.service"
local s3rd = {}
local appinfo = {}
local thirdparty = {}

skynet.init(function()
    local config = sharedata.query "sysconfig"
    for _, third in ipairs(config.user3rd) do
        local instance = config.instance[third] or 1
        if instance > 1 then
            s3rd[third] = balance{service = third, instance = instance}
        else
            s3rd[third] = service.ulaunch(third)
        end
    end
end)

local function get_appinfo(type, app)
    if appinfo[app] == nil then
        local config = sharedata.query("appconfig." .. app)
        assert(config.third)
        appinfo[app] = config.third[type]
    end
    return appinfo[app]
end

function thirdparty.auth(app, type, args)
    local s = assert(s3rd[type], string.format("no supports thirdparty %s service", type))
    local a = assert(get_appinfo(type, app), "no supports thirdparty %s.%s appinfo", type, app)
    return s.auth(a, args)
end

return thirdparty

