local skynet = require "skynet"
local sharedata = require "skynet.sharedata"
local mc = require "skynet.multicast"
local service = require "common.service"
local balance = require "common.balance"
local log = require "common.log"
local cjson = require "cjson"


local function init_common_db(instance)
    local dblist = {
        {name = "account", service = "accdb"},
        {name = "stat", service = "statdb"},
        {name = "gm", service = "gmdb"},
    }
    for _, db in ipairs(dblist) do
        local inst = instance[db.service] or 1
        if inst > 1 then
            balance{service = db.service, instance = inst}
        else
            service.ulaunch(db.service)
        end
    end
end

local function init_app_db(name, instance)
    local dblist = {
        {name = "game", service = "gamedb"},
        {name = "user", service = "userdb"},
    }
    for _, db in ipairs(dblist) do
        local inst = instance[db.service] or 1
        log.debug("init app db, name: %s, service: %s, inst: %d", name, db.service, inst)
        if inst > 1 then
            balance{name = name, service = db.service, instance = inst}
        else
            service.ulaunch(db.service, name)
        end
    end
end

local function init_game_config(name, conf)
    local gcp = skynet.getenv "game_config_path"
    for cfgname, cfgfile in pairs(conf[name]) do
        local file = string.format("%s/%s", gcp, cfgfile)
        local f = assert(io.open(file), "Can't open " .. file)
        local t = f:read "a"
       -- log.debug("init game config: %s", t)
        f:close()
        log.debug("init_game_config, add sharedata: %s:%s", name,cfgname)

        local info = cjson.decode(t)
        sharedata.new(name .. ":" .. cfgname, info)
    end
end

local function init_app(name, conf)
    init_game_config("shop", conf)
    init_game_config("notice", conf)
    init_game_config("gameplay", conf)

    local channel = mc.new()
    sharedata.new("ch:broadcast:"..name, {channel = channel.channel})
    local roomlobby = service.xlaunch("roomlobby", name)
    roomlobby.open(conf.games)

    for platform, gates in pairs(conf.gates) do
        for _, g in ipairs(gates) do
            local gate = service.launch("gate", name)
            gate.open(platform, g)
            init_app_db(name, conf.instance)
        end
    end

    log.debug("client.version %s ios:%s android:%d", name, conf.version.ios, conf.version.android)
end

skynet.start(function()
    local scf = skynet.getenv "sys_config_file"
    local sysconf = assert(dofile(scf))
    sharedata.new("sysconfig", sysconf)

    init_common_db(sysconf.instance)

    local login = service.ulaunch("login", sysconf.instance.auth)

 --   local stat = service.ulaunch "stat"
    local acp = skynet.getenv "app_config_path"
    for _, name in ipairs(sysconf.apps) do
        local file = string.format("%s/%s.lua", acp, name)
        local conf = assert(dofile(file))
        sharedata.new("appconfig." .. name, conf)
        init_app(name, conf)
        local stat = service.ulaunch "stat"
        stat.register(name)
        stat.open()
    end

    login.open(sysconf.login)

    local gm = service.ulaunch "gm"
    gm.open(sysconf.db.gm)

    local web = service.ulaunch "webserver"
    web.open()

   -- skynet.newservice("debug_console", 10002)

    log.notice "Server start..."
    skynet.exit()
end)

