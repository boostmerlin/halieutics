local scr = {
    --[[
        ARGV[1]: type
        ARGV[2]: userid
        ARGV[3]: nuse
        ARGV[4]: history.json
    ]]
    use_account = [[
        local ty = ARGV[1]
        local userid = tonumber(ARGV[2])
        local nuse = tonumber(ARGV[3])
        local index = math.floor(userid/1024)
        local key = string.format("user:%d:%s", index, ty)
        local n = tonumber(redis.call("HGET", key, userid)) or 0
        local left = n - nuse
        if left >= 0 then
            local key2 = string.format("user:%d:%s:history", userid, ty)
            redis.call("HSET", key, userid, left)
            redis.call("LPUSH", key2, ARGV[4])
        end
        return left 
    ]],

    --[[
        ARGV[1]: userid
        ARGV[2]: propid
        ARGV[3]: num
    ]]
    use_prop = [[
        local num = tonumber(ARGV[3])
        local key = string.format("user:%s:bag", ARGV[1])
        local n = tonumber(redis.call("HGET", key, ARGV[2])) or 0
        local left = n - num
        if left >= 0 then
            redis.call("HSET", key, ARGV[2], left)
        end
        return left
    ]],

    --[[
        ARGV[1]: userid
    ]]
    get_mydesk = [[
        local userid = tonumber(ARGV[1])
        local index = math.floor(userid/1024)
        local key = string.format("user:%d:active:desk", index)
        local ret = {{}}
        local id = redis.call("HGET", key, userid)
        if id then
            table.insert(ret[1], id)
        end
        local key = string.format("user:%d:create:desk", userid)
        ret[2] = redis.call("SMEMBERS", key)
        return ret
    ]],

    --[[
        ARGV[1]: key
        ARGV[2]: value
        ARGV[3]: maxd
    ]]
    lpush_max = [[
        local len = tonumber(redis.call("LPUSH", ARGV[1], ARGV[2]))
        local max = tonumber(ARGV[3])
        if len > max then
            redis.call("LTRIM", ARGV[1], 0, max-1)
        end
    ]],

}

return scr

