local skynet = require "skynet"
local log = require "common.log"

local proxyd

skynet.init(function()
	proxyd = skynet.uniqueservice "socket_proxyd"
end)

local proxy = {}
local map = {}

skynet.register_protocol {
	name = "text",
	id = skynet.PTYPE_TEXT,
	pack = function(text) return text end,
	unpack = function(buf, sz) return skynet.tostring(buf,sz) end,
}

skynet.register_protocol {
	name = "client",
	id = skynet.PTYPE_CLIENT,
	pack = function(buf, sz) return buf, sz end,
}

local function get_addr(fd)
	return map[fd]
end

function proxy.subscribe(fd)
	local addr = map[fd]
	if not addr then
		addr = skynet.call(proxyd, "lua", fd)
		map[fd] = addr
	end
end

function proxy.read(fd)
	local ok,msg,sz = pcall(skynet.rawcall , get_addr(fd), "text", "R")
	if ok then
		return msg,sz
	else
		error("disconnect", 0)
	end
end

function proxy.write(fd, msg, sz)
    local s = get_addr(fd)
    if s then
	    skynet.send(s, "client", msg, sz)
    else
        log.warning("write %d must subscribe first", fd)
    end
end

function proxy.close(fd)
    local s = get_addr(fd)
    if s then
	    skynet.send(s, "text", "K")
    else
        log.warning("close %d must subscribe first", fd)
    end
end

function proxy.info(fd)
    local s = get_addr(fd)
    if s then
	    return skynet.call(s, "text", "I")
    else
        log.warning("info %d must subscribe first", fd)
    end
end

return proxy



