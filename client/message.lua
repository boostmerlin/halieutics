local skynet = require "skynet"
local sproto = require "sproto"
local socket = require "skynet.socket"
local proxy = require "common.socket_proxy"
local log = require "common.log"
local cjson = require "cjson"

local score = require "sproto.core"

local message = {}
local var = { 
        session_id = 0,
        session = {},
        socket = {},
        handler = {},
}

function message.init()
    var.proto_path = skynet.getenv "proto_path"

    local f = assert(io.open(var.proto_path .. "/login.sproto"))
    local data = f:read "a"
    f:close()
    local sp = sproto.parse(data)
    assert(sp:exist_type "package")
    assert(sp:exist_proto "login")
   -- score.dumpproto(sp.__cobj)
    var.login_host = sp:host "package"
    var.login_request = var.login_host:attach(sp) 

    local f = assert(io.open(var.proto_path .. "/gate.sproto"))
    local data = f:read "a"
    f:close()
    local sp = sproto.parse(data)
    var.gate_host = sp:host "package"
    var.gate_request = var.gate_host:attach(sp) 
end

function message.register(proto)
    local f = assert(io.open(string.format("%s/%s.s2c.sproto", var.proto_path, proto)))
    local data = f:read "a"
    f:close()
    var.host = sproto.parse(data):host "package"
    local f = assert(io.open(string.format("%s/%s.c2s.sproto", var.proto_path, proto)))
    local data = f:read "a"
    f:close()
    var.request = var.host:attach(sproto.parse(data))
end

function message.peer(address)
    local ip, port = address:match("([^:]+):([^:]+)")
        var.ip = ip
        var.port = tonumber(port)
end

function message.bind(obj, event)
        var.handler[obj] = event
end

local socket_error = setmetatable({}, {__tostring = function() return "[socket error]" end})
local function assert_socket(service, v, fd)
        if v then
                return v
        else
                log.error("%s socket (fd=%d) error", service, fd)
                error(socket_error)
        end
end

local function auth(username)
    local fd = assert(socket.open(var.ip, var.port), "can't connect login server")
    proxy.subscribe(fd)


    --test apple switch:
    proxy.write(fd, var.login_request("appleswitch", {
        ver = "v1.0",
        app = "fish"
    }, 2))

    local msg, sz = proxy.read(fd)
    local ty, session, resp = var.login_host:dispatch(msg, sz)
    log.debug("appleswitch, session: %d,  %s", session, cjson.encode(resp))
    proxy.write(fd, var.login_request("login", {
        app = "fish", 
        platform = "android", 
        type = "guest", 
        version = 1, 
        info = {
         --code as weixin code for first time
            code = username, 
            codetype = 1
        }}, 1))
    local msg, sz = proxy.read(fd)
    local ty, session, resp = var.login_host:dispatch(msg, sz)
    assert(ty == "RESPONSE")
    log.debug("login.resp, session: %d,  %s", session, cjson.encode(resp))

    if true then
      --  return
    end

    proxy.close(fd)
    if resp.err then
        error(string.format("login fail(%d) : %s", resp.err.code, resp.err.msg))
    end
    local user = resp.user

    log.notice("login ok %s:%d %s", username, user.id, user.secret)
    local fd = assert(socket.open(resp.server.ip, resp.server.port), "can't connect gate server")
    proxy.subscribe(fd)
    proxy.write(fd, var.gate_request("signin", {userid = user.id, secret = user.secret}, 2))
    local msg, sz = proxy.read(fd)
    local ty, session, resp = var.gate_host:dispatch(msg, sz)
    assert(ty == "RESPONSE")
    log.debug("signin.resp, session: %s", cjson.encode(resp))
    if resp.err then
        proxy.close(fd)
        error(string.format("signin fail(%d) : %s", resp.err.code, resp.err.msg))
    end
    proxy.write(fd, var.gate_request("transfer", nil, 2))
    user.fd = fd
    user.name = username
    log.notice("signin ok %s:%d:%d", user.name, user.id, user.fd)
    return user
end

function message.handshake(obj)
        local user = auth(obj.name)
        if user then
                var.socket[obj] = user 
                return user.id
        end
end


function message.request(obj, name, args)
        local s = assert(var.socket[obj])
        while not s.write do    -- request maybe before dispatch
                skynet.sleep(1)
        end
        var.session_id = var.session_id + 1
        var.session[var.session_id] = {name = name, req = args}
    local ok, ret = pcall(var.request, name, args, var.session_id)
    if not ok then
        log.error("proto wrong, check proto name etc.")
        return
    end
        proxy.write(s.fd, ret)
        log.debug("request %s", name)
end

function message.dispatch(obj)
        local s = assert(var.socket[obj])
        local handler = assert(var.handler[obj])
        proxy.subscribe(s.fd)
        s.write = true
        while true do
                local msg, sz = proxy.read(s.fd)
                local t, session_id, resp, err = var.host:dispatch(msg, sz) 
                if t == "REQUEST" then
                        local f = handler[session_id] -- session_id is request name
                        if f then
                log.debug("request.%s : %s", session_id, cjson.encode(resp))
                local ok, errmsg = pcall(f, obj, resp)  
                if not ok then
                    log.error("Request [%s] error : %s", session_id, errmsg)
                end
                        else
                                log.warning("Unknown request [%s]", session_id)
                        end
                else
                        local session = var.session[session_id]
                        var.session[session_id] = nil

                        if err then
                                log.error("session %s[%d] error : %s", session.name, session_id, tostring(err))
                        else
                                local f = handler[session.name]
                log.debug("response.%s : %s", session.name, cjson.encode(resp))
                                if f then
                    if not resp.err then
                        local ok, errmsg = pcall(f, obj, session.req, resp) 
                        if not ok then
                            log.error("session %s[%d] handler error : %s", session.name, session_id, errmsg)
                        end
                    else
                        log.debug("repsonse.%s error(%d) : %s", session.name, resp.err.code, resp.err.msg)
                    end
                                else
                                        log.warning("session %s[%d] no handler", session.name, session_id)
                                end
                        end
                end
        end
end


function message.close(obj)
        local s = assert(var.socket[obj])
        var.socket[obj] = nil
        var.handler[obj] = nil
        proxy.close(s.fd)
        log.close("Close username=%s userid=%d", obj.username, obj.userid)
end
        
return message

