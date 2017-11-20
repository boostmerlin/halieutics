local log = require "common.log"
local sharedata = require "skynet.sharedata"
local mod = {}

--cjson can't serialize shareddata
function mod:list(name)
	local cfgname = self.cfgname or name
	local key = self.modname .. ":"..cfgname
	local data = sharedata.deepcopy(key, name)

	log.debug("list mod %s on key: %s", self.modname, name)

	-- if self.sharedmap[name] == nil then
	-- 	self.sharedmap[name] = data
	-- end

--	local t = shopmap[name]

    return data
end

function mod:clear()
	self.sharedmap = {}
end

function mod.init(modname, cfgname)
	local ins = setmetatable({}, {__index = mod})
	ins.modname = modname
	ins.cfgname = cfgname
	ins.sharedmap = {}

	return ins
end

function mod.listconfig(modname, cfgname, name)
	local key = modname .. ":" .. cfgname
	local data = sharedata.deepcopy(key, name)

	return assert(data, "null data when listconfig")
end


return mod