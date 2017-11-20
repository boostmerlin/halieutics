local skynet = require "skynet"
local sharedata = require "skynet.sharedata"
local service = require "common.service"
local client = require "common.client"
local log = require "common.log"
local em = require "def.errmsg"
local cjson = require "cjson"
local msgdef = require "def.msgdef"

local prop = require "module.prop"

local invite = require "module.invite"

local mod = require "module.sharedmod"
local broadcast = require "module.broadcast"

local json_enc = cjson.encode
local json_dec = cjson.decode
local str_format = string.format
local m_ceil = math.ceil

local sharedinfoMod

local agent = {}
local data = {
    app = tostring(...), 
    users = {}
}

local MAX_HEARTBEAT = 30
local PER_PAGE_ITEM_NUM = 4 

local cli = {}

local function getuser(self)
    self.__user = self.__user or {
        id = self.id,
        ip = self.ip,
        nick = self.uname,
        head = self.head,
        sex = self.sex,
        tag = self.tag,
    }
    return self.__user
end

function cli:heartbeat()
    local now = math.floor(skynet.time())
    self.heartbeat = now
    return {now = now}
end

function cli:userinfo()
    local n = service.userdb.get_user_prop(self.id, "diamond")
    local recode = service.userdb.get_bind_recode(self.id)
    return {
        nick = self.uname,
        head = self.head,
        sex = self.sex,
        uid = self.id,
        diamond = n,
      --  phone = "null",
        recode = recode
    }
end

function cli:account()
    return service.userdb.get_account(self.id)
end

function cli:total()
    local totalgames = service.gamedb.get_mygame_results(self.id)

    return {mygames = totalgames}
end

local empty_bag = {items = {}}
function cli:mybag()
    local bag = prop.bag(self.id)
    return bag and {items = bag} or empty_bag
end

function cli:create(req)
    if self.mydesk.active then
        local deskid = self.mydesk.active.id
        log.error("cli:create already_in_desk: %d", self.mydesk.active.id)
        return {err = em.already_in_desk, deskid=deskid}
    end
    local limit = data.config.limit.create
    if service.userdb.get_create_desk_num(self.id) >= limit then
        return {err = em.create_limit}
    end

    req.info.game = assert(req.game, "what is the game?")
    req.info.roomtype = req.roomtype
    req.info.robotmode = req.robotmode

    local ok, desk = pcall(service.roomlobby.assign, self.id, req.info)
    if not ok then
        return {err = em.invalid_request}
    end
    if desk then
        local pay = desk.info.pay
        local detail = {id = desk.id, game = desk.info.game}
        local num = pay.total --no check player bag here
        if pay.total > 0 then
            num = prop.use("create", self.id, "diamond", pay.total, detail)
        end
        if num >= 0 then
            skynet.call(desk.service, "lua", "create", desk.info, getuser(self), true)
            service.userdb.create_desk(self.id, desk.id)
            log.debug("[agent] create desk into mydesk.creat....")
            table.insert(self.mydesk.create, desk)
            -- update accout ?
            if pay.total > 0 then --in case num is zero.
                agent.push(self.id, "update_account", {diamond = num})
            end
            return {deskid = desk.id}
        else
            service.roomlobby.free(desk.id)
            return {err = em.card_lack}
        end
    else
        return {err = em.no_free_desk}
    end
end

function cli:join(req)
    if self.mydesk.active then
        return {err = em.already_in_desk}
    end

    local deskid = assert(req.deskid)
    local desk = service.roomlobby.query(deskid)
    log.debug("[cli:join] query deskid: %d from roomlobby, userid: %d", deskid, self.id)
    if desk then
        log.debug("[cli:join] query desk info: %s", cjson.encode(desk))

        -- local pay = desk.info.pay
        -- local isCreater = (desk.creater == self.id)
        -- local recorduse = -1
        -- if pay and pay.AA and pay.total > 0 and not isCreater then
        --     local detail = {id = deskid, game = req.game}
        --     local left = prop.use("join", self.id, "diamond", pay.total, detail)
        --     if left < 0 then
        --         return {err = em.card_lack}
        --     end
        --     recorduse = left
        -- end

        local err = skynet.call(desk.service, "lua", "join", deskid, getuser(self))
        if err == nil then
            self.mydesk.active = desk
            -- log.verbose("join-desk %s %s:%d", self.tag, desk.info.game, deskid)
            -- if recorduse >= 0 then
            --     agent.push(self.id, "update_account", {diamond = recorduse})
            -- end
        else
            -- if recorduse >= 0 then
            --     prop.add("join", self.id, "diamond", pay.total, {d = deskid})
            -- end
            return err and {err = err} or client.no_resp
        end
    else
        return {err = em.desk_noexists}
    end
