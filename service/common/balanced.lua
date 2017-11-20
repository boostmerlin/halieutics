local skynet = require "skynet"
local service = require "common.service"
local log = require "common.log"

local balance = {}
local data = {services = {}}

function balance.launch(o)
    assert(o.service)
    local name = o.service
    if o.name then
        name = o.name .. "." .. o.service 
    end
    local instance = o.instance or 1

    local dbset = data.services[name]
    if dbset then
        if instance <= #dbset.slave then
            return name
        end
    else
        dbset = {balance = 0, slave = {}}
    end

    instance = instance - #dbset.slave
    assert(o.service)

    log.debug("[balance.launch] service: %s instance: %d", name, instance)
    for i=1, instance do
        table.insert(dbset.slave, skynet.newservice(o.service, o.name))
    end
    data.services[name] = dbset
    return name
end

function balance.call(name, ...)
    local s = assert(data.services[name], "no balance service "..name)
	s.balance = s.balance + 1
	if s.balance > #s.slave then
		s.balance = 1
	end
	local slave = s.slave[s.balance]
	return skynet.call(slave, "lua", ...)
end

service.init {
	command = balance,
	info = data,
}

