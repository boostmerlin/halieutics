local scr = {
    --[[
        ARGV[1]: uinfo.uname
        ARGV[2]: hash(uinfo.uname)
    ]]
    query = [[
        local maxsize = 1024
        local pattern = string.format("nick:*%s*", ARGV[1])
        local nickkeys = redis.call("SCAN", 0, "MATCH", pattern)
        local r = {}
        nickkeys = nickkeys[2]
        for _, key in ipairs(nickkeys) do
            local ids = redis.call("SMEMBERS", key)
            for _, id in ipairs( ids ) do
                local rr = {id}
                local idx = math.floor(tonumber(id)/maxsize)
                local keys = {
                    string.format("account:%d:base", idx),
                    string.format("account:%d:uinfo", idx),
                }
                for _, k in ipairs(keys) do
                    local v = redis.call("HGET", k, id) 
                    table.insert(rr, v)
                end
                table.insert(r, rr)
            end
        end
        return r
    ]],

    --[[
        ARGV[1] third.name 
        ARGV[2] third.uid 
        ARGV[3] hash(third.uid)
    ]]
    query3rd = [[
        local maxsize = 1024
        local maxblock = 10000
        local index = tonumber(ARGV[3]) % maxblock 
        local subindex = 1
        while true do
            local key = string.format("acc3rd:%s:%d:%d", ARGV[1], index, subindex)
            local r = redis.call("EXISTS", key)
            if r == 1 then 
                local id = redis.call("HGET", key, ARGV[2])
                if id then
                    local idx = math.floor(tonumber(id)/maxsize)
                    local keys = {
                        string.format("account:%d:base", idx),
                        string.format("account:%d:uinfo", idx),
                    }
                    return {id, redis.call("HGET", keys[1], id), redis.call("HGET", keys[2], id)}
                end
                subindex = subindex + 1
            else
                break
            end
        end
    ]],

    unique_username = [[
        redis.call("SETNX", "account:guid", 0x01fd3a7b)
        local id = tonumber(redis.call("INCR", "account:guid"))
        math.randomseed(id)
        local x = math.random(0x0101, 0x7fff)
        local y = math.random(0x0101, 0xffff)
        return string.format("%04x%08x%04x", x, id, y)
    ]],


    --[[
        ARGV[1] third.name 
        ARGV[2] third.uid 
        ARGV[3] hash(third.uid)
        ARGV[4] uinfo.uname
        ARGV[5] hash(uinfo.uname)
        ARGV[6] json{acc.base}
        ARGV[7] json{acc.uinfo}
        ARGV[8] json{acc.third}
    ]]
    register3rd = [[
        local maxsize = 1024
        local maxblock = 10000
        redis.call("SETNX", "account:id:counter", 1000000)
        local id = tonumber(redis.call("INCR", "account:id:counter"))


        local nickkey = string.format("nick:%s", ARGV[4])
        redis.call("SADD", nickkey, id)

        local index = tonumber(ARGV[3]) % maxblock 
        local subindex = 1
        while true do
            local key = string.format("acc3rd:%s:%d:%d", ARGV[1], index, subindex)
            local size = redis.call("HLEN", key) or 0
            if size < maxsize then
                redis.call("HSET", key, ARGV[2], id)
                break
            end
            subindex = subindex + 1
        end

        local index = math.floor(id/maxsize)
        local keys = {
            string.format("account:%d:base", index),
            string.format("account:%d:uinfo", index),
            string.format("account:%d:third", index),
        }
        for i, key in ipairs(keys) do
            redis.call("HSET", key, id, ARGV[5+i])
        end

        return id
    ]],
}
return scr

