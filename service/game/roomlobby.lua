local service = require "common.service"
local sharedmod = require "module.sharedmod"
local log = require "common.log"
local prop = require "module.prop"
local cjson = require "cjson"
local skynet = require "skynet"
local timer = require "common.timer"
local sharedata = require "skynet.sharedata"

local data = {app = tostring(...), games = {}}

local lobby = {}

local roommod

local waitload = {}
local deskmap = {}

local deskid_min = 100001
local deskid_max = 999999

local deskid_buffer = {}
local desk_monitor = {}

local kill_desk_delay = 60      -- 1min 
local reserve_desk_time = 900  -- 10m
--local reserve_desk_time = 15

local function gettime()
    return math.floor(skynet.time())
end

local function getdesk(d)
    d.__info = d.__info or {
        id = d.info.id,
        robotmode = d.info.robotmode,
        roomtype = d.info.roomtype,
        info = d.info,
        service = d.home.service,
    }
    return d.__info
end

local function getpay(info)
    local roompara = roommod:list("roompara")
    local key = info.aapay and "aa" or "master"
    local cost = roompara[key][tostring(info.timelimit)]
    if info.roomtype == 0 and (not cost or cost == -1) then
        return
    end
    local pay = info.roomtype == 0 and cost or 0
    return {AA = info.aapay, total = pay }
end

local function random_id(id_buffer)
    local n = #id_buffer
    if n > 0 then
        local idx = math.random(1, n)
        local id = id_buffer[idx]
        id_buffer[idx] = id_buffer[n]
        id_buffer[n] = nil
        log.debug("[roomlobby] random id: %d", id)
        return id
    end
end

local function assign_desk(info, userid)
    local g = assert(data.games[info.game], "no game " .. info.game)
    info.id = info.id or random_id(deskid_buffer)
    if info.id == nil then
        return
    end

    info.creater = userid or info.creater --for restore from db.
    local pay = getpay(info)
    if not pay then
        return
    end
    info.pay = pay
    info.time = info.time or gettime()
    log.notice("[assign_desk] pay info: %s", cjson.encode(info.pay))

    for _, d in ipairs(g.desks) do
        if #d.actives < data.desk_load then
            table.insert(d.actives, info.id)
            deskmap[info.id] = {home = d, info = info, users = {}}
            return deskmap[info.id]
        end
    end
    --one service service serve desk_load desk
    local s = skynet.newservice("roomdesk", data.app, info.game)
    local d = {game = info.game, service = s, actives = {info.id}}
    deskmap[info.id] = {home = d, info = info, users = {}}
    table.insert(g.desks, d)
    return deskmap[info.id]
end

function lobby.deskn()
    local n = 0
    local g = assert(data.games[data.app], "no game " .. data.app)
    for _, d in ipairs(g.desks) do
        n = n + #d.actives
    end
    return {game=data.app, deskn=n}
end

local function add_kill_queue(desk)
    local g = data.games[desk.info.game]
    local d = desk.home
    if #d.actives== 0 and #g.desks > 1 then
        timer.add(kill_desk_delay, function()
            log.debug("wait kill desk service %s timeup", skynet.address(d.service))
            if #d.actives == 0 then
                for i, ds in ipairs(g.desks) do
                    if ds == d then
                        table.remove(g.desks, i)
                        skynet.call(d.service, "lua", "exit")
                        break
                    end
                end
            else
                log.debug("desk service %s has active desk, can't kill", skynet.address(d.service))
            end
        end)
    end
end