end

function cli:deskinfo(req)
    local deskid = assert(req.deskid)
    local desk = service.roomlobby.query(deskid)

    if desk then
        return {cost = desk.info.pay.total, info={
            timelimit = desk.info.timelimit,
            aapay = desk.info.aapay,
            cannonscore = desk.info.cannonscore,
        }}
    else
        return {err = em.desk_noexists}
    end
end

function cli:sceneinfo()
    local desk = self.mydesk.active
    if desk then
        return skynet.call(desk.service, "lua", "sceneinfo", desk.id, self.id)
    else
        return {err = em.desk_noexists}
    end
end

function cli:mydesk()
    local ret = {}
    if self.mydesk.active then
        ret.active = self.mydesk.active.id
    elseif #self.mydesk.create > 0 then
        ret.create = {}
        for _, d in ipairs(self.mydesk.create) do
            table.insert(ret.create, d.id)
        end
    end
    return ret
end

function cli:sitdown(req)
    -- local deskid = service.userdb.get_active_desk(self.id)

    -- if not deskid then
    --     return {err = em.invalid_request}
    -- end
    local desk = service.roomlobby.query(req.deskid)
    if desk then
        --if not aa, check money
        local userid = self.id
        local pay = desk.info.pay
        if pay.AA and pay.total > 0 and desk.info.creater ~= userid then
            if not prop.check(userid, "diamond", pay.total) then
                return {err = em.card_lack}
            end
        end
        local flag, ret, mates = skynet.call(desk.service, "lua", "sitdown", desk.id, userid, req.seat)
        if flag then
            log.debug("[cli:sitdown], self info: %s", cjson.encode(self))
         --   self.mydesk.active = desk
            return {seat = ret, ip = self.ip, deskmates = mates}
        else
            return {err = ret}
        end
    else
        return {err = em.desk_noexists}
    end
end

function cli:standup()
    local desk = self.mydesk.active
    if desk then
        log.debug("[cli:standup] user %d standup from d: %d", self.id, desk.id)
        return skynet.call(desk.service, "lua", "standup", desk.id, self.id) 
    end
end

function cli:leave()
    local desk = self.mydesk.active
    if desk then
        log.debug("[cli:leave] user %d leave desk: %d", self.id, desk.id)
        local ret = skynet.call(desk.service, "lua", "leave", desk.id, self.id)
        if not ret then
            self.mydesk.active = nil
        else
            return ret
        end
    end
end

function cli:signout()
    log.notice("signout: %d", self.id)
    agent.kick(self.id, true)
end

function cli:shop(req)
    log.debug("shop info request %s", req.name)
   -- local list = shopmod:list(req.name)
    local list = mod.listconfig("shop", "diamond", req.name)
    if list then
        return {items = list}
    else
        return client.no_resp
    end
end


local function buypayed(orderid, userid, v)
    if service.gmdb.update_order(orderid) then
        local n = prop.add("buypayed", userid, v.prop, v.num)
        agent.push(userid, "buy_notice", {ok = true, reason = "payed"})
        agent.push(userid, "update_account", {diamond = n})
    else
        agent.push(userid, "buy_notice", {ok = false, reason = "pc order id not found"})
    end
end

function cli:buy(req)
    local list = mod.listconfig("shop", "diamond", req.name)
  --  local list = shopmod:list(req.name)
    for _, v in ipairs(list) do
        if v.id == req.id then
            local orderid = service.gmdb.buy(v, self.id)
            --request orderid
            log.debug("[cli:buy] gen pay order: %s", orderid)
            --test
            buypayed(orderid, self.id, v)
            return {ok = true, reason = msgdef.buy_unpay}
        end
    end
    log.error("[agent.buy] not found any item in shop cfg.")
    return {err = em.buy_error}
end

