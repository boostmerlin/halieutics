
local log = require "common.log"
local cjson = require "cjson"
local def = require "game.fish.def"

local json_enc = cjson.encode

local AI = {}
local rand = math.random

local targetscore = 10000.0

function AI.create(g, user)
	local ai = setmetatable({}, {__index=AI})
	ai.g = g
	ai.user = user
	ai.bullet_kind = 0
	ai.kill = 0
	ai.last_fire_angle = 0
	ai.allow_fire = user.seat ~= g.banker
	ai.firecount = 0
	ai.cease_fire = false

	return ai
end

local kFireAngle = { 6.28-1.47,6.28-1.27,6.28-0.97,6.28-0.67,6.28-0.37,6.28-0.07
, 0, 0.07, 0.37, 0.67, 0.97, 1.27, 1.47 }
for i, v in ipairs(kFireAngle) do
	kFireAngle[i] = math.floor(v * 57.29)
end

local function getangle(last_fire_angle)
	local angle
	local idx = 0
	local nrand = function ()
		return math.random(1, 99923)
	end
	for i = 1, #kFireAngle do
		if last_fire_angle == kFireAngle[i] then
			idx = i;
			break;
		end
	end

	local n = nrand() % 5 - 1
	if idx - n < 1 then
		idx = nrand() % 5 + 1
	elseif idx + n > #kFireAngle then
		idx = #kFireAngle - (nrand() % 7);
	else
		idx = idx + n;
	end

	angle = kFireAngle[idx] or last_fire_angle;

	return angle
end

local function change_bullet(ai)
	ai.firecount = ai.firecount + 1
	if ai.firecount % rand(3, 6) == 0 then
		ai.bullet_kind = rand(0, 2)
	end
end

local function onfire(user, ai)
	if not ai.allow_fire or ai.cease_fire then
		return
	end

	local score = targetscore - user.game.score
	local prob = score / (targetscore + 200)

	local p = rand()

	if p > prob then
		return
	end

	local req = {}
	req.bullet_kind = ai.bullet_kind
	local angle = getangle(ai.last_fire_angle)
	ai.last_fire_angle = angle or 0
	req.angle = angle or 0
	req.lock_fishid = -1
	log.debug("[android fire] %d on: %s",user.id, json_enc(req))

	change_bullet(ai)

	ai.g:userfire(user, req)
end

function AI:onevent(name, ...)
	log.debug("AI onevent %s, user: %d", name,self.user.id)
	if def.ACTION_CHANGE_BULLET == name then
		change_bullet(self)
	elseif "gameend" == name then
		self.allow_fire = false
	elseif def.ACTION_BANKER == name then
		local bankerseat =  ...
		log.debug("[AI:onevent] Change Banker: %d", bankerseat)
		self.allow_fire = self.user.seat ~= bankerseat
	elseif "dismiss" == name then
	    local sendf = self.user.send
	    if sendf then
			sendf("dismiss_reply", {agree = true})
	    end
	elseif def.ACTION_NOPLAYER == name then
		self.cease_fire = true
	elseif def.ACTION_HASPLAYER == name then
		self.cease_fire = false
	end
end

local dt_accumulate = 0
function AI:update(dt)
	dt_accumulate = dt_accumulate + dt
	onfire(self.user, self)
	if dt_accumulate < 100 then
		return
	end
	dt_accumulate = 0
	if self.g.dismiss then
		log.debug("[simu android dismiss] %d, deskid: %d", self.user.id, self.g.id)
		self.user.send("dismiss_reply", {agree=true})
	end
end

return AI