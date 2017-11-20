local scr = {}

--[[
    ARGV[1]: deskid
    ARGV[2]: info.json 
]]
scr.create_desk = [[
    if #ARGV < 2 then 
        return 
    end
    local guid = redis.call("INCR", "desk:guid:counter")
    local key = "desk:" .. ARGV[1] .. ":info"
    redis.call("SET", key, ARGV[2])
    redis.call("SADD", "desk:active", ARGV[1])
    return guid
]]

--[[
    ARGV[1]: userid
    ARGV[2]: time
    ARGV[3]: max
]]
scr.add_lastest_login = [[
    local key = "login:lastest"
    redis.call("ZADD", key, ARGV[2], ARGV[1])
    local n = tonumber(redis.call("ZCARD", key))
    if n > tonumber(ARGV[3]) then
        redis.call("ZREMRANGEBYRANK", key, -1, -1)
    end
]]


return scr

