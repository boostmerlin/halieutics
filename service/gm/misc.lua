local service = require "common.service"
local log = require "common.log"
local cjson = require "cjson"

local misc = {}

local watchdog
local app="fish"

local function fetch_watchdog()
    if watchdog == nil then
        watchdog = service.xlaunch("watchdog", app)
    end
    return watchdog
end

function misc.ready()
    log.notice "shutdown ready"
    service.gmdb.set_shutdown_status "ready"
    service.login.shutdown()
end

function misc.done()
    log.notice "shutdown done"
    service.gmdb.set_shutdown_status "ok"
end

function misc.accinfo(userid)
	local uinfo = service.accdb.get_accinfo(tonumber(userid))
--	log.debug("Get account info for :%d", userid)
	if uinfo then
		local diamond = service.userdb.get_account(tonumber(userid))
		uinfo.bag = diamond
	else
	    uinfo = {err="user not find"}
	end

	return uinfo
end

function misc.query(nick)
	local users = service.accdb.query_by_uname(nick)
	return users
end

function misc.bind(userid, icode)
	assert(userid and icode)
	local uid = tonumber( userid )
	local uinfo = service.accdb.get_accinfo(uid)
	if uinfo then
		service.userdb.invite_bind(uid, icode)
	else
		return {err="user not found."}
	end
end

function misc.blacklist(userid, kick)
	local uid = tonumber(userid)
	local ret = service.accdb.blacklist(uid)
	if not ret then
		return {err="user not find"}
	else
		if true or kick and kick == "yes" then
			local wd = fetch_watchdog()
			wd.try_kick(uid, true)
		end
	end
end

function misc.whitelist(userid)
	local ret = service.accdb.whitelist(tonumber(userid))
	if not ret then
		return {err = "user not find"}
	end
end

function misc.regusern(app)
	return service.statdb.get_user(app)
end

function misc.online(app)
	return service.statdb.getonline(app)
end

function misc.activeusers(from, to)
	from = from and tonumber(from) or 0
	to = to and tonumber(to) or -1
	local t = service.statdb.activeusers(from, to)
	return t
end

function misc.appleswitch(app, ver, stat)
	if stat and not ver then
		return {err = "set must specify version"}
	end
	local ret = service.gmdb.appleswitch(app, ver, stat)
	return ret
end

function misc.getstock()
	return service.gmdb.update_stock(0)
end

function misc.setstock(value)
	assert(value)
	local nvalue = tonumber(value)
	if nvalue then
		return service.gmdb.set_stock(nvalue)
	else
		return "wrong value type"
	end
end

service.init {
    command = misc,
    require = {"gmdb", "login", "accdb", "statdb"},
    requireB = {
	    {name = "fish", service = "userdb"},
    },
}