function cli:payorders(req)
    local rechargeorders = service.gmdb.get_all_recharge_orders(self.id)
    for _, v in ipairs(rechargeorders) do
        v.num = tonumber(v.num)
        v.price = tonumber(v.price)
        v.timestamp = tonumber(v.timestamp)
    end

    return {orders = rechargeorders}
end

--desk of my create.
function cli:desklist()
    local mydesks = self.mydesk.create

    if not mydesks then
        return client.no_resp
    end

    local rooms = {}
    for _, d in ipairs(mydesks) do
        local room = {}
        room.id = d.id
        room.timestamp = d.info.time
        room.master = d.info.master
        room.timelimit = d.info.timelimit
        room.usern = skynet.call(d.service, "lua", "usern", d.id)
        room.aapay = d.info.aapay
        room.cannonscore = d.info.cannonscore
        room.roomtype = d.info.roomtype
        table.insert(rooms, room)
    end

    return {rooms = rooms}
end


function cli:invite_bind(req)
    local ok, err = invite.bind(self.id, req.recode)
    if ok then
        for _, l in ipairs(err) do
            if l.prop == "diamond" then
                agent.push(self.id, "update_account", {diamond = l.num})
            end
        end
        return {ok = true}
    else
        return {err = err}
    end
end

local test = 1
function cli:notice(req)
    if test == nil then
        test = true
        skynet.fork(function()
            while true do
                skynet.sleep(1000)
                broadcast.notice(str_format("这是一个测试公告:%d"))
            end
        end)
    end
    return broadcast.pull(req.lastid)
end

function cli:shareinfo()
    return sharedinfoMod:list()
end

function cli:smallhorn(req)
    local ok, err = broadcast.smallhorn(self.id, req.content)
    if ok then
        return {ok = true, props = err}
    end
    return {err = err}
end

local function game_handler(c, command, req)
    local desk = c.mydesk.active
    if desk then
        local r = skynet.call(desk.service, "lua", "client", desk.id, c.id, command, req)
        if r == false then
            return client.no_resp
        end
        return r
    else
        return {ok = false, err=em.not_in_desk}
    end
end

local function new_user_msgloop(c)
	local ok, err = pcall(client.dispatch, c, "agent")
	log.notice("[agent] %s is gone : %s", c.tag, err)
    if c.force then
        c.force = nil
        return
    end
    pcall(client.close, c.fd)
	local user = data.users[c.id]
	if user and user.fd == c.fd then
		user.fd = nil
        service.watchdog.afk(user.id)
        if user.mydesk.active then
            pcall(skynet.call, user.mydesk.active.service, "lua", "afk", user.mydesk.active.id, user.id)
        end
		skynet.sleep(2000)  -- wait client reconnect
        if user.fd == nil and not user.clear then
            if not user.exit then
                user.exit = true
                data.users[user.id] = nil
                service.watchdog.exit(user.id)
                log.notice("exit2 %s %s", data.app, user.tag)
            end
        end
	end
end

local function restore_mydesk_from_db(user)
    log.debug("[restore_mydesk_from_db] for user: %d", user.id)
    user.mydesk = {create = {}}
    local mydesk = service.userdb.get_mydesk(user.id)
    local acd = mydesk.active
    if acd then
        local desk = service.roomlobby.query(acd)
        if desk then
            user.mydesk.active = desk
            table.insert(user.mydesk.create, desk)
            log.debug("[agent@restore_mydesk] restore %s mydesk active id: %d [%s]", 
            user.tag, mydesk.active, skynet.address(desk.service))
        else
            log.notice("[agent@restore_mydesk] no desk in roomlobby, game over??")
        end
    else
        log.notice("[agent@restore_mydesk], no active desk.")
    end
    if mydesk.create then
        for _, id in ipairs(mydesk.create) do
            if id ~= acd then
                log.debug("[agent@restore_mydesk] about to restore %s mydesk create %d", user.tag, id)
                local desk = service.roomlobby.query(id)
                if desk then
                    table.insert(user.mydesk.create, desk)
                else
                    service.userdb.dismiss(user.id, id)
                    log.debug("[agent@restore_mydesk] Restore mydesk error, user db and game db not sync")
                end
            end
        end
    else
        log.notice("[agent@restore_mydesk], no create desk.")
    end
end

local function get_avatar(c)
    local uinfo = service.userdb.get_avatar(c.id)
    if uinfo then
        c.nick = uinfo.nickname
        c.head = uinfo.head
        c.sex = uinfo.sex
        c.sign = uinfo.sign
        c.time = uinfo.time
    end
    return c
