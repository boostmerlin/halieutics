local skynet = require "skynet"
local cjson = require "cjson"
local rdb = require "common.redisdb"
local log = require "common.log"

local str_format = string.format
local m_floor = math.floor
local tbl_insert = table.insert

local json_enc = cjson.encode
local json_dec = cjson.decode

local db = {}

local cmd_multi = rdb.cmd_multi
local cmd_exec = rdb.cmd_exec

local function hashid(id)
    return m_floor(tonumber(id) / 1024)
end

function db.add_lastest_login(userid)
    local tm = m_floor(skynet.time())
    rdb.scr.add_lastest_login(userid, tm, 500)
end

function db.get_lastest_login(userid, max)
    local stop = max and max-1 or -1
    local r = rdb.db:zrevrange("login:lastest", 0, stop)
    if r and #r then
        local ret = {}
        for _, uid in ipairs(r) do
            tbl_insert(ret, tonumber(uid))
        end
        return ret
    end
end

function db.create_desk(info)
    --[[
    local guid = rdb.scr.create_desk(info.id, json_enc(info))
    return tonumber(guid)
    ]]
    info.guid = tonumber(rdb.db:incr "desk:guid:counter")
    local ops = {
        {"set", str_format("desk:%d:info", info.id), json_enc(info)},
        {"sadd", "desk:active", info.id},
    }
    rdb.db:pipeline(ops)
    return tonumber(info.guid)
end


function db.free_desk(deskid)
    local keys = {
        str_format("desk:%d:info", deskid),
        str_format("desk:%d:attr", deskid),
        str_format("desk:%d:seat", deskid),
        str_format("desk:%d:user", deskid),
        str_format("desk:%d:cost", deskid),
    }
    local ops = {cmd_multi, {"srem", "desk:active", deskid}}
    for _, k in ipairs(keys) do
        tbl_insert(ops, {"del", k})
    end
    tbl_insert(ops, cmd_exec)
    rdb.db:pipeline(ops)
end

function db.get_active_desks()
    local result = rdb.db:smembers "desk:active"
    if result and #result > 0 then
        local ret = {}
        for _, id in ipairs(result) do
            ret[tonumber(id)] = true
        end
        return ret
    end
end

function db.add_cost(deskid, cost)
    local key = str_format("desk:%d:cost", deskid)
    rdb.db:lpush(key, json_enc(cost))
end

function db.save_costs(deskid, costs)
    local key = str_format("desk:%d:cost", deskid)
    if costs and #costs > 0 then
        local ops = {
            cmd_multi, 
            {"del", key},
        }
        for _, c in ipairs(costs) do
            tbl_insert(ops, {"lpush", key, json_enc(c)})
        end
        tbl_insert(ops, cmd_exec)
        rdb.db:pipeline(ops)
    else
        rdb.db:del(key)
    end
end

function db.add_user(deskid, user)
    local key = str_format("desk:%d:userid", deskid)
    rdb.db:hset(key, user.id, cjson.encode(user))
end

function db.remove_user(deskid, userid)
    local key = str_format("desk:%d:userid", deskid)
    rdb.db:hdel(key, userid)
end

function db.start(deskid)
    local key = str_format("desk:%d:attr", deskid)
    rdb.db:hset(key, "start", 1)
end

function db.isstart(deskid)
    local key = str_format("desk:%d:attr", deskid)
    local r = rdb.db:hget(key, "start")
    return tonumber(r) == 1
end

function db.get_desk_info(deskid)
    local key = str_format("desk:%d:info", deskid)
    local r = rdb.db:get(key)
    if r then
        return json_dec(r)
    end
end

function db.restore_desk(deskid)
    local ops = {
        {"hgetall", str_format("desk:%d:attr", deskid)},
        {"hgetall", str_format("desk:%d:userid", deskid)},
        {"lrange", str_format("desk:%d:cost", deskid), 0, -1},
    }
    local ret = rdb.db:pipeline(ops, {})

    local desk = {}
    if ret[1].ok and ret[1].out then
        local r = ret[1].out
        for i=1, #r, 2 do
            desk[r[i]] = r[i+1]
        end
    end
    if ret[2].ok and ret[2].out then
        desk.users = {}
        local r = ret[2].out
        for i=1, #r, 2 do
            local info = cjson.decode(r[i+1])
            desk.users[info.id] = {userid = tonumber(r[i]), info=info}
        end
    end
    if ret[3].ok and ret[3].out then
        desk.costs = {}
        for _, r in ipairs(ret[3].out) do 
            tbl_insert(desk.costs, json_dec(r))
        end
    end

    return desk
end


function db.add_feedback(userid, content)
    local id = rdb.db:incr "feedback:id:counter"
    local index = hashid(id)
    local ops = {
        {"lpush", "feedback:open", id},
        {"hset", str_format("feedback:%d:info", index), id, json_enc{from = userid, content = content}},
    }
    rdb.db:pipeline(ops)
end

function db.save_game_result(guid, info)
    local ops = {
        {"set", str_format("desk:%d:result", guid), json_enc(info)},
    }

    local score = m_floor(skynet.time())
    for _, u in ipairs(info.users) do
        tbl_insert(ops, {"zadd", str_format("desk:%d:mygame", u.id), score, guid})
    end

    rdb.db:pipeline(ops)
end

function db.get_mygame_results(userid)
    local key = str_format("desk:%d:mygame", userid)
    local deskguids = rdb.db:zrange(key, 0, 50)
    local mygames = {}
    for _, v in ipairs(deskguids) do
        local ret = rdb.db:get(str_format("desk:%d:result", v))
        tbl_insert(mygames, json_dec(ret))
    end
    return mygames
end

rdb.init {
    app = tostring(...), 
    name = "game",
    command = db,
}

