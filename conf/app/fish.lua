return {
-- 服务器版本
version = {ios = 1, android = 1},

-- 当前app包含的游戏
games = {"fish"},

-- 当前app的网关
gates = {
    android = {
        {name = "chengdu", ip = "192.168.31.129", port = 16001, maxload = 1024},
    },
    ios = {
        {name = "chengdu", ip = "192.168.31.128", port = 17001, maxload = 1024},
    },
},

-- 数据库配置
db = {
    user = {
      --  "1@127.0.0.1:8802",
        "1@127.0.0.1:8803", 
        "1@127.0.0.1:8804",
    },
    game = "0@127.0.0.1:8802",
},

-- balance负载均衡系统实例配置
instance = {
    userdb = 2,
    gamedb = 1,
},

-- 当前app使用的第三方SDK配置 
third = {
    weixin = {
        appid = "wxeb3851a3318fab86",
        appsecret = "fcab6854f292e76ff761e9844445e65d",
    },
},


proptype = {
    diamond = "diamond"
},

props = {
    ["diamond"] = {name = "房卡", unit = "ge", record = {get = "g:diamond", use = "u:diamond"}},
},

-- 限制配置
limit = {
    create = 3,
},

broadcast = {
    system = {sign = "notice", color = 0xff0000},
    marquee = {sign = "smallhorn", color = 0xffff00},
},

--mod name
shop = {
    diamond = "shopcfg.json",
},

notice = {
    --this name is the same as first node in json.
    system = "notice.json",
    share = "shareinfo.json"
},

gameplay = {
    --config name
    createroom = "createroom.json",
    play = "play.json",
},

-- 邀请
invite = {
    bind = {diamond = 8},
    progress = {
        {cond = {cycle = "once", record = "recharge", value = 1}, awards = {diamond = 0.1}},
        {cond = {cycle = "once", record = "recharge", value = 3}, awards = {diamond = 0.2}},
        {cond = {cycle = "once", record = "recharge", value = 5}, awards = {diamond = 0.3}},
    },
},

}

