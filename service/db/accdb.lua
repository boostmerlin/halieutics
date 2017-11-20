local skynet = require "skynet"
local crypt = require "skynet.crypt"
local md5core = require "md5"
local cjson = require "cjson"
local rdb = require "common.redisdb"
local log = require "common.log"

local hex = crypt.hexencode
local hashkey = crypt.hashkey
local randomkey = crypt.randomkey
local md5 = md5core.sumhexa

local db = {}

local function hash(key)
    local h = hashkey(key)
    return tonumber("0x"..hex(h):sub(9))
end

function db.query(uname)
    local h = hash(uname)
    local r = rdb.scr.query(uname, h)
    if r and #r >= 3 then
        local acc = {
            id = tonumber(r[1]),
            base = cjson.decode(r[2]),
            uinfo = cjson.decode(r[3]),
        }
        log.debug("base : %s", r[2])
        log.debug("uinfo : %s", r[3])
        if r[4] then
            acc.third = cjson.decode(r[4])
        end
        return acc
    end
end

function db.query3rd(third)
    local h = hash(third.uid)
    local r = rdb.scr.query3rd(third.name, third.uid, h)
    if r and #r >= 3 then
        return tonumber(r[1]), cjson.decode(r[2]), cjson.decode(r[3])
    end
end

function db.refresh3rd(userid, third, uinfo)
    local index = math.floor(userid/1024)
    local keys = {
        string.format("account:%d:uinfo", index),
        string.format("account:%d:third", index),
    }
    local ops = {}
    if uinfo then
        log.debug("refresh3rd %d uinfo %s", userid, cjson.encode(uinfo))
        table.insert(ops, {"hset", keys[1], userid, cjson.encode(uinfo)})
    end
    if third then
        log.debug("refresh3rd %d third %s", userid, cjson.encode(third))
        table.insert(ops, {"hset", keys[2], userid, cjson.encode(third)})
    end
    if #ops > 1 then
        table.insert(ops, 1, {"multi"})
        table.insert(ops, {"exec"})
    end
    rdb.db:pipeline(ops)
end

local function refreshbase(baseinfo, userid)
    local index = math.floor(userid / 1024)
    local key = string.format("account:%d:base", index)
    rdb.db:hset(key, userid, cjson.encode(baseinfo))
end

function db.querybyuid(userid)
    local index = math.floor(userid / 1024)
    local key = string.format("account:%d:base", index)
    local r = rdb.db:hget(key, userid)
    if r then
        local base = cjson.decode(r)
        return base
    end
end

function db.blacklist(userid)
    local base = db.querybyuid(userid)
    if base then
        base.forbidden = true
        refreshbase(base, userid)

        return true
    end
end

function db.isInblacklist(userid)
    local base = db.querybyuid(userid)
    if base then
        return base.forbidden
    end
end

function db.whitelist(userid)
    local base = db.querybyuid(userid)
    if base then
        base.forbidden = false
        refreshbase(base, userid)

        return true
    end
end

function db.register3rd(third, uinfo)
    local h = hash(third.uid)
    --generate a base info of myown
    local base = {
        uname = rdb.scr.unique_username(),
        password = md5(randomkey()),
        salt = hex(randomkey()),
        time = math.floor(skynet.time()),
        forbidden = false
    }
    uinfo = uinfo or {
        uname = base.uname,
        sex = 0,
        head = "null"
    }
    local base_json = cjson.encode(base)
    local uinfo_json = cjson.encode(uinfo)
    local third_json = cjson.encode(third)
    local userid = rdb.scr.register3rd(third.name, third.uid, 
        h, uinfo.uname, hash(uinfo.uname), base_json, uinfo_json, third_json)
    log.debug("register3d, raw info base: %s, uinfo: %s, third: %s", base_json, uinfo_json, third_json)
    return userid, base, uinfo
end

function db.get_accinfo(userid)
    local index = math.floor(userid / 1024)
    local key = string.format("account:%d:uinfo", index)
    local r = rdb.db:hget(key, userid)
    if r then
        local user = cjson.decode(r)
        user.id = userid
        local base = db.querybyuid(userid)
        user.forbidden = base.forbidden
        return user
    end
end

function db.query_by_uname(uname)
    local h = hash(uname)
    local r = rdb.scr.query(uname, h)

    local users = {}
    for _, u in ipairs( r ) do
        local uinfo = cjson.decode(u[3])
        uinfo.id = tonumber(u[1])
        uinfo.forbidden = cjson.decode(u[2]).forbidden
        table.insert(users, uinfo)
    end

    return users
end

function db.get_lotsofaccinfo(userids)
    local ops = {}
    local index
    local key
    for _, v in ipairs(userids) do
        index = math.floor(v / 1024)
        key = string.format("account:%d:uinfo", index)
        table.insert(ops, {"hget", key, v})
    end
    local infos = {}
    if #ops > 0 then
        local rets = rdb.db:pipeline(ops, {})
        for i, ret in ipairs(rets) do
            if ret[i].ok and ret[i].out then
                local r = ret[i].out
                r.userid = userids[i]
                table.insert(infos, r)
            end
        end
    end
    return infos
end

rdb.init {
    name = "account",
    command = db,
}

