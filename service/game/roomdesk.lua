local skynet = require "skynet"
local queue = require "skynet.queue"
local sharedata = require "skynet.sharedata"
local service = require "common.service"
local log = require "common.log"
local sync = require "game.sync"
local em = require "def.errmsg"
local cjson = require "cjson"
local msgdef = require "def.msgdef"
local string = string
local androiduser = require "module.androiduser"

local prop = require "module.prop"
local tbl_insert = table.insert

local app, game = ...

local desk = {}
local data = {app = assert(app), game = assert(game), desks = {}}

local gamedesk = require("game."..data.game .. ".desk")
local msg_queue = {}

local dismiss_max_time = 30
local grab_banker_delay = 10
local chat_intval = 2   -- 2s
local game_run_delay = 8

local function getuser(u)
    return {
        id = u.id,
        seat = u.seat,
        nick = u.nick,
        head = u.head,
    }
end

local cli = setmetatable({}, {__index = gamedesk})

local push_null = function() end

local function gettablen(t)
    assert(type(t) == "table")
    local n = 0
    for _, _ in pairs(t) do
        n = n + 1
    end
    return n
end

local function remtableitem(t, item)
    assert(type(t) == "table")
    for i, v in ipairs(t) do
        if(v == item) then
            table.remove(t, i)
            return v
        end
    end
end

local function android_notify(d, evt, args)
    for _, u in pairs(d.users) do
        if u.android then
            u:onevent(evt, false, args)
        end
    end
end

local function changeandroidid(d, afkuid)
    local aid = d.androidid
    if not aid or aid == afkuid then
        for uid, u in pairs(d.usermap) do
            if not u.afk and not u.android then
                d.androidid = uid
                return
            end
        end
        d.androidid = nil
    end
end

local function dispatch_client_message()
    while #msg_queue > 0 do
        local m = table.remove(msg_queue, 1)
        for _, u in ipairs(m.clients) do
            if not u.afk and u.source then
                skynet.send(u.source, "lua", "push", u.id, m.message.command, m.message.data)
            end
        end
    end
end

local function add_msg_queue(m)
    table.insert(msg_queue, m)
    if #msg_queue == 1 then
        skynet.fork(dispatch_client_message)
    end
end

local function user_push_f(user)
    return function(command, args)
        local message = {
            command = command,
            data = args,
        }
        add_msg_queue{clients = {user}, message = message}
    end
end

local function desk_push_f(d)
    return function(command, args, noaudience)
        local m = {
            message = {
                command = command,
                data = args,
            },
            clients = {}
        }
        for _, u in pairs(d.usermap) do
            if not (noaudience and u.audience) then
                table.insert(m.clients, u)
            end
        end
        add_msg_queue(m)
    end
end


local function kick_user(d, user)
    local uid = user.id
    d.usermap[uid] = nil
    d.audiences[uid] = nil
    user.audience = nil
    service.gamedb.remove_user(d.id, user.id)
    service.userdb.leave(uid, d.id)
end

local function desk_epush_f(d)
    return function(command, flag, args, noaudience, byuserid)
        local m = {
            message = {
                command = command,
                data = args,
            },
            clients = {}
        }
        for _, u in pairs(d.usermap) do
            if (byuserid and u.id ~= flag) or (not byuserid and u.seat ~= flag) then
                if not (noaudience and u.audience) then
                    table.insert(m.clients, u)
                end
            end
        end
        add_msg_queue(m)
    end
end

local function android_thread(au, d)
    log.debug("---------androiduser thread, %s", au.tag)
    desk.join(d.id, au)
    desk.sitdown(d.id, au.id)
    cli.ready(d, au)
    skynet.wait()
    if not au.prepared then
        au.prepared = true
        local req = {grabbed = true}
        cli.grab_banker(d, au, req)
        skynet.wait()
        cli.gamerun(d, au)
    end
    local dt = 20
    while d.isstart do
        au:update(dt)
        dt = math.random(18, 25)
        skynet.sleep(dt)
    end
    log.debug("-------------android user-- over: %d", au.id)
    --game over.
