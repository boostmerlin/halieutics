local skynet = require "skynet"
local service = require "common.service"
local timer = require "common.timer"
local log = require "common.log"
local cjson = require "cjson"

local STAT_INTVAL = 10

local appname
local stat = {}

local function do_work()
    local start = skynet.now()
    local online_stat = service.login.stat()
    -- if online_stat[appname] then
    --  --   print( "----online: ", cjson.encode(online_stat[appname]))
    --     service.statdb.online(appname, online_stat[appname])
    -- end
    local ret = service.roomlobby.deskn()
 --   print( "desk n", ret.deskn )
    service.statdb.desks(appname, ret.deskn)
    timer.add(STAT_INTVAL, do_work)
    --log.debug("---------update stat takes: %d", skynet.now()-start)
end

function stat.register(app)
    appname = app
    log.debug("[stat.register] stat %s", app)
end

function stat.open()
    timer.add(STAT_INTVAL, do_work)
end

service.init {
    command = stat,
    require = {"login", "statdb"},
    requireX = {
        {name = "fish", service = "roomlobby"},
    },
}

