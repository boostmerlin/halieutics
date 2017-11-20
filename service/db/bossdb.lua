local cjson = require "cjson"
local rdb = require "common.redisdb"
local log = require "common.log"
local skynet = require "skynet"
local crypt = require "crypt"

local md5core = require "md5"
local db = {}
local hashkey = crypt.hashkey
local md5 = md5core.sumhexa
local mfloor = math.floor

local function hash(key)
    local h = hashkey(key)
    return h
end

local cmd_multi = rdb.cmd_multi
local cmd_exec = rdb.cmd_exec
local str_format = string.format

function db.exist(recode)
    local hkey = str_format("boss:acc:%d", recode)

    return rdb.db:exists(hkey) == 1
end

function db.bind(recode, userid)
    if db.exist(recode) then
        local skey = "boss:bind:"..recode
        rdb.db:zadd(skey, mfloor(skynet.time()), userid)
        return true
    else
        return false
    end
end

function db.register(uinfo)
    local uname = assert(uinfo.uname, "user name must supply")

    local hname = hash(uname)
    local r = rdb.db:exists("boss:accname:"..hname)
    if r == 1 then
        log.warning("[bossdb] uname exist.")
        return false
    end

    local pass = assert(uinfo.passwd, "user pass must supply")
    uinfo.uname = nil
    uinfo.passwd = nil
    pass = md5(pass)
    local jsoninfo = cjson.encode(uinfo)
    log.debug("[bossdb] register acc: %s", jsoninfo)
    rdb.db:setnx("boss:recode:counter", 14300)

    local recode = rdb.db:incr("boss:recode:counter")
    local ops = {cmd_multi}
    local hkey = str_format("boss:acc:%d", recode)

    table.insert(ops, {"set", "boss:accname:"..hname, recode})
    table.insert(ops, {"hset", hkey, "uname", uname})
    table.insert(ops, {"hset", hkey, "passwd", pass})
    table.insert(ops, {"hset", hkey, "uinfo", jsoninfo})
    table.insert(ops, cmd_exec)

    rdb.db:pipeline(ops)
end

rdb.init {
    name = "boss",
    command = db,
}

