local skynet = require "skynet"
local cjson = require "cjson"
local rdb = require "common.redisdb"
local log = require "common.log"

local db = {}

local cmd_multi = {"multi"}
local cmd_exec = {"exec"}

local tbl_insert = table.insert

local function read_table(t)
    local result = { }
    for i = 1, #t, 2 do result[t[i]] = t[i + 1] end
    return result
end

function db.get_untreated_order(orderid)
    local ops = {
        {"sismember", "recash:order:untreated", orderid},
        {"hmget", "recash:order:"..orderid, "userid", "app", "count", "time"},
    }
    local ret = rdb.db:pipeline(ops, {})
    if ret[1].ok and ret[1].out == 1 then
        if ret[2].ok and ret[2].out then
            local r = ret[2].out
            if #r >= 4 then
                return {
                    userid = tonumber(r[1]),
                    app = r[2],
                    count = tonumber(r[3]),
                    time = tonumber(r[4]),
                }
            end
        end
    end
end

function db.get_all_untreated()
    return rdb.db:smembers "recash:order:untreated"
end


function db.check_order_repeat(orderid)
    return rdb.db:sismember("recash:order:treated", orderid)
end

function db.add_error_order(orderid, reason)
    local info = cjson.encode{id = orderid, reason = reason}
    local ops = {
        cmd_multi,
        {"srem", "recash:order:untreated", orderid},
        {"lpush", "recash:order:error", info},
        cmd_exec,
    }
    rdb.db:pipeline(ops)
end

function db.treate_order(orderid)
    local ops = {
        cmd_multi,
        {"srem", "recash:order:untreated", orderid},
        {"sadd", "recash:order:treated", orderid},
        cmd_exec,
    }
    rdb.db:pipeline(ops)
end

function db.get_broadcast(class)
    local key 
    if class ~= "all" then
        key = string.format("notice:%s:broadcast", class)
    else
        key = "notice:broadcast"
    end
    local msg = rdb.db:lpop(key)
    if msg then
        return cjson.decode(msg)
    end
end

function db.get_activity_all_notices(class)
    local key = string.format("act:%s:notice", class)
    local result = rdb.db:smembers(key)
    if result and #result > 0 then
        local buffer = {}
        for _, id in ipairs(result) do
            local key = string.format("act:notice:%s", id)
            local ret = rdb.db:hmget(key, "class", "type", "content", "expire")
            if ret and #ret == 4 then
                tbl_insert(buffer, {
                    id = tonumber(id),
                    class = ret[1],
                    type = ret[2],
                    content = ret[3],
                    expire = tonumber(ret[4]),
                })
            else
                log.error("invalid activity notice: %s", ret or "null")
            end
        end
        return buffer
    end
end

function db.get_activity_notice(id)
    local key = string.format("act:notice:%s", tostring(id))
    local result = rdb.db:hmget(key, "class", "type", "content", "expire")
    if result then
        if #result == 4 then
            return {
                id = tonumber(id),
                class = result[1],
                type = result[2],
                content = result[3],
                expire = result[4]
            }
        else
            log.error("invalid activity notice: %s %s", tostring(id), table.concat(result, " "))
        end
    end
end

function db.remove_activity_notice(class, id)
    local key = string.format("act:%s:notice", class)
    rdb.db:srem(key, id)
end

function db.set_shutdown_status(st)
    if st then
        rdb.db:set("shutdown:status", st)
    else
        rdb.db:del "shutdown:status"
    end
end

function db.buy(item, userid)
    local scr = assert(rdb.scr)

    local timestamp = math.floor(skynet.time())
    local datestr = os.date("%Y%m%d")

    local orderid = scr.buy_item(userid, datestr, item.prop, item.num, item.price, timestamp)

    return orderid
end

function db.appleswitch(class, ver, stat)
    local key = string.format("appleswitch:%s", class)
    if not stat then --get
        local ret = {}
        if ver then
            stat = rdb.db:hget(key, ver)
            if stat then
               table.insert(ret, {ver=ver, stat=tonumber( stat )})
            end
        else
            local map = rdb.db:hgetall(key)
            for i=1, #map, 2 do
                table.insert(ret, {ver=map[i], stat=tonumber(map[i+1])})
            end
        end
        return ret
    else
        rdb.db:hset(key, ver, stat)
        return stat
    end
end

function db.get_all_recharge_orders(userid)
    local key = "recharge:"..userid
    local orderids = rdb.db:lrange(key, 0, -1)
    local ops = {cmd_multi}
    for _, v in ipairs(orderids) do
        tbl_insert(ops, {"HGETALL", v})
    end
    tbl_insert(ops, cmd_exec)
    local ret = rdb.db:pipeline(ops)
      -- local t = {"prop", ARGV[3],"num", ARGV[4],"price", ARGV[5]
      --   , "timestamp", ARGV[6], "userid", ARGV[1], "status", "unpayed"}
    local orders = {}
    for i, v in ipairs(ret) do
        if v and #v > 0 then
            local t = read_table(v)
            t.orderid = orderids[i]
            tbl_insert(orders, t)
        end
    end
    return orders
end

function db.update_order(orderid)
    if not rdb.db:hget(orderid, "status") then
        return
    end
    rdb.db:hset(orderid, "status", "payed")

    return true
end

function db.update_stock(value)
    return rdb.db:incrby("fish:stock", value)
end

function db.get_stock()
    return rdb.db:get("fish:stock")
end

function db.set_stock(value)
    return rdb.db:set("fish:stock", value)
end

rdb.init {
    name = "gm",
    command = db,
}