function lobby.free(deskid)
    local desk = deskmap[deskid]

    local timerid = desk_monitor[deskid]
    if timerid then
        timer.remove(timerid)
    end

    if desk then
        local dh = desk.home
        deskmap[deskid] = nil
        waitload[deskid] = nil
        log.notice("[lobby.free] free-desk %s %d [%d]", desk.info.game, deskid, #dh.actives)
        if dh.service then
       	    skynet.call(dh.service, "lua", "remove_mydesk", deskid)
       	end

        for i, id in ipairs(dh.actives) do
            if id == deskid then
                table.remove(dh.actives, i)
                table.insert(deskid_buffer, deskid)
                break
            end
        end
        -- for i, d in ipairs(desk_monitor) do
        --     if d == desk then
        --         table.remove(desk_monitor, i)
        --     end
        -- end
        add_kill_queue(desk)
    else
        log.warning("[lobby.free] free-desk %d is not exists", deskid)
    end
end

local function restore_desk(dinfo)
    if data.games[dinfo.game] then
        local desk = assign_desk(dinfo)
        if desk then
            --todo restore in game too..
            skynet.call(desk.home.service, "lua", "restore", dinfo)
            return desk
        end
    else
        log.warning("[restore a desk] that no exists game %s", dinfo.game)
    end
end

function lobby.query(deskid)
    local desk = deskmap[deskid]
    if desk == nil then
        local dinfo = waitload[deskid]
        if dinfo then
            waitload[deskid] = false
            log.debug("[lobby.query] Restore desk by info: %s", cjson.encode(dinfo))
            desk = restore_desk(dinfo)
        end
    end
    if desk then
        return getdesk(desk)
    end
end


local function free_desk(dinfo)
    local deskid = dinfo.id

    if waitload[deskid] ~= nil then
        waitload[deskid] = nil
    end

    local r = service.gamedb.restore_desk(deskid)
    if r then
        if r.users then
            for userid, _ in pairs(r.users) do
                service.userdb.leave(userid)
            end
        end
        if r.costs then
            for _, c in ipairs(r.costs) do
            	log.debug("[lobby] back roomcard userid: %d, count: %d", c.userid, c.count)
                prop.add("room.back", c.userid, "diamond", c.count, {d = deskid, g = dinfo.game})
            end
        end
    end

    service.userdb.dismiss(dinfo.creater, deskid)
    service.gamedb.free_desk(deskid)
    table.insert(deskid_buffer, deskid)
    log.notice("[lobby] ------------free-desk %s:%d", dinfo.game, deskid)
end

local function desk_monitor_work(d)
    log.debug("desk monitor timeup, remove desk %s:%d", d.game, d.id)
    local desk = deskmap[d.id] --lobby.free
    if desk then
        log.debug("[desk_monitor_work] free normal.")
        local ret = skynet.call(desk.home.service, "lua", "force_dismiss", d.id)
        if ret == 3 then
            lobby.free(d.id)
           -- free_desk(d)
        end
    else
        log.debug("[desk_monitor_work] !!! free unnormal, no desk running")
        free_desk(d)
    end
end

local function desk_monitor_add(dinfo, id)
    assert(dinfo)
    local expire = dinfo.time + reserve_desk_time
    local now = gettime()
    local cd = expire >= now and (expire-now) or 0
    local timerid = timer.add(cd, desk_monitor_work, dinfo)
    local last = desk_monitor[id]
    if not last then --should be nil, or something not right.
        timer.remove(last)
    end
    desk_monitor[id] = timerid
    log.debug("desk monitor add %s:%d %d NOW:%d", dinfo.game, dinfo.id, expire, now)
end


-- call by desk
function lobby.monitor_desk(deskid)
    local desk = assert(deskmap[deskid], "lobby has no desk " .. tostring(deskid))
    if waitload[deskid] == nil then
        desk_monitor_add(desk.info, deskid)
    end
end

function lobby.open(games)
	roommod = sharedmod.init("gameplay", "createroom")
	for _, name in ipairs(games) do
		assert(data.games[name] == nil, "repeat game "..name)
        data.games[name] = {
            name = name,
            tag = string.format("%s.%s", data.app, name), 
            desks = {}
        }
        log.notice("open roomlobby for game %s", data.games[name].tag)
    end
end

function lobby.assign(userid, info)
	local desk = assign_desk(info, userid)
	if desk then
        log.notice("assign-desk %s:%d [%s] by %d", info.game, info.id, skynet.address(desk.home.service), userid)
        return getdesk(desk)
    end
end

-- call by desk
function lobby.sitdown(user, deskid)
end

-- call by desk
function lobby.standup(userid, deskid)
end

function lobby.gamestart(deskid)
end

function lobby.gameover(deskid)
end

local function init_deskid_buffer()
    -- just get deskid, load it when query desk
    log.verbose(".....................init_deskid_buffer...............................")
    local wbuffer = service.gamedb.get_active_desks() or {}
    for id=deskid_min, deskid_max do
        if wbuffer[id] then
            waitload[id] = assert(service.gamedb.get_desk_info(id))
            local start = service.gamedb.isstart(id)
            if not start then --not this time...
                --desk_monitor_add(waitload[id], id)
                desk_monitor_work(waitload[id])
            else
                desk_monitor_work(waitload[id])
            end
            log.verbose("[init_deskid_buffer] wait load desk %s:%s, start? %s", data.app, id,start)
        else
            table.insert(deskid_buffer, id)
        end
    end
end

service.init {
    command = lobby,
    info = data,
    require = {"accdb"},
    requireB = {
        {name = data.app, service = "userdb"},
        {name = data.app, service = "gamedb"},
    },
    -- requireX = {
    --     {name = data.app, service = "watchdog"},
    -- },
    init = function()
        math.randomseed(skynet.time())
        data.desk_load = tonumber(skynet.getenv "desk_load") or 8 
        data.config = sharedata.query("appconfig." .. data.app)
        prop.init(data.config.props)
        init_deskid_buffer()
    end
}