end

local function wait_ready(d)
    log.debug("%s state => ready", d.tag)
    local s = d.sync:wait "ready" -- must wait until master start game.
    if s.driver == "message" then
        return true
    end
end

local function wait_grab_banker(d)
    log.debug("%s state => grab banker", d.tag)
    local s = d.sync:wait("banker", grab_banker_delay)  -- must wait until
end

local function wait_notice_gamerun(d)
    log.debug("%s state => wait_notice_gamerun", d.tag)
    local s = d.sync:wait("gamerun", game_run_delay)  --
end

local function free_desk(d)
    log.debug("[roomdesk] free-desk %s = %s", data.game, d.tag)
    for _, u in pairs(d.usermap) do
        if u.source then
            pcall(skynet.call, u.source, "lua", "standup", u.id, true)
         --   pcall(skynet.call, u.source, "lua", "leave", u.id, true)
        end
        kick_user(d, u)
    end

--todo, remove_mydesk here
    --desk.remove_mydesk(d.id)
    service.userdb.dismiss(d.creater, d.id)
    service.gamedb.free_desk(d.id)
    service.roomlobby.free(d.id)
    data.desks[d.id] = nil
end

local function gamestart(d)
    d.count = d.count + 1
    if d.count == 1 then -- for cycle is 1, isstart and gaming should be same.
        if not d.isstart then
            service.gamedb.start(d.id)
            d.isstart = true
        end
        d:init()
    end
    d.push("gamestart", {timeout = grab_banker_delay})
    for _, u in pairs(d.users) do
        if u.android then
            u:onevent("gamestart", true)
        end
    end

end

local function gameover(d, g)
    --send gameover. 
    if g then
        local t = math.floor(skynet.time())
        local ginfo = {appname = data.app, deskid = d.id
        , time = t, users = {}, audiences={}}
        local results = {}
        for _, u in pairs(d.users) do
            table.insert(results, {seat=u.seat, score=u.game.score})
            table.insert(ginfo.users, {id = u.id, nick = u.nick, score = u.game.score, head=u.head})
        end
        local usermap = d.usermap
        for uid, _ in pairs(d.audiences) do
            local u = usermap[uid]
            table.insert(ginfo.audiences, {id = u.id, nick = u.nick, head=u.head})
        end
        d.push("gameover", {users=results, time=t})
        service.gamedb.save_game_result(d.guid, ginfo)
        log.debug("[roomdesk] game result saved, deskguid: %d, info: %s", d.guid, cjson.encode(ginfo))
    else
        log.warning("[roomdesk] why g is nil.")
    end
end

