-- this configure save db better
return {
    login = 15032, 
    apps = {"fish"},
    db = {
        account = "0@127.0.0.1:8801",
        stat = "0@127.0.0.1:8804",
       -- boss = "8@127.0.0.1:8805",
        gm = "0@127.0.0.1:8805",
    },
    user3rd = {"weixin"},
    third = {
        weixin = {
            access_url = "https://api.weixin.qq.com/sns/oauth2/access_token",
            refresh_url = "https://api.weixin.qq.com/sns/oauth2/refresh_token",
            userinfo_url = "https://api.weixin.qq.com/sns/userinfo",
        },
    },
    instance = {
        auth = 1,
        weixin = 2,
        statdb = 1,
    },
}

