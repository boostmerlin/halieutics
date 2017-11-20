local skynet = require "skynet"
local socket = require "skynet.socket"
local service = require "common.service"
local client = require "common.client"
local timer = require "common.timer"
local log = require "common.log"
local em = require "def.errmsg"
local cjson = require "cjson"

local gate = {}
local data = {
    app = tostring(...),
    users = {}, 
    ucache = {},
}

local cli = {}

local resp_ok = {ok = true}

local function fetch_user(userid)
    if data.users[userid] == nil then
        data.users[userid] = data.ucache[userid]
        data.ucache[userid] = nil
    end
    return data.users[userid]
end

-- cache for reconnect, don't need login authorization server
local function cache_user(userid)
    local user = data.users[userid]
    if user then
        user.state = "afk"
        data.ucache[userid] = user
        data.users[userid] = nil
    end
end

local function reset_cache(user)
    user.state = "wait"
    data.users[user.id] = user
    data.ucache[user.id] = nil
end

local function clear_user(userid)
    data.users[userid] = nil
    data.ucache[userid] = nil
end

function cli:signin(msg)
    if data.shutdown then
        return em.shutdown
    end
    assert(msg.userid, "no userid")
    assert(msg.secret, "no secret")
    self.exit = true
    local secret = service.watchdog.secret(msg.userid)
    if secret and secret ~= msg.secret then
        return {err = em.other_login}
    end
    local user = fetch_user(msg.userid)
    if user == nil then
        return {err = em.secret_expire}
    end
    if user.ltmr then
        timer.remove(user.ltmr)
        user.ltmr = nil
    end
    if user.secret ~= msg.secret then
        return {err = em.invalid_secret}
    end
    log.verbose("[gate] *******signin on gate: %s ", user.state)
    if user.state == "afk" then
        -- check user already login?
        if not service.login.restore(user) then
            return {err = em.repeat_login}
        end
    elseif user.state == "ok" then
        -- return em.repeat_login
        -- kick last user when repeat login just on gate
        service.watchdog.kick(user.id)
    end
    user.state = "ok"
    user.tag = string.format("%s:%d:%s", user.uname, user.id, self.fd)
    user.ip = self.addr:match "([^:]+):"
    self.user = user
    self.login = true
end

local function getuser(c)
    return {
        fd = c.fd,
        ip = c.user.ip,
        id = c.user.id,
        secret = c.user.secret,
        uname = c.user.uname,
        head = c.user.head,
        sex = c.user.sex,
        tag = c.user.tag,
    }
end

local function new_socket(fd, addr)
    log.verbose("[gate] new socket %d %s on %s", fd, addr, data.tag)
    -- client must send a unuse message to skip dispatch
    -- move protocol from gate to agent
    local c = {fd = fd, tag = fd, addr = addr, block = true}
    local ok, err = pcall(client.dispatch, c, "gate")
    if ok then
        if c.login then
            log.debug("protocol move... %s", cjson.encode(c))
            local ok, err = pcall(service.watchdog.assign, getuser(c))
            if ok then
                return
            end
            log.verbose("login-fail %d %s : %s", fd, addr, err)
        end
    else
        if c.login then
            gate.kick(c.user.id, true)
        end
        log.verbose("login-err %d %s : %s", fd, addr, err)
    end
    client.close(fd)
end

function gate.open(platform, conf)
    assert(conf.ip)
    assert(conf.port)
    assert(conf.name)
    conf.platform = assert(platform)
    conf.maxclient = conf.maxload or 1024

    data.conf = conf
    data.tag = string.format("Gate:%s.%s.%s", data.app, conf.platform, conf.name)

    assert(data.fd == nil, "gate already open")
    data.fd = socket.listen("0.0.0.0", conf.port)
    socket.start(data.fd, new_socket)

    if not service.login.register(data.app, conf) then
        socket.close(data.fd)
        log.warning("register %s failed!", data.tag)
        return
    end

    log.notice("%s startup", data.tag)
end

local function timeout_handler(user)
    -- check user exists
    if user.state ~= "ok" then
        clear_user(user.id)
        service.login.logout(user.id)
        log.notice("[gate] login timeout %d", user.id)
    end
end

-- call by loginserver
-- user {id, secret, uname, head, sex, tag}
function gate.login(user)
    -- assert(data.users[user.id] == nil, "repeat login "..user.id)
    -- user return by login.lua what a mess...

    if user.new then
        log.debug("New user, give diamond to %d", user.id)
        service.userdb.add_prop(user.id, "diamond", 1000)
    end
    reset_cache(user)
    user.ltmr = timer.add(15, timeout_handler, user)
    service.userdb.add_record(user.id, "login", 1)
    service.userdb.add_avatar(user.id, {id = user.id, uname = user.uname, head = user.head, sex = user.sex})
    service.gamedb.add_lastest_login(user.id)
    log.verbose("login-try %s %s:%s", data.tag, user.uname, user.id)
end

-- call by watchdog
function gate.kick(userid, cache)
    local user = data.users[userid]
    if user then
       if cache and false then
           cache_user(user.id)
       else
          data.users[user.id] = nil
       end
        service.login.logout(user.id, cache)
        log.notice("[gate] kick %s %s, cached? %s", data.tag, user.tag, cache)
    else
        log.warning("[gate.kick] user not exist in gate server..")
    end
end

service.init {
    command = gate,
    info = data,
    require = {"login"},
    requireX = {
        {name = data.app, service = "watchdog"},
    },
    requireB = {
        {name = data.app, service = "userdb"},
        {name = data.app, service = "gamedb"},
    },
    init = function()
        client.proto("gate", true)
        client.bind(cli)
    end,
    shutdown = function()
        data.shutdown = true
        service.watchdog.shutdown()
    end,
}

