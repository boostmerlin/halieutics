local skynet = require "skynet"

local string = string

local ll = {
	"debug",
	"verbose",
	"notice",
	"info",
	"warning",
	"error",
}

local loglevel
local logservice

local nullf = function() end

local function printf(lv)
    local prefix = string.format("<%s> ", lv:sub(1,3))
    return function(...)
        local log_text
        local ok
        if select("#", ...) == 1 then
            log_text = tostring(...)
        else
            ok, log_text = pcall(string.format, ...)
            if not ok then
            	skynet.error(debug.traceback())
            	log_text = select(1, ...)
            end
        end
        skynet.error(prefix .. log_text)
    end
end

local log = { 
	__index = function(t, k)
		local w = ll[k] or 0
		t[k] = w >= ll[loglevel] and printf(k) or nullf
		return t[k]
	end
}

skynet.init(function()
	loglevel = skynet.getenv("loglevel") or "info"
	for i, l in ipairs(ll) do
		ll[l] = i
	end
end)

return setmetatable({}, log) 

