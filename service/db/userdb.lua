local skynet = require "skynet"
local cjson = require "cjson"
local rdb = require "common.redisdb"
local utils = require "common.utils"
local log = require "common.log"

local str_format = string.format
local os_date = os.date
local tbl_insert = table.insert
local tbl_unpack = table.unpack
local tbl_sort = table.sort
local json_dec = cjson.decode
local json_enc = cjson.encode
local m_floor = math.floor


local userdb = {}

local max_user_history = 50
local max_redpacket_notify = 20
local MAX_MAIL_EXPIRE = utils.DAY * 7

local cmd_multi = rdb.cmd_multir
local cmd_exec = rdb.cmd_exec

local function get_date()
    local now = math.floor(skynet.time())
    return os_date("*t", now)
end

local function hashid(id)
    return math.floor(tonumber(id) / 1024)
end

local function get_user_by_index_f(name, conv)
    local key_fmt = "user:%d:" .. name
    return function(userid)
        local db = assert(rdb.db[userid])
        local index = hashid(userid)
        local key = str_format(key_fmt, index)
        local r = db:hget(key, userid)
        if r and conv then
            return conv(r)
        end
        return r
    end
end

local function set_user_by_index_f(name, conv)
    local key_fmt = "user:%d:" .. name
    return function(userid, value)
        local db = assert(rdb.db[userid])
        local index = hashid(userid)
        local key = str_format(key_fmt, index)
        value = conv and conv(value) or value
        db:hset(key, userid, value)
    end
end

local function update_user_by_index_f(name)
    local key_fmt = "user:%d:" .. name
    return function(userid, value)
        local db = assert(rdb.db[userid])
        local index = hashid(userid)
        local key = str_format(key_fmt, index)
        return tonumber(db:hincrby(key, userid, value))
    end
end

userdb.get_avatar = get_user_by_index_f("info", json_dec)
userdb.set_avatar = set_user_by_index_f("info", json_enc)

function userdb.add_avatar(userid, uinfo)
    set_user_by_index_f(userid, uinfo)
end

function userdb.get_account(userid)
    local db = assert(rdb.db[userid])
    local key = str_format("user:%d:bag", userid)
    local r = db:hmget(key, "diamond")
    return {
        diamond = r[1] and tonumber(r[1]) or 0,
    }
end


function userdb.create_desk(userid, deskid)
    local db = assert(rdb.db[userid])
    local key = str_format("user:%d:create:desk", userid)
    db:sadd(key, deskid)
end

function userdb.join(userid, deskid)
    local db = assert(rdb.db[userid])
    local index = hashid(userid) 
    local key = str_format("user:%d:active:desk", index)
    db:hset(key, userid, deskid)
end

function userdb.leave(userid)
    local db = assert(rdb.db[userid])
    local index = hashid(userid)
    local key = str_format("user:%d:active:desk", index)
    db:hdel(key, userid)
end

function userdb.dismiss(userid, deskid)
    local db = assert(rdb.db[userid])
    local key = str_format("user:%d:create:desk", userid)
    db:srem(key, deskid)
end

function userdb.get_mydesk(userid)
    local scr = assert(rdb.scr[userid])
    local result = scr.get_mydesk(userid)
    if result then
        local ret = {}
        if #result[1] > 0 then
            ret.active = tonumber(result[1][1])
        end
        if result[2] and #result[2] > 0 then
            ret.create = {}
            for _, id in ipairs(result[2]) do
                tbl_insert(ret.create, tonumber(id))
            end
        end
        return ret
    end
end

function userdb.get_create_desk(userid)
    local db = assert(rdb.db[userid])
    local key = str_format("user:%d:create:desk", userid)
    local result = db:smembers(key)
    if result and #result > 0 then
        local ret = {}
        for _, id in ipairs(result) do
            tbl_insert(ret, tonumber(id))
        end
        return ret
    end
end

function userdb.get_active_desk(userid)
    local db = assert(rdb.db[userid])
    local index = hashid(userid)
    local key = str_format("user:%d:active:desk", index)
    return tonumber(db:hget(key, userid))
end

function userdb.get_create_desk_num(userid)
    local db = assert(rdb.db[userid])
    local key = str_format("user:%d:create:desk", userid)
    return tonumber(db:scard(key)) or 0
end


function userdb.get_user_bag(userid)
    local db = assert(rdb.db[userid])
    local key = str_format("user:%d:bag", userid)
    local r = db:hgetall(key)
    if r and #r > 0 then
        local bag = {}
        local n = #r / 2
        for i=1, n do
            local idx = (i - 1) * 2
            tbl_insert(bag, {
                id = r[idx+1],
                num = tonumber(r[idx+2]),
            })
        end
        return bag
    end
end

function userdb.get_user_prop(userid, id)
    local db = assert(rdb.db[userid])
    local key = str_format("user:%d:bag", userid)
    return tonumber(db:hget(key, id)) or 0
end