local function determin_banker(d)
    local robbed_seats = {}
    local not_robbed_seats = {}
    for _, u in pairs(d.users) do
        if u.grabbed then
            tbl_insert(robbed_seats, u.seat)
            u.grabbed = nil
        else
            tbl_insert(not_robbed_seats, u.seat)
        end
    end

    local seats = #robbed_seats > 0 and robbed_seats or not_robbed_seats
    local i = math.random(1, #seats)
    d.banker = seats[i]
    d.push("change_banker", {seatid = d.banker, candidates=seats, last = nil})

    for _, u in pairs(d.users) do
        if u.android then
            u:onevent("determin_banker", true, d.banker)
        end
    end
end

local function do_game(d)
    gamestart(d)

    wait_grab_banker(d)
    determin_banker(d)
    wait_notice_gamerun(d)
    d.push("game_do_run")

    d.gaming = true
    d.starttime = math.floor(skynet.time())
    local g = d:start()
    log.debug("[roomdesk] game end, interrupt?? %s", d.err)
    d.gaming = false
    gameover(d, g)
end

local function start_desk(d, restore)
    if not restore and d.robotmode and d.robotmode > 0 then
       -- assert(info.roomtype > 0)
        desk.genandroid(d, d.robotmode)
        d.robotmode = 0
    end
   -- while d.count < d.sum do
    if wait_ready(d) then
        do_game(d)
    end
  --  end
    d.isstart = false
    if d.err then
        error(d.err, 0)
    end
end

local err_handler = {}

local function standup(user)
    if user.source then
        skynet.call(user.source, "lua", "standup", user.id)
    end
end

-- local function leave(user)
--     if user.source then
--         skynet.call(user.source, "lua", "leave", user.id)
--     end
-- end

function err_handler.dismissbyuser(d)
    d.push("dismiss", {reason = msgdef.desk_dismiss_ok})
end

function err_handler.dismissbytimeout(d)
    d.push("dismiss", {reason = msgdef.desk_dismiss_time_out})
end

local function back_roomcard(d, userid)
    if d.costs == nil or #d.costs == 0 then
        return
    end
    local costs = {}
    for i, c in ipairs(d.costs) do
        -- if userid == nil , back all
        if userid == nil or userid == c.userid then
            --local newnum = service.userdb.add_roomcard("back", c.userid, c.count, {id = d.id, game = d.game})
            local newnum = prop.add("room.back", c.userid, "diamond", c.count, {d = d.id, g = d.game})
            log.debug("[back_roomcard] back %d %d in costs %d", c.userid, c.count, i)
            local agent = service.watchdog.query(c.userid)
            if agent then
                skynet.call(agent, "lua", "push", c.userid, "update_account", {diamond = newnum})
            end
        else
            table.insert(costs, c)
        end
    end
    service.gamedb.save_costs(d.id, costs)
    d.costs = costs
end


local function game_interrupt(d, err)
    if d.gaming then
        d:force()
        log.debug("game_interrupt for : %s", err)
        d.err = err
    end
end

local function new_desk(d, restore)
    local ok, err = pcall(start_desk, d, restore)
    if not ok then
        local f = err_handler[err]
        if f then
            f(d)
        else
            log.error("[roomdesk] unhandled error: %s", err)
            gameover(d, d:force())
        end
        log.debug("[roomdesk]game end unnormally ,d.count %d, start? %s, err? %s", d.count, d.isstart, err)
        if d.count == 0 then
            back_roomcard(d)
        end
    end
    free_desk(d)
end

local function simpleCopy(src)
    local newTble = {}
    for key,value in pairs(src) do  
        if type(value) == "table" then  
            newTble[key] = {}  
            simpleCopy(newTble[key], value)  
        elseif type(value) ~= "function" then
            newTble[key] = value  
        end  
    end  
    return newTble
end  

local function backup_user(deskid, user)
    local usercopy = simpleCopy(user)
    usercopy._co = nil
    usercopy.source = nil
    usercopy.tag = nil
    usercopy.push = nil
    usercopy.send = nil
    service.gamedb.add_user(deskid, usercopy)
end

local function update_fish_stock(stock, user)
    assert( type(stock)=="number", "stock is not a number" )
    if user.android then
        return
    end
    service.gmdb.update_stock(stock)
end

local function get_stock()
    local ret = service.gmdb.get_stock()
    if ret then
        return tonumber(ret)
    end
    return 0
end

local function init_desk(d)
    d.count = 0
    d.sum = d.cycle
    d.users = {}
    d.usermap = {}
    d.freeseats = {}
    d.audiences = {} --audience uid, dict
    d.msgbuf = {}
    d.tag = string.format("%s:%s:%d", d.id, d.guid, d.maxplayer)
    d.sync = sync.new(d.maxplayer)
    d.push = desk_push_f(d)
    d.epush = desk_epush_f(d)
    d.banker = -1 --banker seatid
    d.grabcnt = 0
    d.update_stock = update_fish_stock
    d.get_stock = get_stock
    for i=1, d.maxplayer do
        table.insert(d.freeseats, i)
    end

    d.cs = queue()
    data.desks[d.id] = d
    service.roomlobby.monitor_desk(d.id)
end

local function init_user(d, user, seat)
    user.game = {score = 0}
    if seat then
        for i, s in ipairs(d.freeseats) do
            if s == seat then
                table.remove(d.freeseats, i)
                break
            end
        end
        log.notice("--[init_user], desk id %d, userid: %d, seat: %d", d.id, user.id, seat)
        d.sync:add(seat, true)
    else
        seat = table.remove(d.freeseats)
        log.notice("[init_user], desk id %d, userid: %d, seat: %d", d.id, user.id, seat)

        d.sync:add(seat, true)
    end
    user.seat = seat
    user.audience = false
    backup_user(d.id, user)

    user.tag = string.format("%s:%d", user.nick, user.id)
    --agent getuser.
    --table.insert(d.users, user)
    d.users[seat] = user
    d.audiences[user.id] = nil
    -- if not user.android and not d.master then
    --     user.master = true
    --     d.master = user.id
    -- end
end

local function joinin(d, user, restore)
    user.seat = -1
    user.afk = false
    if not user.android then
        user.source = service.SOURCE
        if not d.androidid then
            d.androidid = user.id
        end
    end
    d.usermap[user.id] = user
    d.audiences[user.id] = true
    user.audience = true
    user.master = d.creater == user.id
    if user.master then
        d.master = user.id
    end
    backup_user(d.id, user)
    if user.android then
        user.push = push_null
        user.send = function (cmd, args)
            desk.client(d.id, user.id, cmd, args)
        end
    else
        user.push = user_push_f(user)
    end
    service.userdb.join(user.id, d.id)
end

local function desk_cost_backup(d, user, pay)
    d.costs = d.costs or {}
    local c = {userid = user.id, count = pay.total}
    table.insert(d.costs, c)
    service.gamedb.add_cost(d.id, c)
    log.debug("[desk_cost_backup] %s:%d cost.%s %d %d", d.game, d.id, pay.AA and "AA" or "master", user.id, pay.total)
end

function desk.usern(deskid)
    local d = data.desks[deskid]
    if not d then
        return 0
    end

    return gettablen(d.usermap)
end

-- call by agent, update gamedb
function desk.create(info, user, donotseat)
    log.debug("[roomdesk.create] info: %s", cjson.encode(info))
    assert(data.desks[info.id] == nil, string.format("desk %d exists", info.id))

    local d = gamedesk.create(info)

    local robotcnt = info.robotmode
    if robotcnt and robotcnt > 0 then
        d.robotmode = robotcnt < d.maxplayer and robotcnt or (d.maxplayer-1)
    end

    if info.pay then
        desk_cost_backup(d, user, info.pay)
    end

    -- add desk in gamedb, set active state.
    d.guid = service.gamedb.create_desk(d)
    log.debug("*********************[roomdesk] desk.create guid %d, sit when create ? %s", d.guid, not donotseat)

    init_desk(d)

    if not donotseat then --sit now
        log.notice("[desk.create] init user, create and sit: %d", user.id)
        init_user(d, user)
    end

    -- if d.robotmode and d.robotmode > 0 then
    --    -- assert(info.roomtype > 0)
    --     desk.genandroid(d, d.robotmode)
    --     d.robotmode = 0
    -- end

    skynet.fork(new_desk, d)

    log.verbose("end of create-desk %s %s", user.tag, d.tag)

    return d.guid
end

--depracated
local function restore_desk(d)
    local r = service.gamedb.restore_desk(d.id)
    if r == nil then
        return
    end
    if r.costs then
        d.costs = r.costs
    end
    d.isstart = r.start
    if r.users then
        for userid, u in pairs(r.users) do
            log.debug("[restore_desk] user, %d : %s", userid, cjson.encode(u.info))
         --   local user = service.accdb.get_userinfo(userid)
            local user = u.info
           -- user.afk = true
            if user.android then
                user = androiduser.restoreandroid(user)
                --user.afk = false
                user._co = skynet.fork(android_thread, user, d)
            else
                local audience = user.audience
                joinin(d, user, true)
                log.debug("[user-restore] %s", cjson.encode(u))
                if not audience then
                    init_user(d, user, u.seat)
                end
            end
        end
    end
end

--lobby ,depracated
function desk.restore(info)
    assert(data.desks[info.id] == nil, string.format("desk %d exists", info.id))
    local d = gamedesk.create(info)
    init_desk(d)
    restore_desk(d)
    skynet.fork(new_desk, d, true)
    log.debug("[$$ roomdesk] restore-desk to %s", d.tag)
end

local function getfreeseat(seats, start)
    for i, v in ipairs(seats) do
        if v >= start then
            table.remove(seats, i)
            return v
        end
    end
end

-- call by agent
function desk.join(deskid, user)
    local d = assert(data.desks[deskid], "no desk "..tostring(deskid))
    local playern = gettablen(d.users) + gettablen(d.audiences)
    if playern >= d.maxplayer + d.maxaudience then
        log.debug("user %d join:  %d but desk is full", user.id, deskid)
        return em.desk_full
    end
    if d.usermap[user.id] then
        return em.already_joined
    end

    local start = d.starttime
    if start then
        local timelimit = d.timelimit
        local timeleft = start + timelimit - math.floor(skynet.time())
        local ratio = timeleft / timelimit
        if ratio < 0.1 then
            return em.game_too_short
        end
    end
    -- M. join even game is started.
    -- if d.isstart then
    --     return em.already_in_game
    -- end

    --no cost when join
    -- local isCreater = (d.creater == user.id)
    -- if d.pay and d.pay.AA and not isCreater then
    --     desk_cost_backup(d, user, d.pay)
    -- end

    -- local seat = nil
    -- if d.robotmode and d.robotmode > 0 then
    --     if user.android then
    --         seat = getfreeseat(d.freeseats, d.maxplayer - d.robotmode)
    --     else
    --         seat = getfreeseat(d.freeseats, 1)
    --     end
    -- end
    -- init_user(d, user, seat)

    joinin(d, user)

    d.epush("deskmate", user.id, {
        id = user.id,
        nick = user.nick,
        head = user.head,
        sex = user.sex,
        seat = -1,
        master = user.master,
        ip = user.ip,
        audience = user.audience
    }, false, true)
    log.verbose("%s join %s at seat %d", user.tag, d.tag, user.seat)
end




function desk.genandroid(d, n)
    for i=1,n do
        local au = androiduser.getandroid(d, i)
        au._co = skynet.fork(android_thread, au, d)
    end
end

function desk.sitdown(deskid, userid, withseat)
    local d = assert(data.desks[deskid])
    for _, v in pairs(d.users) do
        if v.id == userid then
            return false, em.repeat_seat
        end
    end

    local user = d.usermap[userid] --not join
    if not user then
        return false, em.not_joined
    end

    if #d.freeseats == 0 then
        return false, em.seat_full
    end

    --assign seat.
    local seat
    if user.android then
        seat = getfreeseat(d.freeseats, 4)
    else
        if withseat then
            seat = remtableitem(d.freeseats, withseat)
            if not seat then
                return false, em.seat_taken
            end
        else
            seat = getfreeseat(d.freeseats, 1)
        end
    end
    log.debug("*************[desk.sitdown] user:%d sit at %d, android? %s", userid, deskid, user.android)
    init_user(d, user, seat)

    local isCreater = (d.creater == userid)
    local pay = d.pay
    if pay and pay.AA and not isCreater then
        if pay.total > 0 then
            local left = prop.use("sitdown", userid, "diamond", pay.total)
            assert(left >= 0, "use prop should always success?")
            user.push("update_account", {diamond = left})
            desk_cost_backup(d, user, pay)
        end
    end

    --TODO delete
    -- local deskmates = {}
    -- for _, u in pairs(d.users) do
    --     if u.id ~= userid then
    --         local uinfo = {
    --             id = u.id,
    --             nick = u.nick,
    --             head = u.head,
    --             sex = u.sex,
    --             seat = u.seat,
    --             master = u.master,
    --             ip = u.ip,
    --             ready = u.ready
    --         }
    --         table.insert(deskmates, uinfo)
    --     end
    -- end

    if d.isstart then
        user.ready = true
    end
    d.epush("deskmate", user.id, {
        id = user.id,
        nick = user.nick,
        head = user.head,
        sex = user.sex,
        seat = user.seat,
        master = user.master,
        ip = user.ip,
        audience = user.audience
    }, false, true)
 --   d.epush("userstate", user.seat, {seat = user.seat, afk=false, userid=userid})

    return true, user.seat, deskmates
end

local function actstandup(d, seat)
    log.debug("[roomdesk] actstandup, seat? %d", seat)

    local user = d.users[seat]
    if not user or seat == -1 then
        return
    end

    d.audiences[user.id] = true
    user.audience = true
    user.seat = -1
    d.users[seat] = nil
    table.insert(d.freeseats, seat)
    service.gamedb.remove_user(d.id, user.id)
end


function desk.remove_mydesk(deskid)
    local d = data.desks[deskid]
    if not d then
        log.warning(string.format("[desk.remove_mydesk] %d not exist in desk service",deskid))
        return
    end
    local creater = d.creater
    if creater then
        local agent = service.watchdog.query(creater)
        if agent then
            skynet.call(agent, "lua", "remove_mydesk", creater, deskid)
        end
    else
        log.warning(string.format("[desk.remove_mydesk] agent not exxist"))
    end
end

function desk.leave(deskid, userid)
    local d = assert(data.desks[deskid], "[desk.leave] no desk.")
    -- if d.isstart and (d.gaming or d.count >= 1) then
    --     return {ok = false, err = em.already_in_game}
    -- end
    local user = d.usermap[userid]
    if user.audience == false then
        return {ok = false, err = em.standup_before_leave}
    end

    assert(user, "can't find user? ".. tostring(userid))
    if not user.audience then
        d.sync:add(user.seat)
    end
    kick_user(d, user)
--    leave(user)
end

function desk.standup(deskid, userid)
    local d = assert(data.desks[deskid], "[desk.standup] no desk.")
    if d.isstart and (d.gaming or d.count >= 1) then
        return {ok = false, err = em.already_in_game}
    end

    local user = d.usermap[userid]
    assert(user, "can't find user? ".. tostring(userid))

    local isCreater = (d.creater == user.id)
    if d.pay and d.pay.AA and not isCreater then
        back_roomcard(d, user.id)
    end

    if user.master then
      --  d.master = nil
      --  user.master = false
        -- for _, u in pairs(d.users) do
        --     if not u.android then
        --         d.master = u.id
        --         u.master = true
        --         d.epush("other_standup", user.seat, {seat = user.seat, masterid = u.id, masterseat=u.seat})
        --         break
        --     end
        -- end
        d.epush("other_standup", user.seat, {seat = user.seat})
    else
        d.epush("other_standup", user.seat, {seat = user.seat})
    end
    actstandup(d, user.seat)

    return {ok = true}
end

function desk.afk(deskid, userid)
    local d = data.desks[deskid]
    if not d then
        log.warning("[desk.afk] no desk, check if it's freed: "..tostring(deskid))
        return
    end

    local user = assert(d.usermap[userid], "mydesk.active wrong, desk has no user "..tostring(userid))
    user.afk = true
    local allafk = function()
        for _, u in pairs(d.usermap) do
            if not u.android and not u.afk then
                return false
            end
        end
        return true
    end
    if allafk() then
        android_notify(d, "all_player_offline")
    end
    changeandroidid(d, userid)
    log.debug("[desk.afk] user afk, deskid: %d seat: %d, uid: %d", deskid, user.seat, userid)
    d.epush("userstate", user.seat, {seat = user.seat, afk = true, userid = userid})
    -- test
    --[[
    local allafk = function()
        for _, u in ipairs(d.users) do
            if not u.afk then
                return false
            end
        end
        return true
    end
    if allafk() then
        timer.add(60, function()
            if allafk() then
                log.debug("TEST FREE DESK %d", deskid)
                d.sync:raise "missbytimeout"
            end
        end)
    end
    ]]
end

function cli:ready(user)
    log.debug("[roomdesk cli:ready] user : %s, master? %s", user.id, user.master)
    if user.audience then
        return {err = em.invalid_request}
    end

    if user.master then
        --start game:
        local has_user = false
        for _, u in pairs(self.users) do
            if u.id ~= user.id then
                has_user = true
                if not u.ready then
                    return {ok = false, err = em.user_not_ready}
                end
            end
        end

        if not has_user then
            return {ok = false, err = em.desk_no_user}
        end

        user.ready = true
        --wake upready
        self.sync:wakeup("ready")
    else
        user.ready = true
        self.epush("other_ready", user.seat, {seat = user.seat})
    end
end

function cli:grab_banker(user, req)
    log.debug("[grab_banker] %s grabbed: %s, started? %s", user.tag, req.grabbed, self.isstart)
    if self.isstart and not user.audience then
        if req.grabbed then
            user.grabbed = true
        end

        self.sync:arrive("banker", user.seat)
    else
        return {ok = false, resp = em.invalid_request}
    end
end

function cli:gamerun(user)
    log.debug("[cli:gamerun] %d send gamerun. android? %s", user.id, user.android)
    self.sync:arrive("gamerun", user.seat)
end

function desk.sceneinfo(deskid, uid)
    local d = data.desks[deskid]
    if not d then
        log.warning("[desk.sceneinfo] no desk, check if over: "..tostring(deskid))
        return {err = em.desk_noexists}
    end
    local g = d:mygame()
    if not g then
        log.warning("[desk.sceneinfo] no game on desk:"..tostring(deskid))
    end

    local si = {}
    local user = d.usermap[uid]
    user.source = service.SOURCE
    if g and d.gaming then
        d:pushconfig(user.seat)
    end

    user.afk = false
    if not d.androidid then
        d.androidid = user.id
    end
    android_notify(d, "has_player_online")
    d.epush("userstate", user.seat, {seat = user.seat, afk=false, userid=uid})

    si.bankerseat = d.banker
    local stat = d.sync:getstatus()
    if not stat and g then
        stat = g._sync:getstatus()
    end
    si.state = stat
    si.users = {}
    for _, u in pairs(d.usermap) do
        table.insert(si.users, {
            id = u.id,
            nick = u.nick,
            head = u.head,
            sex = u.sex,
            seat = u.seat,
            master = u.master,
            score = u.game and u.game.score or -1,
            ip = u.ip,
            afk = u.afk,
            ready = u.ready,
            audience = u.audience
        })
    end

    if d.dismiss then
        si.dismiss = {
            applyer = d.dismiss.applyer,
            cd = d.dismiss.expire - math.floor(skynet.time()),
            replies = d.dismiss.reply,
        }
    end

    si.timelimit = d.timelimit
    if d.gaming and g then
      --  si.fishes = d:all_active_fishes()
      --  si.bullets = d:all_active_bullets()
        si.timeleft = d.starttime + d.timelimit - math.floor(skynet.time())
    end

    return si
end

local function wait_dismiss(d)
    log.debug("desk %s => dismiss", d.tag)
    local msg = {cd = dismiss_max_time, applyer = d.dismiss.applyer}
    local usern = 0
    local dimiss = d.dismiss
    for _, u in pairs(d.users) do
        usern = usern + 1
        if u.seat ~= d.dismiss.applyer then
            dimiss.sync:add(u.seat, true)
            dimiss.wait[u.seat] = u.id
            u.push("other_dismiss_apply", msg)
        end
    end

    local s = dimiss.sync:wait("dismiss", dismiss_max_time)

    if s.driver == "message" then
--        d.dismiss_backup = d.dismiss
        game_interrupt(d, "dismissbyuser")
    elseif s.driver == "timeout" then
        local n = #(dimiss.reply) + 1
        if 2*n > usern then --most agree dismiss
            game_interrupt(d, "dismissbytimeout")
        end
--        d.dismiss_backup = d.dismiss
        --d.sync:raise "dismissbytimeout"
    end
    log.debug("desk %s => wait dismiss over: %s", d.tag, s.driver)
    d.dismiss = nil
end

function cli:dismiss_apply(user)
    if self.dismiss then
        return {err = em.dismiss_already}
    end
    if self.isstart and (self.gaming or self.count >= 1) then
        self.dismiss = {
            applyer = user.seat,
            sync = sync.new(self.maxplayer),
            expire = math.floor(skynet.time()) + dismiss_max_time,
            wait = {},
            reply = {},
        }
        skynet.fork(wait_dismiss, self)

        return {wait = dismiss_max_time}
    else
        if user.master then
            self.dismiss = true
            back_roomcard(self)
            skynet.fork(function()
                local msg = {reason = msgdef.desk_dismiss_tip}
                self.push("dismiss", msg)
            end)
            free_desk(self)
           -- return {resp = "master dismiss ok"}
        else
            desk.standup(self.id, user.id)
            desk.leave(self.id, user.id)
            standup(user)
            return {resp = msgdef.dismiss_standup}
        end
    end
end



function cli:dismiss_reply(user, msg)
    if self.dismiss == nil then
        return {ok = false, err=em.dismiss_no_ins}
    end
    if self.dismiss.wait[user.seat] then
        self.dismiss.wait[user.seat] = nil
        msg.replyer = user.seat
        self.epush("other_dismiss_reply", user.seat, msg)
        if msg.agree then
            table.insert(self.dismiss.reply, user.seat)
            self.dismiss.sync:arrive("dismiss", user.seat)
        else
            self.dismiss.sync:abandon()
        end
    else
        return {ok = false, em.dismiss_no_user}    -- ignore this request
    end
end

function cli:chat(user, msg)
    local now =  math.floor(skynet.time())
    if user.chattime and now < user.chattime+chat_intval then
        return em.chat_frequent
    end
    user.chattime = now

    self.epush("other_chat", user.seat, msg)
end


local err_nodesk = {err = em.desk_noexists}

--called by agent game_handler
function desk.client(deskid, userid, command, args)
    local d = data.desks[deskid]
    if d then
        local user = assert(d.usermap[userid], "desk has no user "..tostring(userid))
        local f = assert(cli[command], "unknown game command "..tostring(command))
        log.debug("[desk.client] %s %s on %s at %d", user.tag, command, d.tag, user.seat)
        return d.cs(f, d, user, args)
    else
        -- this function is wait response mode
        -- skynet.retpack{err = em.desk_noexists}
        return err_nodesk
    end
end

function desk.force_dismiss(deskid)
    local d = data.desks[deskid]
    if d then
        if not d.isstart then
            d.dimiss = true
            for _, u in pairs(d.usermap) do
                if not u.android then
                    u.push("dismiss", {reason = msgdef.desk_dismiss_not_start})
                end
            end
            back_roomcard(d)
            free_desk(d)
            return 1
        else
            log.debug("desk %s is start, can't force dismiss", d.tag)
            return 2
        end
    else
        log.error("force dismiss desk %d is not exists", deskid)
        return 3
    end
end

function desk.exit()
    skynet.timeout(100, function()
        log.debug("will exit desk service mqlen:%d task:%d", skynet.mqlen(), skynet.task())
        skynet.exit()
    end)
end

service.init {
    command = desk,
    require = {"accdb", "gmdb"},
    requireX = {
        {name = data.app, service = "roomlobby"},
        {name = data.app, service = "watchdog"},
    },
    requireB = {
        {service = "statdb"},
        {name = data.app, service = "userdb"},
        {name = data.app, service = "gamedb"},
    },
    init = function()
        math.randomseed(skynet.time())
        local config = sharedata.query("appconfig." .. data.app)
        prop.init(config.props)
    end,
}