end

function agent.assign(c)
	local user = data.users[c.id]
    if user then
        log.debug("[agent.assign] has user ???? %s", cjson.encode(user))
        if user.exit then
            return false
        end
        if user.fd == nil then
            user.fd = c.fd
            user.tag = c.tag
        end
    else
        -- test(c.id)
        user = get_avatar(c)
        data.users[c.id] = user 
        restore_mydesk_from_db(user)
    end
	skynet.fork(new_user_msgloop, user)
	return true
end

function agent.try_kick(userid)
    local user = data.users[userid]
    if user and not user.exit then
        local heartbeat = user.heartbeat or 0
        local now = math.floor(skynet.time())
        if now > heartbeat + MAX_HEARTBEAT then
            log.debug("try-kick %s from agent %d:%d", user.tag, now, heartbeat)
            if user.mydesk.active then
                skynet.call(user.mydesk.active.service, "lua", "afk", user.mydesk.active.id, user.id)
            end

            return true
        end
    end
end

function agent.kick(userid, clear)
    local user = data.users[userid]
    if user then
        log.debug("kick %s from %s.agent, fd: %d", user.tag, data.app, user.fd)
        if user.fd then
            client.close(user.fd)
            user.force = user.fd
            user.fd = nil
        end
        if clear then
            user.clear = true
            data.users[userid] = nil
        end
    end
end

function agent.remove_mydesk(userid, deskid)
    local user = data.users[userid]
    log.debug("[agent.remove_mydesk] notify remove user: %d, desk: %d, %s", userid, deskid, cjson.encode(user))
    if user then
        if user.mydesk.active and user.mydesk.active.id == deskid then
            user.mydesk.active = nil
        end
        local mydesks = user.mydesk.create

        if mydesks then
            for i, v in ipairs(mydesks) do
                if v.id == deskid then
                    log.debug("[agent.remove_mydesk] remove mycreate desk: %d", v.id)
                    table.remove(mydesks, i)
                    break
                end
            end
        end
    end
end


function agent.standup(userid)
    local user = data.users[userid]
    if user then
        log.debug("[agent.standup] userid: %d", userid)
        user.mydesk.active = nil
    end
end

function agent.push(userid, command, args)
    local user = data.users[userid]
    if user and not user.exit and user.fd then
        client.push(user.fd, command, args)
        log.debug("[agen.PUSH] userid: %d, cmd: %s, args: %s", userid, command, args and json_enc(args) or "nil")
    end
end

function agent.broadcast(command, args)
    local fds = {}
    for _, user in pairs(data.users) do
        if not user.exit and user.fd then
            table.insert(fds, user.fd)
        end
    end
    if #fds > 0 then
        client.mpush(fds, command, args)
    end
end

function agent.close()
    broadcast.close()
    for _, user in pairs(data.users) do
        if user.fd then
            user.force = user.fd
            user.fd = nil
            pcall(client.close, user.force)
        end
    end
    skynet.exit()
end

local function init_modules(conf)
    log.debug("---------------------------[agent] init_modules..")
    broadcast.init(data.app, conf.broadcast)
    prop.init(conf.props)
    invite.init(conf.invite)
    local noticemod = mod.init("notice", "system")
    local items = noticemod:list()

    if items then
        for _, v in ipairs(items) do
            broadcast.noticeitem(v)
        end
    end

    sharedinfoMod = mod.init("notice", "share")
--    prop.add("innner test", 1000002, "diamond", 10)
    -- shopmod = mod.init("shop")
end
service.init {
	command = agent,
	info = data,
    require = {"accdb"},
    requireX = {
        {name = data.app, service = "roomlobby"},
        {name = data.app, service = "watchdog"},
    },
    requireB = {
        {name = data.app, service = "userdb"},
        {name = data.app, service = "gamedb"},
    },
    init = function()
        log.debug("[agent] service.init func. ")
        client.proto(data.app)
        client.bind(cli, game_handler)
        data.config = sharedata.query("appconfig."..data.app)
        init_modules(data.config)
    end,
    shutdown = function()
        for _, user in pairs(data.users) do
            if user.fd then
                user.force = user.fd
                user.fd = nil
                pcall(client.close, user.force)
            end
        end
    end,
}

