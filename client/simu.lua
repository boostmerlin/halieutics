local skynet = require "skynet"
local service = require "common.service"
local message = require "message"
local log = require "common.log"
local cjson = require "cjson"
local socket = require "client.socket"

local def = require "def"

local address = ...

local client = {}
local event = {}

local tag

local identity

local self_index


local function clog(str_format, ...)
	log.debug(string.format("%s  %s", tag, str_format), ...)
end

local function make_cmd(name, args)
	return name.. " " .. cjson.encode(args)
end

local function use_cmd(cmd, user)
	local cmd, para = cmd:match("(%g+)%s*(.*)")
	local paraobj = def[cmd]
	if not paraobj and para and para ~= "" then
		local ok, ret = pcall(cjson.decode, para)
		if not ok then
			clog(" !! Json decode para exception..")
			return
		end
		paraobj = ret
	end

	if paraobj == nil then
		paraobj = {}
	end

	clog("Final Request Para: %s", cjson.encode(paraobj))
	message.request(user, cmd, paraobj)
end

local auto_works = {
	["1"] = {
		current = 1,

		make_cmd("mydesk", {}),
		make_cmd("create", {game = "fish", info = {
	    	timelimit = 180,
	    	aapay = true,
	    	cannonscore = 1,
    	}}),

	}
}

local function auto_run(user)
	local works = auto_works[identity]
	print("auto run on .. ", identity)
	if not works then
		return
	end

	local cmd = works[works.current]
	if cmd then
		print("auto run cmd .. ", cmd)
		use_cmd(cmd, user)
		works.current = works.current + 1
	end
end 



local function do_message(user)
	local ok, err = pcall(message.dispatch, user) 
	log.notice("Lost server %s : %s", address, err)

	message.close(user)
end

local function do_heartbeat(user)
    while true do
        skynet.sleep(10000)
        message.request(user, "heartbeat")
    end
end



local function do_work(user)
	skynet.fork(do_heartbeat, user)
	if identity == "1" then
		auto_run(user)
	end
	while true do
		local str = socket.readstdin()
		if str then
			use_cmd(str, user)
		else
			socket.usleep(1000)
		end
		skynet.sleep(50)
	end
end

local deskid
function event:heartbeat(req, resp)
    --log.debug("event.heartbeat : %d", resp.now)
end

function event:mydesk(req, resp)
	if not resp.active then
		auto_run(self)
	else
		log.debug("MYDESK is: %s", resp.active)
	end
end

function event:create(req, resp)
    if resp.err then
        log.error("event.create error : %s", resp.err.msg)
        return
    end
	deskid = resp.deskid
    message.request(self, "join", {deskid = resp.deskid})
end

function event:join(req, resp)
	if resp.err then
		log.error("event.join error: %s",resp.err.msg)
		return
	end

   -- message.request(self, "sitdown", {deskid = req.deskid})
end

function client.open(username, id, i)
	identity = id
	self_index = i
	local user = {name = username}
	message.bind(user, event)

	local ok, err = pcall(message.handshake, user)
	if not ok then
		log.error("%s handshake failed : %s", username, err)
		return
	end

	user.id = err

	tag = "["..username..":"..err.."]"

	skynet.fork(do_message, user)
    skynet.fork(do_work, user)
	clog("%s:%d handshake succ", username, user.id)
end

service.init {
	command = client,
	init = function()
        message.init()
        message.register "fish"
		message.peer(address)
	end,
}

