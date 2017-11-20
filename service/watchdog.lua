local skynet = require "skynet"
require "skynet.manager"	-- for skynet.kill
local service = require "common.service"
local log = require "common.log"
local cjson = require "cjson"

local watchdog = {}
local data = {
    class = tostring(...),
    agents = {}, 
    users = {},
}

local broadcast_queue = {}

local function new_agent()
	for _, agent in ipairs(data.agents) do
		if agent.count < data.agent_load then
			agent.count = agent.count + 1
			return agent.service
		end
	end
	local agent = skynet.newservice("agent", data.class)
	table.insert(data.agents, {count = 1, service = agent})
	return agent
end

local function free_agent(agent)
	for i, a in ipairs(data.agents) do
		if a.service == agent then
			a.count = a.count - 1
			if a.count == 0 and #data.agents > 1 then
				table.remove(data.agents, i)
                skynet.call(a.service, "lua", "close")
			end
			return
		end
	end
end

-- c {id, ip, nick, head, sex, tag}
function watchdog.assign(c)
    log.debug("watchdog.assign user: %s", cjson.encode(c))
    local gate = service.SOURCE
	local users = data.users
	repeat
        local user = users[c.id]
        if not user then
            local agent = new_agent()
            if not users[c.id] then     -- new_agent may yield, double check
                user = {agent = agent, gate = gate, tag = c.tag, secret = c.secret} 
                users[c.id] = user
            else
                free_agent(agent)
                user = users[c.id]
            end
        else
            user.gate = gate
            user.tag = c.tag
            user.secret = c.secret
        end
        user.afk = nil
	until skynet.call(user.agent, "lua", "assign", c)
	log.notice("assign %s.agent %s %s to [%s]", data.class, c.tag, c.secret, skynet.address(users[c.id].agent))
end

function watchdog.query(userid)
    local user = data.users[userid]
    if user then
        return user.agent
    end
end

function watchdog.secret(userid)
    local user = data.users[userid]
    if user and not user.afk then
        return user.secret
    end
end

-- call by agent
function watchdog.afk(userid)
	local user = assert(data.users[userid], "no userid " .. tostring(userid))
    log.debug("watchdog.afk %s", user.tag)
    if not user.afk then
        user.afk = true
        skynet.call(user.gate, "lua", "kick", userid, false)
    end
end

-- call by agent 
function watchdog.exit(userid)
	local user = assert(data.users[userid], "no userid " .. tostring(userid))
	free_agent(user.agent)
	data.users[userid] = nil
	log.notice("exit %s.agent %s", data.class, user.tag)
    if not user.afk then
        skynet.call(user.gate, "lua", "kick", userid, false)
    end
end

-- call by gate
function watchdog.kick(userid)
    local user = data.users[userid]
    if user then
        skynet.call(user.agent, "lua", "kick", userid, true)
        free_agent(user.agent)
        data.users[userid] = nil
        log.debug("kick %s from watchdog %s", user.tag, data.class)
    end
end

-- call by login
function watchdog.try_kick(userid, force)
    log.debug("[watchdog.try_kick] userid %d", userid)
    local user = data.users[userid]
    if user then
        skynet.call(user.agent, "lua", "kick", userid, true)
        free_agent(user.agent)
        data.users[userid] = nil
        if user.gate then
            skynet.call(user.gate, "lua", "kick", userid, true)
        end
        log.debug("try-kick %s from watchdog %s", user.tag, data.class)
    else
        log.debug("[watchdog.try_kick] user is nil")
    end
end

local function dispatch_broadcast(message)
    while #broadcast_queue > 0 do
        local message = table.remove(broadcast_queue, 1)
        for _, agent in ipairs(data.agents) do
            if agent.count > 0 then
                skynet.call(agent.service, "lua", "broadcast", message)
                skynet.sleep(1)
            end
        end
        skynet.sleep(50)
    end
end

-- call by gm
function watchdog.broadcast(message)
    table.insert(broadcast_queue, message)
    if #broadcast_queue == 1 then
        skynet.fork(dispatch_broadcast)
    end
end

service.init {
	command = watchdog,
	info = data,
	init = function()
		data.agent_load = tonumber(skynet.getenv "agent_load") or 64
        skynet.fork(function()
            free_agent(new_agent())
        end)
	end,
    shutdown = function()
        for _, agent in ipairs(data.agents) do
            pcall(skynet.call, agent.service, "lua", "shutdown")
        end
    end,
}

