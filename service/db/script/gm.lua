local scr = {
    --[[
        ARGV[1]: userid number
        ARGV[2]: datestr str
        ARGV[3]: propid str
        ARGV[4]: num number
        ARGV[5]: price number
        ARGV[6]: timestamp number
    ]]
    buy_item = [[
        redis.call("SETNX", "recharge:id:counter", 1000)
        local orderid = redis.call("INCR", "recharge:id:counter")
        orderid = ARGV[2]..orderid

        local key = "recharge:"..ARGV[1]
        redis.call("RPUSH", key, orderid)

        local t = {"prop", ARGV[3],"num", ARGV[4],"price", ARGV[5]
        , "timestamp", ARGV[6], "userid", ARGV[1], "status", "unpayed"}

        redis.call("HMSET", orderid, unpack(t))

        return orderid
    ]],
}

return scr