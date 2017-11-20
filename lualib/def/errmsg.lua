
local err = {
    invalid_request = {code = 40001, msg = "无效的请求"},
    secret_expire = {code = 40002, msg = "与服务器断开连接,请重新登录"},
    invalid_secret = {code = 40003, msg = "用户令牌失效或者过期,请重新登录"},
    repeat_login = {code = 40004, msg = "用户已登录"},
    unauth = {code = 40005, msg = "认证失败,不存在的用户或错误的口令"},
    server_busy = {code = 40006, msg = "系统繁忙,请稍后再试"},
    other_login = {code = 40007, msg = "用户在其他地方登录"},
    old_version = {
        android = {code = 40008, msg = "客户端当前版本过低,请前往xxx下载最新版本!"},
        ios = {code = 40008, msg = "客户端当前版本过低,请前往AppStore下载最新版本!"},
    },
    shutdown = {code = 40009, msg = "服务器暂停服务,请稍后再试!"},
    token_expire = { code = 40010, msg = "微信token过期需要重新验证"},
    in_blacklist = { code = 40011, msg = "你的号已被封禁，请联系客服"},
    no_version_found = { code = 40012, msg = "不存在的版本"},


    create_limit = {code = 40101, msg = "您创建房间数量已达上限"},
    join_limit = {code = 40102, msg = "您只能加入或者创建一个房间"},
    desk_full = {code = 40103, msg = "房间人员已满"},
    no_free_desk = {code = 40104, msg = "当前没有可用的房间或指定的参数不存在"},
    chat_frequent = {code = 40105, msg = "发送消息过于频繁,请休息一会"},
    user_not_ready = {code = 40106, msg = "当前有玩家未准备"},
    already_in_game = {code = 40107, msg = "游戏已经开始了"},
    already_in_desk = {code = 40108, msg = "自己已经在桌内了"},
    already_joined = {code = 40110, msg = "已经在房间内了"},
    not_joined = {code = 40111, msg = "未在房间内，无法坐下"},
    banker_no_fire = {code = 40109, msg = "庄家不能开火"},
    seat_full = {code = 401112, msg = "坐位已经满了"},
    standup_before_leave = {code = 401113, msg = "先站起才能离开"},
    repeat_seat = {code = 401114, msg = "重复坐下"},
    seat_taken = {code = 401115, msg = "该坑有人"},
    game_too_short = {code = 401116, msg = "游戏剩余时间不足"},
    audience_cant_fire = {code = 401117, msg = "观众不能开火"},
    not_sitdown = {code = 401118, msg = "没有坐下，不必战起"},

    prop_lack = {code = 40201, msg = "您的%s不足"},

    app_noexists = {code = 40401, msg = "不存在的游戏"},
    platform_noexists = {code = 40402, msg = "不支持当前客户端系统"},
    desk_noexists = {code = 40403, msg = "桌子不存在或已解散"},
    desk_no_user = {code = 40407, msg = "你不能跟自己玩"},
    card_lack = {code = 40404, msg="房卡不足，请充值"},
    invalid_recode = {code = 40405, msg = "邀请码错误不是5位"},
    buy_error = {code = 40406, msg = "购买失败"},
    invalid_reqparam = {code = 40407, msg = "无效的参数"},

    dismiss_already = {code = 40408, msg = "正在解散"},
    dismiss_no_ins = {code = 40409, msg = "没有解散实例"},
    dismiss_no_user = {code = 40410, msg = "no dimiss user."},
    not_in_desk = {code = 40411, msg = "not in desk."},

}

return err