function userdb.get_user_props(userid, s)
    local db = assert(rdb.db[userid])
    local key = str_format("user:%d:bag", userid)
    local r = db:hmget(key, tbl_unpack(s))
    local result = {}
    for i, k in ipairs(s) do
        result[k] = tonumber(r[i]) or 0
    end
    return result
end

function userdb.add_prop(userid, id, num)
    local db = assert(rdb.db[userid])
    local key = str_format("user:%d:bag", userid)
    return tonumber(db:hincrby(key, id, num))
end

function userdb.add_props(userid, m)
    local db = assert(rdb.db[userid])
    local key = str_format("user:%d:bag", userid)
    local s = {}
    local ops = {}
    for id, n in pairs(m) do
        tbl_insert(ops, {"hincrby", key, id, n})
        tbl_insert(s, id)
    end
    local r = db:pipeline(ops, {})
    local result = {}
    for i, id in ipairs(s) do
        result[id] = r[i].ok and tonumber(r[i].out) or 0
    end
    return result
end

function userdb.use_prop(userid, id, num)
    num = num or 0
    local scr = assert(rdb.scr[userid])
    log.debug("[userdb.use_prop] from: %d, prop: %s, num: %d", userid, id, num)
    local n = tonumber(scr.use_prop(userid, id, num))
    return n
end

function userdb.add_record(userid, name, val)
    local db = assert(rdb.db[userid])
    local n = val or 1
    local ops = {}
    local keys = {
        {str_format("urecord:%d", userid)},
    }
    local buffer = type(name) == "table" and name or {name}
    for _, rn in ipairs(buffer) do
        for _, k in ipairs(keys) do
            tbl_insert(ops, {"hincrby", k[1], rn, n})
        end
    end
    db:pipeline(ops)
end


local cycle_func = {
    hour = utils.get_hour_guid,
    day = utils.get_day_guid,
    week = utils.get_week_guid,
    month = utils.get_month_guid,
}

function userdb.get_record(userid, name, cycle, arg)
    local db = assert(rdb.db[userid])
    local cf = cycle_func[cycle]
    local key = str_format("urecord:%d", userid)
    return tonumber(db:hget(key, name)) or 0
end

-- mark: name@type
local function get_mark_kf(userid, ty, name, cycle, arg)
    local cf = cycle_func[cycle]
    local key =  cf and str_format("umark:%d:%s", userid, cf(arg)) or str_format("umark:%d", userid)
    local field = str_format("%s@%s", name, ty) 
    return key, field
end

function userdb.add_mark(userid, ty, name, cycle, val)
    local db = assert(rdb.db[userid])
    local key, field = get_mark_kf(userid, ty, name, cycle)
    db:hset(key, field, val or 1)
end

function userdb.get_mark(userid, ty, name, cycle, arg)
    local db = assert(rdb.db[userid])
    local key, field = get_mark_kf(userid, ty, name, cycle, arg)
    return db:hget(key, field)
end

function userdb.clear_mark(userid, ty, name, cycle)
    local db = assert(rdb.db[userid])
    local key, field = get_mark_kf(userid, ty, name, cycle)
    db:hdel(key, field)
end

function userdb.get_user_game_info(userid)
    local db = assert(rdb.db[userid])
    local ops = {
        {"hget", str_format("urecord:%d", userid), "win"},
        {"hget", str_format("urecord:%d", userid), "lost"},
    }
    local r = db:pipeline(ops, {})
    if r then
        return {
            win = r[1].ok and tonumber(r[1].out) or 0,
            lost = r[2].ok and tonumber(r[2].out) or 0,
        }
    end
end

function userdb.invite_bind(userid, recode)
    local db = assert(rdb.db[userid])
    local index = hashid(userid)
    local key = str_format("user:%d:invite:recode", index)
    db:hset(key, userid, recode)
end

function userdb.get_bind_recode(userid)
    local db = assert(rdb.db[userid])
    local index = hashid(userid)
    local key = str_format("user:%d:invite:recode", index)
    return db:hget(key, userid)
end

function userdb.get_invite_parent(userid)
    local db = assert(rdb.db[userid]) 
    local index = hashid(userid)
    local key = str_format("user:%d:invite:parent", index)
    return tonumber(db:hget(key, userid))
end

function userdb.get_invite_children(userid)
    local db = assert(rdb.db[userid])
    local key = str_format("user:%d:invite:children", userid)
    local result = db:zrange(key, 0, -1)
    if result and #result > 0 then
        local ret = {}
        for _, id in ipairs(result) do
            tbl_insert(ret, tonumber(id))
        end
        return ret
    end
end

function userdb.is_invite_child(userid, child)
    local db = assert(rdb.db[userid])
    local key = str_format("user:%d:invite:children", userid)
    return db:zrank(key, child)
end

rdb.init {
    app = tostring(...),
    name = "user",
    select_f = function(n)
        return function(id)
            local idx = tonumber(id) % n
            return idx + 1
        end
    end,
    command = userdb,
}

