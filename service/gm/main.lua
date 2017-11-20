local skynet = require "skynet"
local redis = require "skynet.db.redis"
local redisdb = require "common.redisdb"
local service = require "common.service"
local log = require "common.log"
local utils = require "common.utils"
local urllib = require "http.url"
local cjson = require "cjson"
local crypt = require "skynet.crypt"

local gm = {}
local service_map = {}

local account = {
    ["yjj"] = "yjj123"
}

local SECRET_TIMEOUT = 60 * 10

gm.secrets = {}

local face_protocol = {
--recharge.add(app, userid, prop, num)
    ["recharge.add"] = {"app", "userid", "prop", "num"},
    ["recharge.get"] = {"app", "userid", "prop"},
    --CMD.noticeadd(content, time, tp, expire)
    ["config.noticeadd"] = {"content", "time", "tp", "expire"},
    ["misc.accinfo"] = {"userid"},
    ["misc.query"] = {"nick"},
    ["misc.regusern"] = {"app"},
    ["misc.online"] = {"app"},
    ["misc.activeusers"] = {"from", "to"},
    ["misc.blacklist"] = {"userid", "kick"},
    ["misc.bind"] = {"userid", "icode"},
    ["misc.whitelist"] = {"userid"},
    ["misc.getstock"] = {},
    ["misc.setstock"] = {"value"},
    ["misc.appleswitch"] = {"app", "ver", "stat"},
    ["config.gamefish"] = {"kind", "key", "nv"},
    ["config.playcfg"] = {},
    ["config.stockcfg"] = {},
    ["config.stockthreshold"] = {"value", "prob"},
    ["config.shareinfoget"] = {},
    ["config.shareinfoset"] = {"stitle", "scontent", "surl", "ititle", "icontent", "iurl"},
    ["config.noticegets"] = {},
    ["config.noticeget"] = {"id"},
    ["config.noticedel"] = {"id"},
    ["config.noticeadd"] = {"content", "time", "tp", "expire"},
}

local function convert_face(proto, params)
    local t = {}
    local tt = face_protocol[proto]
    if not tt then
        log.error("not find protocol: %s", proto)
    end
    for _, v in ipairs(tt) do
        local p = params[v]
        if p == nil then
            --error("[gm] protocol not consistent.")
            p = false --post taker
        end
        if p and p:find(",") then
           local array = utils.split(p, ',')
           table.insert(t, array)
        else
           if type(p)=="string" then
               p = utils.trim(p)
           end
           table.insert(t, p)
        end
    end
    return t
end

local function secret_time_out()
    local now = math.floor(skynet.time())
    for k, v in pairs(gm.secrets) do
        if now > v.expire then
            gm.secrets[k] = nil
            log.debug("[gm] %s secrect: %s expire.", v.user, k)
        end
    end
    skynet.timeout(100, secret_time_out)
end

local function login(user, pass)
    if account[user] and account[user] == pass then
        local secret = crypt.hexencode(crypt.randomkey())
        gm.secrets[secret] = {user=user, expire = math.floor(skynet.time()) + SECRET_TIMEOUT}
        return secret
    end
end

local function islogin(user)
    for _, v in pairs(gm.secrets) do
        if user == v.user then
            return true
        end
    end
end

local function validate(sec)
    return gm.secrets[sec] ~= nil
end

local function get_service(name)
    if service_map[name] == nil then
        local ret = service.ulaunch(name)
        service_map[name] = ret
    end
    return service_map[name]
end

local function dispatch_channel(ch, message, header, body, method)
    local channel, command = ch:match("([^%.]+)%.([^%.]+)")
    log.debug("[dispatch_channel] dispatch ch: %s, message: %s", ch, message)
    if channel then
        local s = get_service(channel)
        if s then
            local f = s[command]
            if not message then
                return f()
            else
               local params = urllib.parse_query(message)
                if #params ~= 1 then
                    params = convert_face(ch, params)
                end
              --  local params = urllib.parse_query(message)
                return f(table.unpack(params))
            end
        end
    else
        log.warning("unknown channel %s %s", ch, message)
        error("unknown channel")
    end
end


local FORBID_GET_LOGIN = true
local AUTH = false

function gm.http(url, method, header, body)
    local path, query = urllib.parse(url:sub(2, -1))
    local ch = path:gsub("/", ".")

    if not ch or #ch==0 then
        return "Invalid Request", 403
    end

    local message = query
    if method == "POST" then
        if not string.match(header["content-type"], "application/x%-www%-form%-urlencoded") then
            return "wrong content type, should application/x-www-form-urlencoded", 400
        end
        message = body
    end
    if AUTH then
        if ch == "login" then
            if FORBID_GET_LOGIN then
                if method ~= "POST" then
                    return "Use POST", 400
                end
            end

            local params = urllib.parse_query(message)
            local user = params["user"]

            if islogin(user) then
                return "Repeated Login", 400
            end

            local sec = login(user, params["pass"])
            if not sec then
                return "Login Failed", 401
            end
            return {Secret = sec}
        else
            local sec = header["Secret"]
            if not sec or not validate(sec) then
                return "no secret or invalid secret", 401
            end
        end
    end

    local ok, err = pcall(dispatch_channel, ch, message, header, body, method)
    if not ok then
        return "Internal Server Error", 500
    end
    return err, 200
end

function gm.open(token)
    skynet.timeout(100, secret_time_out)
    local dbconf = redisdb.parse(token)
    local wdb = redis.watch(dbconf)
    wdb:psubscribe("*")
    skynet.fork(function()
        while true do
            local message, channel = wdb:message()
            log.debug("[gm] publish %s %s, type message: %s", channel, message, type(message))
            skynet.fork(dispatch_channel, channel, message)
        end
        log.warning "gm service stop"
    end)
end

service.init {
    command = gm,
}

