local skynet = require "skynet"
local datacenter = require "skynet.datacenter"
local sharedata = require "skynet.sharedata"
local redis = require "skynet.db.redis"
local log = require "common.log"
local cjson = require "cjson"
require "skynet.manager"

local service = {
    cmd_multi = {"multi"},
    cmd_exec = {"exec"},
}

local function fetch_db(token)
	local fields = {
		db = "(%d+)@",
		host = "@([^:^#]+)[:#]?",
		port = ":(%d+)#?",
		auth = "#([^#]+)",
	}
	local conf = {}
	for k, v in pairs(fields) do
		conf[k] = token:match(v)
	end
	conf.db = conf.db and tonumber(conf.db) or 0
	conf.port = conf.port and tonumber(conf.port) or 6379
	return conf
end

local function bind_scr(db, scr)
    local sha = {}
    for k, v in pairs(scr) do
        sha[k] = db:script("LOAD", v) 
        -- log.debug("redis-sha %s %s", k, sha[k])
    end
    return setmetatable({__db = db}, {
        __index = function(t, k)
            if sha[k] then
                t[k] = function(...)
                    return db:evalsha(sha[k], 0, ...)
                end
                return t[k]
            else
                log.error("don't supports db interface %s", k)
            end
        end
    })
end

local function multi_db(mod, dbs, scr)
    assert(mod.select_f)
    local f = mod.select_f(#dbs)
    service.db = setmetatable({}, {__index = function(t, k)
        assert(type(k) == "number")
        local idx = f(k)
        local sdb = dbs[idx]
        t[k] = sdb
        log.debug("[Redisdb] selectdb %s:%d@%d for user %d-%d", sdb.conf.host, sdb.conf.port, sdb.conf.db, k, idx)
        return sdb
    end})
    if scr then
        local scrs = {}
        for _, db in ipairs(dbs) do
            local scr = bind_scr(db, scr)
            table.insert(scrs, scr)
        end
        service.scr = setmetatable({}, {__index = function(t, k)
            assert(type(k) == "number")
            local idx = f(k)
            log.debug("[redisdb] selectdb script %d-%d", k, idx)
            t[k] = scrs[idx]
            return t[k]
        end})
    end
end

local function make_db(mod)
    if mod.db == nil then
        assert(mod.name)
        local config
        if mod.app then
            config = sharedata.query("appconfig." .. mod.app)
        else
            config = sharedata.query "sysconfig"
        end
        local conf = config.db[mod.name]
        if type(conf) == "table" then
            mod.db = table.concat(conf, " ")
        else
            mod.db = conf 
        end
    end
    assert(mod.db)
    local dbs = {}
    for token in (mod.db.." "):gmatch "([^ ]+) " do 
        local conf = fetch_db(token)
        local db = redis.connect(conf)
        db.conf = conf
        table.insert(dbs, db)
    end
    assert(#dbs > 0, "no db configed")
    return dbs
end

function service.init(mod)
	if mod.info then
		skynet.info_func(function()
			return mod.info
		end)
	end
    if mod.init then
        mod.init()
    end
	skynet.start(function()

        local dbs = make_db(mod)

        local path = skynet.getenv "redis_script_path"
        local ok, scr = pcall(dofile, path .. "/" .. mod.name.. ".lua")
        if not ok then
            scr = nil
        end
        if #dbs > 1 then --always goes here
            multi_db(mod, dbs, scr)
        else
            service.db = dbs[1]
            if scr then
                service.scr = bind_scr(dbs[1], scr)
            end
        end

        local funcs = mod.command
        skynet.dispatch("lua", function(_, _, cmd, ...)
            local f = funcs[cmd]
            if f then
                skynet.ret(skynet.pack(f(...)))
            else
                log.error("Unknown command : [%s]", cmd)
                skynet.response()(false)
            end
        end)
	end)
end

service.parse = fetch_db

return service

