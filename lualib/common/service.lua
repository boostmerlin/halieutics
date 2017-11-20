local skynet = require "skynet"
local balance = require "common.balance"
local log = require "common.log"
require "skynet.manager"

local service = {}

local function object(s)
    return setmetatable({}, {__index = function(t, k)
        t[k] = function(...)
            return skynet.call(s, "lua", k, ...)
        end
        return t[k]
    end})
end

local function set_dispatch_func(mod)
    local wait_response = {}
    if mod.wait_response then
        for _, cmd in ipairs(mod.wait_response) do
            wait_response[cmd] = true
        end
    end
    local closing
    local shutdown = mod.shutdown
    local funcs = mod.command
    skynet.dispatch("lua", function(session, source, cmd, ...)
        if cmd == "shutdown" then
            closing = true
            if shutdown then
                log.notice("%s shutdowning ...", SERVICE_NAME)
                pcall(shutdown)
                log.notice("%s shutdown ok", SERVICE_NAME)
            end
            skynet.response()(true)
        else
            if not closing then
                local f = funcs[cmd]
                if f then
                    service.SESSION = session
                    service.SOURCE = source
                    if wait_response[cmd] then
                        f(...)
                    else
                        skynet.ret(skynet.pack(f(...)))
                    end
                else
                    log.error("[service] Unknown command : [%s]", cmd)
                    skynet.response()(false)
                end
            else
                log.error "service closing"
                skynet.response()(false)
            end
        end
    end)
end

function service.init(mod)
    service.self = skynet.address(skynet.self())
	if mod.info then
		skynet.info_func(function()
			return mod.info
		end)
	end
	skynet.start(function()
		if mod.require then
			local s = mod.require
			for _, name in ipairs(s) do
				service[name] = object(skynet.uniqueservice(name))
			end
		end
        if mod.requireS then
            local s = mod.requireS
            for _, name in ipairs(s) do
                service[name] = object(skynet.newservice(name))
            end
        end
        if mod.requireX then
            local s = mod.requireX
            for _, v in ipairs(s) do
                service[v.service] = service.xlaunch(v.service, v.name)
            end
        end
		if mod.requireB then
			local s = mod.requireB
			for _, v in ipairs(s) do
                service[v.service] = balance(v)
			end
		end
		if mod.init then
			mod.init()
		end

        set_dispatch_func(mod)
	end)
end

function service.ulaunch(name, ...)
    if service[name] == nil then
        service[name] = object(skynet.uniqueservice(name, ...))
    end
    return service[name]
end

function service.launch(name, ...)
    local s = skynet.newservice(name, ...)
    return object(s)
end

function service.xlaunch(name, class, ...)
    local lname = string.format(".%s_%s", name, class)
    local s = skynet.localname(lname)
    if s == nil then
        s = skynet.newservice(name, class, ...)
        skynet.name(lname, s)
    end
    return object(s)
end

return service

