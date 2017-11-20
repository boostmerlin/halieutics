local skynet = require "skynet"
local cjson = require "cjson"
local rdb = require "common.redisdb"
local string = string

local db = {}

local cmd_multi = rdb.cmd_multi
local cmd_exec = rdb.cmd_exec

local odate = os.date
local function get_date()
    local now = math.floor(skynet.time())
    return odate("*t", now)
end

function db.save(type, game, tag)
    local d = get_date()
    local keys = {
        string.format("%s:count", type),
        string.format("%s:%d%02d:count", type, d.year, d.month),
        string.format("%s:%s:count", type, game),
        string.format("%s:%s:%d%02d:count", type, game, d.year, d.month),
        string.format("%s:%s:%d%02d%02d:count", type, game, d.year, d.month, d.day),
        string.format("%s:%s:%d%02d%02d:all", type, game, d.year, d.month, d.day),
    }
    local ops = {
        cmd_multi,
        {"incr", keys[1]},
        {"hincrby", keys[2], d.day, 1},
        {"incr", keys[3]},
        {"hincrby", keys[4], d.day, 1},
    }
    if type == "desk" then
        table.insert(ops, {"hincrby", keys[5], d.hour, 1})
        table.insert(ops, {"lpush", keys[6], tag})
    end
    table.insert(ops, cmd_exec)
    rdb.db:pipeline(ops)
end

function db.diamond(game, count)
    local d = get_date()
    local keys = {
        "diamond:count",
        string.format("diamond:%d%02d:count", d.year, d.month),
        string.format("diamond:%s:count", game),
        string.format("diamond:%s:%d%02d:count", game, d.year, d.month),
    }
    local ops = {
        cmd_multi,
        {"incrby", keys[1], count},
        {"hincrby", keys[2], d.day, count},
        {"incrby", keys[3], count},
        {"hincrby", keys[4], d.day, count},
        cmd_exec,
    }
    rdb.db:pipeline(ops)
end

function db.get_user(class)
    local d = get_date()
    local keys = {
        string.format("user:%s:count", class),
        string.format("user:%s:%d%02d:count", class, d.year, d.month),
    }
    local ops = {
        cmd_multi,
        {"get", keys[1]},
        {"hget", keys[2], d.day},
        cmd_exec,
    }
    local ret = rdb.db:pipeline(ops)
    return {user=tonumber(ret[1]), dayuser=tonumber(ret[2])}
end

-- record stat of user, like login times(counts)
function db.user(class, type)
    local d = get_date()
    local keys = {
        string.format("user:%s:count", class),
        string.format("user:%s:count", type),
        string.format("user:%s:%s:count", class, type),
        string.format("user:%d%02d:count", d.year, d.month),
        string.format("user:%s:%d%02d:count", class, d.year, d.month),
        string.format("user:%s:%d%02d:count", type, d.year, d.month),
        string.format("user:%s:%s:%d%02d:count", class, type, d.year, d.month),
    }
    local ops = {
        cmd_multi,
        {"incr", keys[1]},
        {"incr", keys[2]},
        {"incr", keys[3]},
        {"hincrby", keys[4], d.day, 1},
        {"hincrby", keys[5], d.day, 1},
        {"hincrby", keys[6], d.day, 1},
        {"hincrby", keys[7], d.day, 1},
        cmd_exec,
    }
    rdb.db:pipeline(ops)
end

function db.desks(class, n)
    local key = string.format("desks:%s", class)
    rdb.db:set(key, n)
end

function db.getonline(class)
    local key1 = string.format("desks:%s", class)
    local onlinedeskn = tonumber(rdb.db:get(key1))
    local key2 = string.format("online:%s", class)
    local online = cjson.decode(rdb.db:get(key2))
    return {online=online, onlinedeskn=onlinedeskn}
end

--{"android", 1}
function db.online(class, data)
  --  local d = get_date()
    local keys = {
        string.format("online:%s", class),
  --      string.format("online:%s:%d%02d%02d", class, d.year, d.month, d.day),
    }
    local data_json = cjson.encode(data)
  --  local time = string.format("%02d:%02d", d.hour, d.min)
    local ops = {
        cmd_multi,
        {"set", keys[1], data_json},
   --     {"hset", keys[2], time, data_json},
        cmd_exec,
    }
    rdb.db:pipeline(ops)
end

function db.resetactiveusers()
    local key = "activeusers"
    rdb.db:ltrim(key, 1, 0)
end

function db.addactiveusersrange(userinfos)
    local key = "activeusers"
    local len
    for _, v in ipairs(userinfos) do
        len = rdb.db:rpush(key, v)
    end
    return len or 0
end

function db.activeusers(from, to)
    assert(from and to)
    local key = "activeusers"
    local ret = rdb.db:lrange(key, from, to)
    local t = {}
    for _, v in ipairs(ret) do
        table.insert(t, cjson.decode(v))
    end
    return t
end

rdb.init {
    name = "stat",
    command = db,
}
