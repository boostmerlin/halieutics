local crypt = require "skynet.crypt"
local md5core = require "md5"
local service = require "common.service"
local thirdparty = require "common.thirdparty"
local log = require "common.log"
local em = require "def.errmsg"
local randomkey = crypt.randomkey
local hex = crypt.hexencode
local md5 = md5core.sumhexa

local auth = {}

local function getuser(acc)
    local user = {}
    user.id = acc.id
    user.new = acc.new
    user.guest = acc.guest
    user.uname = acc.uinfo.uname
    user.secret = hex(randomkey())
    user.acc = acc.uinfo
    user.forbidden = acc.base.forbidden
    if acc.third then
        user.third = {rtk=acc.third.info.rtk}
    end
    return user
end

local do_auth = {}

function do_auth.guest(app, type, info)
    assert(info.code and #info.code > 0)
    local acc = {third = {name = "guest", uid = info.code, info = {rtk=info.code}}}
    acc.id, acc.base, acc.uinfo = service.accdb.query3rd(acc.third)
    if acc.id == nil then
        acc.id, acc.base, acc.uinfo = service.accdb.register3rd(acc.third, acc.uinfo)
        if acc.id then
            acc.new = true
            service.statdb.user(app, type)
        end
    end
    assert(acc.id and acc.base and acc.uinfo)
    acc.guest = true
    return true, acc
end


local function do_auth3rd(app, type, info)
    local acc = {}
    local ok, ret1, ret2 = thirdparty.auth(app, type, info)

    if not ok then
        return false, ret1
    end

    acc.third = ret1
    acc.uinfo = ret2
    log.debug("[do_auth3rd] auth %s ok", acc.third.name)

    acc.id, acc.base = service.accdb.query3rd(acc.third)
    if acc.id == nil then
        acc.id, acc.base = service.accdb.register3rd(acc.third, acc.uinfo)
        if acc.id then
            acc.new = true
            service.statdb.user(app, type)
        end
    else
        service.accdb.refresh3rd(acc.id, acc.third, acc.uinfo)
    end
    assert(acc.id and acc.base)
    return true, acc
end

function auth.handshake(app, type, info)
    local f = do_auth[type] or do_auth3rd
    local ok, state, acc = pcall(f, app, type, info)
    if ok then
        if state then
            return state, getuser(acc)
        else
            return state, acc
        end
    else
        log.warning("handshake failed : %s", acc)
    end
end

service.init {
    command = auth,
    requireB = {
        {service = "statdb"},
    },
    require = {"accdb"},
}

