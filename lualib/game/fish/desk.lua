local def = require "game.fish.def"
local skynet = require "skynet"
local sync = require "game.sync"
local timer = require "common.timer"
local smod = require "module.sharedmod"
local log = require "common.log"
local errmsg = require "def.errmsg"
local AI = require "game.fish.ai"
local sdk = require "game.fish.sdk"

local desk = {}

local rand = function ()
	return math.random(1, 99999)
end

function desk.create(d)
	d.maxplayer = def.maxplayer
	d.maxaudience = def.maxaudience
	d.cycle = def.cycle
	setmetatable(d, {__index=function(t, k)
		if rawget(t, "gaming") == false then
			log.error("[desk] ask for desk logic after game have ended: %s, d.count: %d", k, rawget(t, "count"))
		else
			return desk[k]
		end
	end})

	return d
end

local function buildfishtrace(g, n, kind_start, kind_end)
--	local sdk = assert(g._sdk)
	local traces_info = sdk.buildfishtrace(g, n, kind_start, kind_end)
	log.debug("[buildfishtrace] buildfishtrace count: %d, desk: %d, kind from %d to %d", #traces_info, g.id, kind_start, kind_end)

	for _, v in ipairs(traces_info) do
		g.push("fishtrace_bbc", v)
	end
end

local function OnTimerBuildSmallFishTrace(g)
	  buildfishtrace(g, 2 + rand() % 6, def.FISH_KIND_5, def.FISH_KIND_10);
end

local function OnTimerBuildSmallFishNewTrace(g)
	  buildfishtrace(g,2 + rand() % 6, def.FISH_KIND_1, def.FISH_KIND_4);
end

local function OnTimerBuildMediumFishTrace(g)
	  buildfishtrace(g,1 + rand() % 2, def.FISH_KIND_11, def.FISH_KIND_17);
end

local function OnTimerBuildFish18Trace(g)
	  buildfishtrace(g,1, def.FISH_KIND_18, def.FISH_KIND_18);
end

local function OnTimerBuildFish19Trace(g)
	  buildfishtrace(g,1 + rand() % 3, def.FISH_KIND_19, def.FISH_KIND_19);
end

local function OnTimerBuildFish20Trace(g)
	  buildfishtrace(g,1 + rand() % 2, def.FISH_KIND_20, def.FISH_KIND_20);
end

local function OnTimerBuildFishBankerTrace(g)
	  buildfishtrace(g,1, def.FISH_KIND_23, def.FISH_KIND_23);
end

local function OnTimerBuildFishLockBombTrace(g)
      buildfishtrace(g,1, def.FISH_KIND_22, def.FISH_KIND_22);
end

local function OnTimerBuildFishSuperBombTrace(g)
	  buildfishtrace(g,1, def.FISH_KIND_24, def.FISH_KIND_24);
end

local function OnTimerBuildFishSanTrace(g)
	  buildfishtrace(g,1 + rand() % 2, def.FISH_KIND_25, def.FISH_KIND_27);
end

local function OnTimerBuildFishSiTrace(g)
	  buildfishtrace(g,1 + rand() % 2, def.FISH_KIND_28, def.FISH_KIND_28);
end

local function OnTimerClearTrace(g)
    g.roles:Update()
end

local specialTimerItem = {
	{name = "kClearInvalidTimer", elapsed = 6, func = OnTimerClearTrace},
}

local function on_timer_out(g, kind, count, countMax)
	buildfishtrace(g,math.random(count, countMax), kind, kind);
end

local function start_timer(g, name, elapsed, func)
	if not g.specialtimers then
		g.specialtimers = {}
	end

	local tid = timer.add(elapsed, func or on_timer_out, g)
	g.specialtimers[name] = tid
	return tid
end

local function stop_timer(g, name)
	local tid = g.specialtimers[name]
	if tid then
		timer.remove(tid)
		g.specialtimers[name] = nil
	end
end

local function startalltimers(g)
	if not g.timers then
		g.timers = {}
	end
	local fishcfg = g._sdk.config.fishcfg
	local count
	local elapsed
	--local offset
	for _, fish in ipairs(fishcfg) do
		count = fish.count >=0 and fish.count or 1
		count = count > 6 and 6 or count
		local countMax = fish.countMax
		if not countMax then
			countMax = count
		else
		    countMax = countMax >= count and countMax or count
		end
		countMax = countMax > 10 and 10 or countMax
		elapsed = fish.elapsed or 10
	--	offset = math.floor(elapsed / 4)
	--  local	math.random(elapsed-offset, elapsed+offset)
		local tid = timer.add(elapsed, on_timer_out, g, fish.kind, count, countMax)
		log.debug("[startalltimers] start fish timer: %d, %d, elapsed:%d", tid, fish.kind, elapsed)
		g.timers[fish.kind] = tid
		local tmr = timer.get(tid)
		tmr.repeated = true
	end

	-- build fish right away.
	OnTimerBuildSmallFishTrace(g)
	OnTimerBuildSmallFishNewTrace(g)
--	OnTimerBuildMediumFishTrace(g)
--	OnTimerBuildFish18Trace(g)

	-- for _, ti in ipairs(timerItem) do
	-- 	offset = math.floor(ti.elapsed / 4)
	-- 	local tid = timer.add(math.random(ti.elapsed-offset, ti.elapsed+offset), ti.func, g, ti.name)
	-- 	log.debug("[startalltimers] start timer: %d, %s", tid, ti.name)
	-- 	g.timers[ti.name] = tid
	-- 	local tmr = timer.get(tid)
	-- 	tmr.repeated = true
	-- end

	--start speical timer.
	for _, ti in ipairs(specialTimerItem) do
		local tid = start_timer(g, ti.name, ti.elapsed, ti.func)
		local tmr = timer.get(tid)
		tmr.repeated = true
	end
end

local function stopalltimers(g)
	if not g.timers then
		return
	end
	log.debug("[stopalltimers] stop all timer")

	for _, v in pairs(g.timers) do
		timer.remove(v)
	end
	g.timers = nil

	--stop special timer.
	stop_timer(g, "kClearInvalidTimer")
end

local function adduserscore(user, score)
	assert(user and user.game)
	user.game.score = user.game.score + score

	return user.game.score
end

function desk:init()
	self._game = setmetatable({
		_sdk = sdk,
		_sync = sync.new(),
		}, {__index=self})

	if true or self._game._sdk.config == nil then --share the config.
		self._cfgmod = smod.init("gameplay", "play")
		local cfg = {}
		cfg.max_bullet_multiple = self._cfgmod:list("Cannon").cannonMaxMultiple
		cfg.bomb = self._cfgmod:list("Bomb")
		cfg.fishcfg = self._cfgmod:list("Fish")
		table.sort(cfg.fishcfg, function (a, b)
			return a.kind < b.kind
		end)
		cfg.bulletcfg = self._cfgmod:list("Bullet")
		table.sort(cfg.bulletcfg, function (a, b)
			return a.kind < b.kind
		end)
		cfg.stockcfg = self._cfgmod:list("Stock")
		table.sort(cfg.stockcfg, function (a, b)
			return a.value > b.value
		end)
		self._game._sdk.config = cfg
	end
	self._game.roles = sdk.roles.create()
end

local function gameend(g)
	stopalltimers(g)
	-- if g.specialtimers then
	-- 	for _, v in ipairs(g.specialtimers) do
	-- 		timer.remove(v)
	-- 	end
	-- end

	g.roles:FreeAll()

	g._sdk = nil
	g._sync = nil
	for _, u in pairs(g.users) do
		if u.android then
			u:onevent("gameend", true)
		end
	end
end

local function new_game(g)
	--send gamecfg.
	g.push("gameconfig", g._sdk.config, true)

	startalltimers(g)

	log.debug("[new_game] game running on limit: %d", g.timelimit)

	g._sync:wait("gameend", g.timelimit)

	gameend(g)
end

function desk:pushconfig(seat)
	local g = self._game
	local u = g.users[seat]
	if u then
		u.push("gameconfig", g._sdk.config)
	end
end

function desk:start()
	local g = self._game
	for _, u in pairs(g.users)do
		if u.android then
			u:attachAI(AI.create(g, u))
		end
	end
	new_game(g)
	self._game = nil
	return g
end

function desk:mygame()
	local g = self._game
	return g
end

function desk:force()
	local g = self._game
	if not g then
		return
	end
	--can't do this a
	--gameend(g)
	g._sync:abandon()

	return g
end

function desk:all_active_bullets()
	local bullets = self._game.roles.bulletActiveStorage
	local t = {}
	for _, mybullet in pairs(bullets) do
		for _, v in ipairs(mybullet) do
			table.insert(t, {
				kind = v.kind,
				id = v.id,
				angle = v.angle,
				timealive = math.floor(skynet.time()) - v.build_tick
			})
		end
	end
end

function desk:all_active_fishes()
	local fishes = self._game.roles.fishActiveStorage
	local t = {}
	for _, v in pairs(fishes) do
		table.insert(t, {
			kind = v.kind,
			id = v.id,
			init_pos = v.init_pos,
			timealive = math.floor(skynet.time()) - v.build_tick
		})
	end
	return t
end



local function setscoresame(g)
	assert(g)
	local msg = {scoreinfo = {}}
	for _, u in pairs(g.users)do
		table.insert(msg.scoreinfo, {seat=u.seat, score=u.game.score})
	end
	g.push("setscoresame", msg)
end

local function calc_fishscore_all(g, meseat, bankerseat, score)
	local banker
	local me
	for _, u in pairs(g.users)do
		if u.seat == bankerseat then
			banker = u
		elseif meseat == u.seat then
		    me = u
		end
	end

	if me and banker then
		adduserscore(me, score)
		adduserscore(banker, -score)
	else
		log.error("[calc_fishscore_all] something wrong, no banker or no me? meseat: %d, bankerseat: %d", meseat, bankerseat)
	end
	setscoresame(g)
end

--game message:
function desk:userfire(user, req)
	local g = self._game
	if user.seat == self.banker then
		log.error("[desk:userfire] banker can't fire, id: %d, banker seat: %d", user.id, self.banker)
		return {err=errmsg.banker_no_fire}
	end

	if not req.bullet_kind then
		return {err = errmsg.invalid_reqparam}
	end

	if user.audience then
		return {err = errmsg.audience_cant_fire}
	end

	local idx = req.bullet_kind + 1
	local bulletcfg = g._sdk.config.bulletcfg[idx]
	assert(bulletcfg, "bullet kind not found in config.")
	local bulletmultiple = bulletcfg.multiple or 1
	assert(bulletmultiple <= g._sdk.config.max_bullet_multiple)
	calc_fishscore_all(g, user.seat, self.banker, -bulletmultiple)

	local bullet = g.roles:ActiveBullet(user.seat)
	local aid = g.androidid
	log.debug("[userfire], user: %d, seat: %d, my score:%d, android?%s, androidid:%s", 
		user.id, user.seat, user.game.score,user.android, aid)

	bullet.kind = req.bullet_kind
	bullet.multiple = bulletmultiple
	bullet.angle = req.angle or 0
	local userfire_bbc = {
		bullet_kind = req.bullet_kind,
		bullet_id = bullet.id,
		seat_id = user.seat,
		android = user.android,
		angle = bullet.angle,
		bullet_multiply = bulletmultiple,
		lock_fishid = req.lock_fishid,
		androidid = user.android and aid or nil,
	}

	self._game.push("userfire_bbc", userfire_bbc)

	return {ok = true}
end

-- audience can delegate android bullet
function desk:catchfish(user, req)
	local g = self._game
	local seat = req.seat_id
	local bullet = g.roles:FreeBullet(req.bullet_id, seat)
	if not bullet then
		bullet = g.roles:FreeBulletOfKind(req.bullet_kind, seat)
	end

	if not bullet or bullet.kind ~= req.bullet_kind then
		log.warning("[catchfish] bullet kind not found in cached, has bullet ? %s, kind: %d", bullet, req.bullet_kind)
		return
	end

	local bulletmultiple = bullet.multiple
	local fish = g.roles:GetFish(req.fish_id)
	if not fish then
		log.debug("[catchfish] no fish id: %d", req.fish_id)
		return
	end

	local fishcfg = g._sdk.config.fishcfg[fish.kind + 1]
	--log.debug("fishcfg kind: %d, fish kind: %d, catch fish id: %d", fishcfg.kind, fish.kind, fish.id)
	assert(fishcfg.kind == fish.kind, "fish kind not found in cfg")

	local fishmultiple = fishcfg.multiple
	if fishcfg.multiplemax then
		fishmultiple = math.random(fishmultiple, fishcfg.multiplemax)
	end

	local fishscore = fishmultiple * bulletmultiple

	local stockcfg = g._sdk.config.stockcfg
	local stockscore = self.get_stock()
	log.debug("current stock score:%d, fish score: %d, bulletmultiply:%d",
		stockscore, fishscore, bulletmultiple)

	local stockscore1 = stockscore + bulletmultiple
	local check_score = stockscore1 - fishscore
	if check_score < 0 and not user.android then
		self.update_stock(bulletmultiple, user)
		log.debug("no stockscore, no one can catch fish.")
		return
	end

	local probability = math.random()
	local fish_probability = fishcfg.probability
	if user.android then
		fish_probability = fish_probability * 1.1
	end
	--(fish_probability * fFishOffSet * (stock_increase_probability_[stock_crucial_count] + 1))
	for _, v in ipairs(stockcfg) do
		if stockscore1 >= v.value then
			fish_probability = fish_probability*(v.prob+1)
			--log.debug("fix fish prob to: %f", fish_probability)
			break
		end
	end
	--log.debug("probability: %f, fish_probability:%f", probability, fish_probability)
	if probability > fish_probability then
		self.update_stock(bulletmultiple, user)
		log.debug("[catchfish] catch no fish, id: %d", req.fish_id)
	--	calc_fishscore_all(user, self.banker, bulletmultiple)
		return
	end
	self.update_stock(bulletmultiple-fishscore, user)
	--特殊鱼类?
	-- if g._sdk.isBombFish(fish.kind) then
	-- 	-- keep cached test.
	-- 	if user.android then
	-- 		user:onevent(def.ACTION_CHANGE_BULLET, true)
	-- 	end
	-- else
		
	-- end
	g.roles:FreeFish(fish.id)
	local catchfish_bbc = {}
	catchfish_bbc.seat_id = seat
	catchfish_bbc.fish_id = fish.id
	catchfish_bbc.fish_kind = fish.kind
	catchfish_bbc.fish_score = fishscore

	if not g._sdk.isBombFish(fish.kind) then
		g.push("catchfish_bbc", catchfish_bbc)
	else
		if user.android then
			user:onevent(def.ACTION_CHANGE_BULLET, true)
		end
		local deleuser = user
	    if user.android then
	    	for _, u in pairs( self.users ) do
	    		if u.id == self.androidid then
	    			deleuser = u
	    			break
	    		end
	    	end
	    end
	    deleuser.push("catchfish_bbc", catchfish_bbc)
	    g.roles:SpecialRecord(fish.id, bulletmultiple)
	end
	
	calc_fishscore_all(g, seat, self.banker, fishscore)
	if g._sdk.isBankerFish(fish.kind) then
		if user.android then
			user:onevent(def.ACTION_CHANGE_BULLET, true)
		end

		local last = self.banker
		self.banker = seat
		g.push("change_banker",
			{seatid=self.banker,candidates={last, seat}, last = last})
	    for _, u in pairs(g.users) do
	        if u.android then
	            u:onevent(def.ACTION_BANKER, true, self.banker)
			end
		end
	end
end

function desk:catchsweepfish(user, req)
	local g = self._game
	local seat = req.seat_id

	local sweepFish = g.roles:GetFish(req.fish_id)
	if not sweepFish then
		log.warning("[catchsweepfish] sweep fish id %d not find.", req.fish_id)
		return
	end

	if not g._sdk.isBombFish(sweepFish.kind) then
		log.warning("[catchsweepfish] not a bomb fish kind:%d", sweepFish.kind)
		return
	end

	local fishcfg = g._sdk.config.fishcfg
	local fish_score = 0
	local fishinfo
	local bulletmultiply = g.roles:SpecialPop(req.fish_id)
	for _, v in ipairs(req.catch_fish_ids) do
		fishinfo = g.roles:FreeFish(v)
		if fishinfo then
			local cfg = fishcfg[fishinfo.kind + 1]
			--assert(cfg.kind == fishinfo.kind, "[catchsweepfish] fish kind not found in cfg")
			if cfg then
				fish_score = fish_score + cfg.multiple * bulletmultiply
			else
				log.warning("[catchsweepfish] fishcfg for kind %d not find.", fishinfo.kind)
			end
		else
			log.warning("[catchsweepfish] one of fish %d not find.", v)
		end
	end
	self.update_stock(fish_score, user)
	local catchsweepfish_bbc = {}
	catchsweepfish_bbc.seat_id = seat
	catchsweepfish_bbc.fish_id = req.fish_id
	catchsweepfish_bbc.fish_score = fish_score
	catchsweepfish_bbc.catch_fish_ids = req.catch_fish_ids
	g.push("catchsweepfish_bbc", catchsweepfish_bbc)
	calc_fishscore_all(g, seat, self.banker, fish_score)
end

return desk