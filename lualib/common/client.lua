local skynet = require "skynet"
local sprotoloader = require "sprotoloader"
local proxy = require "common.socket_proxy"
local log = require "common.log"
local cjson = require "cjson"

local client = {}
local proto_handler
local default_proto_hanlder

local fd_session = {}

local host, sender

local no_resp = {}

client.no_resp = no_resp

local resp_ok = {ok = true}
local resp_err = {err = {code = -1, msg = "invalid request"}}

local function response(fd, resp, name, f, ...)
    local ok, err = pcall(f, ...)
    if ok then
        if no_resp == err then
            return
        end
        err = err or resp_ok 
        proxy.write(fd, resp(err))
        log.debug("RESPONE:%d:%s : %s %s", fd, name, pcall(cjson.encode, err))
    else
        proxy.write(fd, resp(resp_err))
        log.error("REQUEST:%d:%s error : %s", fd, name, err)
    end
end

function client.dispatch(c, tag)
	local fd = c.fd
	proxy.subscribe(fd)
	while true do
		local msg, sz = proxy.read(fd)
		local ty, name, args, resp = host:dispatch(msg, sz)
        log.debug("[client.dispatch@%s] %s:%d:%s : %s", tag, ty, fd, name, cjson.encode(args))
        assert(ty == "REQUEST")
        if c.exit then
            log.debug("[client.dispatch] dispatch exit, fd: %d, tag: %s", fd, tag)
            return c
        end

        local handler = proto_handler[name]
        if handler then
            skynet.fork(response, fd, resp, name, handler, c, args)
        elseif default_proto_handler then
            skynet.fork(response, fd, resp, name, default_proto_handler, c, name, args)
        else
            print("..............................................")
            assert(false, "no request handler : " .. tostring(name))
        end
	end
end

function client.close(fd)
	proxy.close(fd)
end

function client.proto(name, rpc)
    local protoloader = skynet.uniqueservice "protoloader"
    if rpc then
        local slot = skynet.call(protoloader, "lua", "index", name)
        host = sprotoloader.load(slot):host "package"
    else
        local slot = skynet.call(protoloader, "lua", "index", name .. ".c2s")
        host = sprotoloader.load(slot):host "package"
        local slot = skynet.call(protoloader, "lua", "index", name .. ".s2c")
        sender = host:attach(sprotoloader.load(slot))
    end
end

function client.bind(handler, default_handler)
    proto_handler = handler
    default_proto_handler = default_handler
end

function client.push(fd, command, args)
    log.debug("push %s to %d", command, fd)
    proxy.write(fd, sender(command, args))
end

function client.mpush(fds, command, args)
    local msg, sz = sender(command, args)
    for _, fd in ipairs(fds) do
        log.debug("push %s to %d", command, fd)
        proxy.write(fd, msg, sz)
    end
end

function client.client_dispatch(f)
    skynet.dispatch("client", function(_, _, ...)
        f(skynet.unpack(...))
    end)
end

return client

