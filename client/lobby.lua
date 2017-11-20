local skynet = require "skynet"
local service = require "common.service"
local message = require "message"
local log = require "common.log"
local cjson = require "cjson"

local address = ...

local data = {}
local client = {}
local event = {}

local function do_message(user)
	local ok, err = pcall(message.dispatch, user) 
	log.notice("Lost server %s : %s", address, err)
	message.close(user)
end

local function do_heartbeat(user)
    while true do
        skynet.sleep(1000)
        message.request(user, "heartbeat")
    end
end

local function do_work(user)
    message.request(user, "userinfo")
    message.request(user, "account")
    message.request(user, "shop", {name="diamond"})
    message.request(user, "notice", {lastid=0})
 
    message.request(user, "desklist")
  --message.request(user, "sitdown")

  --message.request(user, "join", {deskid = 174000})
  -- message.request(user, "create", {game = "fish", info = {
  --   	timelimit = 180,
  --   	aapay = false,
  --   	cannonscore = 1,
  --   	}})

  --  message.request(user, "create", {game = "fish", info = {
  --   	timelimit = 360,
  --   	aapay = true,
  --   	cannonscore = 2,
  --   	}})

  --  message.request(user, "create", {game = "fish", info = {
  --   	timelimit = 180,
  --   	aapay = false,
  --   	cannonscore = 2,
  --   	}})

  skynet.fork(do_heartbeat, user)

 --   message.request(user, "signout")
end

function client.open(username)
	--username = "liuwh12345"
	local user = {name = username}
	message.bind(user, event)

	local ok, err = pcall(message.handshake, user)
	if not ok then
		log.error("%s handshake failed : %s", username, err)
		return
	end

    if true then
      --  return
    end

	user.id = err 
	skynet.fork(do_message, user)
    skynet.fork(do_work, user)
	log.notice("%s:%d handshake succ", username, user.id)
end

function event:heartbeat(req, resp)
    log.debug("event.heartbeat : %d", resp.now)
end

function event:userinfo(req, resp)
    log.debug("event.userinfo : %s", cjson.encode(resp))
end

local deskid = 0

function event:create(req, resp)
    if resp.err then
        log.error("event.create error : %s", resp.err.msg)
        return
    end
    log.debug("event.create: %d", resp.deskid)
    --it's ok.
    deskid = resp.deskid
    message.request(self, "join", {deskid = deskid})
end

function event:account(req, resp)
    log.debug("event.account diamond:%d", resp.diamond)
end

function event:standup(req, resp)
	if resp.err then
		log.error("event.standup error: %s",resp.err.msg)
		return
	end
    log.debug("event.standup " .. tostring(resp.ok))

    message.request(self, "join", {deskid = deskid})
end

function event:sitdown(req, resp)
	if resp.err then
		log.error("event.sitdown error: %s",resp.err.msg)
		return
	end

	log.debug("sitdown at: " .. resp.seat)
--	message.request(self, "ready", resp.seat)
--	message.request(self, "desklist")
--	message.request(self, "standup")
--	message.request(self, "dismiss_apply")


    -- message.request(self, "chat", {
    -- 	fromid = resp.seat,
    -- 	toid = -1,
    -- 	type = "emoji",
    -- 	content = "hahaa"
    -- 	})
end

function event:join(req, resp)
	if resp.err then
		log.error("event.join error: %s",resp.err.msg)
		return
	end
	log.debug("chat resp: %s", cjson.encode(resp))
	    message.request(self, "sitdown", {deskid = deskid})
end

function event:chat(req, resp)
	if resp.err then
		log.error("event.chat error: %s",resp.err.msg)
		return
	end
	log.debug("chat resp: %s", cjson.encode(resp))
end

function event:dismiss_apply(req, resp)
	if resp.err then
		log.error("event.dismiss_apply error: %s",resp.err.msg)
		return
	end
	log.debug("wait %d, resp: %s", wait, resp)
end

function event:notice(req, resp)
	for _, v in ipairs(resp.items) do
		log.debug("notice color %d, notice :%s", v.color, v.content)
	end
    message.request(self, "notice", {lastid = resp.lastid})
end

function event:shop(req, resp)	
	log.debug("event.shop %s", cjson.encode(resp))
--	message.request(self, "buy", {name = "diamond", id = resp["items"][1].id})
end

function event:update_account(req)
	log.debug("[push] update_account: %d", req.diamond)
end

function event:buy(req, resp)
	log.debug("event:buy: %s", cjson.encode(resp))

	message.request(self, "payorders", {})
end

function event:payorders(req, resp)
	local orders = resp.orders

	for _, v in ipairs(orders) do

		for k, v2 in pairs(v) do
			log.debug("pay order: %s, %s", k, v2)
		end
	end
end

function event:desklist(req, resp)
	log.debug("Get ROOMLIST: %s", cjson.encode(resp))
end


service.init {
	command = client,
	info = data,
	init = function()
        message.init()
        message.register "fish"
		message.peer(address)
	end,
}

