local skynet = require "skynet"
local service = require "common.service"
local balance = require "common.balance"
local log = require "common.log"

local recharge = {}

local data = {treated = {}, treating = {}}
local userdb = {}
local watchdog = {}

local function fetch_userdb(app)
    if userdb[app] == nil then
        userdb[app] = balance{name = app, service = "userdb"}
    end
    return userdb[app]
end

local function fetch_watchdog(app)
    if watchdog[app] == nil then
        watchdog[app] = service.xlaunch("watchdog", app)
    end
    return watchdog[app]
end

function recharge.add(app, userid, prop, num)
    local udb = fetch_userdb(app)
    local uid = tonumber(userid)
    local ret = udb.add_prop(uid, prop, tonumber(num))
    local wdog = fetch_watchdog(app)
    if wdog then
        local agent = wdog.query(uid)
        if agent then
            skynet.call(agent, "lua", "push", uid, "update_account", {diamond=ret})
        else
            log.warning("[recharge.add] found no agent for user: %s", userid)
        end
    else
        log.warning("[recharge.add] found no watchdog for app: %s", app)
    end
    return ret
end

function recharge.get(app, userid, prop)
    local udb = fetch_userdb(app)
    return udb.get_user_prop(tonumber(userid), prop)
end

service.init {
    command = recharge,
    info = data,
    require = {
        "gmdb",
    },
}

