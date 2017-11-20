local skynet = require "skynet"
local socket = require "skynet.socket"
local crypt = require "skynet.crypt"
local sharedata = require "skynet.sharedata"
local service = require "common.service"
local client = require "common.client"
local log = require "common.log"
local em = require "def.errmsg"
local cjson = require "cjson"

local sformat = string.format

local auth_inst = tonumber(...)

local server = {}
local data = {apps = {}}
local service_app = {}
local service_gate = {}
local gate_counter = {}

local cli = {}

local function assign_gate(app, platform)
    local name = sformat("%s.%s", app, platform)
    local counter = gate_counter[name]
    if counter then
        return counter()
    end
end

local function getuser(user)
    return {
        id = user.id,
        secret = user.secret,
        uname = user.uname,
        head = user.acc.head,
        sex = user.acc.sex,
        new = user.new,
        forbidden = user.forbidden
    }
end

function cli:appleswitch(req)
    local ret = service.gmdb.appleswitch(req.app, req.ver)
    if #ret > 0 then
        return ret[1]
    else
        return {err = em.no_version_found}
    end
end

function cli:login(req)
    if data.shutdown then
        return {err = em.shutdown}
    end

    local app = data.apps[req.app]
    if app == nil then
        return {err = em.app_exists}
    end

    if app.platforms[req.platform] == nil then
        return {err = em.platform_noexists}
    end

    local svr_ver = app.config.version[req.platform] 
    local cli_ver = req.version or 0
    if svr_ver and cli_ver < svr_ver then
        return {err = em.old_version[req.platform]}
    end

    local ok, state, user = pcall(service.auth.handshake, req.app, req.type, req.info)

    if not ok then
        return {err = em.unauth}
    end

    if not state then
        return {err = user}
    end

    if user.forbidden then
        return {err = em.in_blacklist}
    end

    if app.online[user.id] then
        app.watchdog.try_kick(user.id)
       -- return {err = em.repeat_login}
    end

    user.gate = assign_gate(req.app, req.platform)
    if user.gate == nil then
        return {err = em.server_busy}
    end
    --user return by auth.lua
    user.tag = string.format("%s:%d", user.uname, user.id)
    app.online[user.id] = user
    local _u = getuser(user)
    log.debug("[cli:login] user info: %s || Gate Uinfo: %s", cjson.encode(user), cjson.encode(_u))
    skynet.call(user.gate.service, "lua", "login", _u)
    self.exit = true
    log.notice("auth-ok %s assign %s", user.tag, user.gate.tag)
    return {
        account = user.acc,
        user = {id = user.id, secret = user.secret, rtk=user.third.rtk},
        server = {ip = user.gate.ip, port = user.gate.port},
    }
end

local function new_socket(fd, addr)
    log.debug("new socket %d %s on loginserver", fd, addr)
    pcall(client.dispatch, {fd = fd}, "login")
    client.close(fd)
    log.debug("[login] close login user %d", fd)
end

function server.open(port)
    data.port = port
    assert(data.fd == nil, "login already open")
    data.fd = socket.listen("0.0.0.0", port)
    socket.start(data.fd, new_socket)
    log.notice("login server listen on 0.0.0.0:%d", port)
end

local function assign_counter(a)
    local n = #a
    local idx = 0 
    return function()
        idx = idx + 1
        if idx > n then 
            idx = 1
        end
        local src = idx
        repeat
            local g = a[idx]
            if g.client < g.maxclient then
                g.client = g.client + 1
                return g
            end
            idx = idx + 1
            if idx > n then
                idx = 1
            end
        until src == idx
    end
end

local function make_gate_assign_counter(app)
    for platform, gates in pairs(app.platforms) do
        local name = sformat("%s.%s", app.name, platform)
        gate_counter[name] = assign_counter(gates) 
    end
end

function server.register(name, conf)
    local source = service.SOURCE
    local app = data.apps[name]
    if app == nil then
        app = {
            name = name, 
            config = sharedata.query("appconfig."..name),
            online = {}, 
            platforms = {}
        }
        data.apps[name] = app 
    end

    local gates = app.platforms[conf.platform]
    if gates == nil then
        gates = {}
        app.platforms[conf.platform] = gates 
    end

    conf.service = source
    conf.client = 0
    conf.tag = string.format("%s.%s.%s", name, conf.platform, conf.name)

    table.insert(gates, conf)
    service_app[source] = app
    service_gate[source] = conf
    make_gate_assign_counter(app)
    app.watchdog = service.xlaunch("watchdog", name)
    log.notice("[gate] reg %s %s:%d %d", conf.tag, conf.ip, conf.port, conf.maxclient)

    return true
end

function server.logout(userid, force)
    local app = assert(service_app[service.SOURCE], skynet.address(service.SOURCE) .. " no app")
    local user = assert(app.online[userid], "no user " .. tostring(userid))
    user.gate.client = user.gate.client - 1
    app.online[userid] = nil
    log.notice("[!!login] user %s logout from %s, force? %s", user.tag, user.gate.tag, force)
    if force then
        server.stat()
    end
end

function server.restore(user)
    local source = service.SOURCE
    local app = assert(service_app[source], skynet.address(source) .. " no app")
    if app.online[user.id] then
        return
    end
    local gate = assert(service_gate[source], skynet.address(source) .. " no gate")
    user.gate = gate
    gate.client = gate.client + 1   -- this maybe cause gate.client > gate.maxlient
    app.online[user.id] = user
    return true
end

function server.stat()
    local stat = {}
    for name, app in pairs(data.apps) do
        stat[name] = {}
        for plat, gates in pairs(app.platforms) do
            local n = 0
            for _, g in ipairs(gates) do
                n = n + g.client
            end
            stat[name][plat] = n
        end
        service.statdb.online(name, stat[name])
    end
    service.statdb.resetactiveusers()
    local t={}
    for name, app in pairs(data.apps) do
        for uid, v in pairs(app.online) do
            local vv = getuser(v)
            vv.secret = nil
            local svv = cjson.encode(vv)
          --  print( "stat()  ", svv )
            table.insert(t, svv)
        end
    end
    service.statdb.addactiveusersrange(t)

  --  return stat
end

service.init {
    command = server,
    info = data,
    require = {"statdb","gmdb"},
    requireB = {
        { service = "auth", instance = auth_inst }
    },
    init = function()
        client.proto("login", true)
        client.bind(cli)
    end,
    shutdown = function()
        data.shutdown = true
        for _, app in pairs(data.apps) do
            for _, gates in pairs(app.platforms) do
                for _, g in ipairs(gates) do
                    skynet.call(g.service, "lua", "shutdown")
                end
            end
        end
    end
}

