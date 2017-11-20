
local skynet = require "skynet"
local log = require "common.log"
local M = {}

local ipaddr = {
	"125.70.77.44",
	"27.44.196.255",
	"183.60.93.249",
	"140.205.16.92",
	"27.184.95.255",
	"27.185.255.255",
	"36.149.27.255",
	"27.115.61.255",
}

local nicks = {
	"无聊小事",
	"王毛",
	"吴峰",
	"中國毛豆",
	"mela",
	"會飛淂魚",
	"菜如狗",
	"练爱对象",
	"战界のMiku",
	"温柔里的倔强",
	"Sky丶逍遥子",
	"膽小鬼灬",
	"别说你狠牛",
	"Ruleヽ 宅男",
	"baby、魅影",
}

local android = {}

function android:onevent(name, wake, ...)
	log.debug("androiduser onevent: %s ", name)
	if wake == true then
		skynet.wakeup(self._co)
	end
	local ai = self.ai
	if ai then
		ai:onevent(name, ...)
	end
end

function android:attachAI(ai)
	self.ai = ai
end

function android:update(dt)
	local ai = self.ai
	if ai then
		ai:update(dt)
	end
end

function M.getandroid(d, index)
	local a = {}

	local deskid = d.id
	--1000000
	a.id = math.random(200000, 998998)
	a.sex = math.random(1, 2)
	a.nick = nicks[(deskid + index) % #nicks + 1]
	a.ip = ipaddr[(deskid + index) % #ipaddr + 1]
	a.android = true
	a.tag = a.id .. ":"..a.nick
	a.game = {score = 0}
	setmetatable(a, {__index=android})

	return a
end

function M.restoreandroid(userinfo)
	userinfo.tag = userinfo.id .. ":"..userinfo.nick
	setmetatable(userinfo, {__index=android})
	return userinfo
end


return M