local skynet = require "skynet"
local sharedata = require "skynet.sharedata"
local cjson = require "cjson"
local service = require "common.service"
local webclient = require "common.webclient"
local log = require "common.log"
local em = require "def.errmsg"

local codedef = require "def.codedef"

local data = {}
local weixin = {}

function weixin.auth(app, info)
    assert(info.code, "weixin auth no code")
    log.debug("[weixin.auth] auth info codetype: %d, code %s", info.codetype, info.code)

    if codedef.TEST_FLAG then
        local t = {name = "weixin", uid = "111111122432234234"..info.code, info = {
        atk = "111111122434",
        rtk = "2234234234",
        oid = "111111122432234234"..info.code,
        exp = 30,
        rtm = math.floor(skynet.time()),
        name = "weixinnick",
        }}

        local urls = {"http://1.su.bdimg.com/icon/weather/a11.jpg", "http://1.su.bdimg.com/icon/weather/a1.jpg"}
        local gender = math.random(1, 2)
        local u = {
                uname = "weixinnick",
                head = urls[gender],
                sex = gender,
             }

        return t, u
    end

    local r
    if codedef.login_codetype_accesscode == info.codetype then
        local ok, resp = webclient.get(data.config.access_url, {
            appid = app.appid,
            secret = app.appsecret,
            code = info.code,
            grant_type = "authorization_code",
        })
        if ok then
            log.debug("[weixin.auth] weixin.access token: %s", resp)
            r = cjson.decode(resp)
        end
    else
        local ok, resp = webclient.get(data.config.refresh_url, {
            appid = app.appid,
            grant_type = "refresh_token",
            refresh_token = info.code,
        })
        if not ok then 
            log.warning("[weixin.auth] refresh_token failed for http error: %s", resp)
            return
        end
        r = cjson.decode(resp)
    end

    if r == nil or (r.errcode and r.errcode ~= 0) then 
        log.warning("[weixin.auth] get or refresh token failed")
        return false, em.token_expire
    end

    local third = {name = "weixin", uid = r.openid, info = {
        atk = r.access_token,
        rtk = r.refresh_token,
        oid = r.openid,
        exp = r.expires_in,
        rtm = math.floor(skynet.time()),
    }}

    local ok, resp = webclient.get(data.config.userinfo_url, {
        access_token = third.info.atk,
        openid = third.info.oid, 
    })

    if ok then
        resp = resp:gsub([[\/]], "/")
        log.debug("[weixin.auth] weixin.userinfo: %s", resp)
        local r = cjson.decode(resp)
        if r == nil or (r.errcode and r.errcode ~= 0) then
            return
        end
        third.uid = r.unionid
        local uinfo = {
            uname = r.nickname,
            sex = r.sex == 1 and r.sex or 2,
        }
        if r.headimgurl then
            local imgurl = r.headimgurl:sub(1, -2).."96"
            uinfo.head = imgurl
        end

        return true, third, uinfo 
    else
        log.error("[weixin.auth] userinfo error : %s", resp)
    end

end


service.init {
    command = weixin,
    init = function()
        local config = sharedata.query "sysconfig"
        data.config = assert(config.third.weixin)
    end
}