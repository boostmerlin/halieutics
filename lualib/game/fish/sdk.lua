local def = require "game.fish.def"
local log = require "common.log"
local skynet = require "skynet"
local cjson = require "cjson"

local sdk = {}

local roles = {}

sdk.roles = roles

local dolog = false

local FISH_EXPIRE_TIME = 60
local BULLET_EXPIRE_TIME = 20

local function time()
	return math.floor(skynet.time())
end

local function init_obj(obj, id)
	obj.kind = -1
	obj.id = id
	obj.build_tick = time()
end

local function new_fish(id)
	local fish = {}
	init_obj(fish, id)
	--pos.
	return fish
end

local function new_bullet(id)
	local bullet = {}
	init_obj(bullet, id)

	bullet.multiple = 1

	return bullet
end

function roles.create()
	local rm = setmetatable({}, {__index=roles})
	rm.fishActiveStorage = {}
	rm.fishFreeStorage = {}
	rm.bulletActiveStorage = {}
	rm.bulletFreeStorage = {}
	rm.fish_id_gen = 0
	rm.bullet_id_gen = 0
	rm.specialFish = {} --fish id mapto multiple

	return rm
end

local function active(tbactive, tbfree, f, id)
	if #tbfree > 0 then
		local obj = table.remove(tbfree)
		init_obj(obj, id)
		tbactive[id] = obj
		--log.debug("[active] obj from FreeStorage info: %s, id:%d", cjson.encode(obj), id)

		return obj
	end

	local info = f(id)

	tbactive[id] = info
	--log.debug("[active] obj from new info: %s, id:%d", cjson.encode(info), id)

	return info
end

local function free(tbactive, tbfree, id)
	local info = tbactive[id]
	if not info then
		log.warning("[roles.free] %d not in active storage", id)
		return
	end
	tbactive[id] = nil
	table.insert(tbfree, info)

	return info
end

local function upate(tbactive, tbfree, expire)
	local now = time()
	for id, v in pairs(tbactive) do
		if v.build_tick + expire <= now then
		--	log.debug("-----xx-[sdk] fish expire: %d, currenttick: %d, %s", expire,now, cjson.encode(v))
			table.insert(tbfree, v)
			tbactive[id] = nil
		end
	end
end

local function getn(tbactive)
	local n = 0
	for _ , _ in pairs(tbactive) do
		n = n + 1
	end

	return n
end

function roles:Update()
	upate(self.fishActiveStorage, self.fishFreeStorage, FISH_EXPIRE_TIME)
	--upate(self.bulletActiveStorage, self.bulletFreeStorage, BULLET_EXPIRE_TIME)
	local now = time()
	local n = 0
	for _, mybullet in pairs(self.bulletActiveStorage) do
		local i = 1
		while i <= #mybullet do
			local v = mybullet[i]
			if v.build_tick + BULLET_EXPIRE_TIME <= now then
				table.insert(self.bulletFreeStorage, v)
			--	log.debug("-----------[sdk] bullet expire: %s, freen: %d", cjson.encode(v), #self.bulletFreeStorage)
				table.remove(mybullet, i)
			else
				i = i + 1	
				n = n + 1
			end
		end
	end
	if dolog then
		log.debug("fishActiveStorage: %d, bulletActiveStorage: %d", getn(self.fishActiveStorage), n)
	end
end

function roles:SpecialRecord(id, multiple)
	self.specialFish[id] = multiple
end

function roles:SpecialPop(id)
	local multiple = self.specialFish[id]
	self.specialFish[id] = nil
	return multiple
end

function roles:FreeAll()
	self.fishActiveStorage = {}
	self.fishFreeStorage = {}
	self.bulletActiveStorage = {}
	self.bulletFreeStorage = {}
end

function roles:ActiveFish()
	self.fish_id_gen = self.fish_id_gen + 1
	return active(self.fishActiveStorage, self.fishFreeStorage, new_fish, self.fish_id_gen)
end

function roles:FreeFish(fid)
	local obj = free(self.fishActiveStorage, self.fishFreeStorage, fid)
	--log.debug("FreeFish: %s", cjson.encode(obj))
	return obj
end

function roles:ActiveBullet(seat)
	self.bullet_id_gen = self.bullet_id_gen + 1
	local obj
	if #self.bulletFreeStorage > 0 then
		obj = table.remove(self.bulletFreeStorage)

		init_obj(obj, self.bullet_id_gen)
		--log.debug("[ActiveBullet] from free storage: %d", self.bullet_id_gen)
	else
		--log.debug("[ActiveBullet] from new: %d", self.bullet_id_gen)
		obj = new_bullet(self.bullet_id_gen)
	end

	local mybullet = self.bulletActiveStorage[seat]
	if not mybullet then
		mybullet = {}
		self.bulletActiveStorage[seat] = mybullet
	end
	table.insert(mybullet, obj)
	--log.debug("[activebullet] seat: %d, info: %s, idgen:%d", seat, cjson.encode(obj), self.bullet_id_gen)

	return obj
end

function roles:FreeBullet(bid, seat)
	local mybullet = self.bulletActiveStorage[seat]
	if not mybullet then
		log.warning("[FreeBullet] no such seat: %d", seat)
		return
	end

	for i, v in ipairs(mybullet) do
		if v.id == bid then
			table.remove(mybullet, i)
			table.insert(self.bulletFreeStorage, v)
			--log.debug("FreeBullet on seat: %d,  %s",seat, cjson.encode(v))
			return v
		end
	end
end

function roles:FreeBulletOfKind(kind, seat)
	local mybullet = self.bulletActiveStorage[seat]
	if not mybullet then
		log.warning("[FreeBulletOfKind] no such seat: %d", seat)
		return
	end

	for i, v in ipairs(mybullet) do
		if v.kind == kind then
			table.remove(mybullet, i)
			table.insert(self.bulletFreeStorage, v)
			--log.debug("FreeBulletOfKind on seat: %d,  %s", seat, cjson.encode(v))

			return v
		end
	end
end

function roles:GetFish(fid)
	return self.fishActiveStorage[fid]
end

function roles:GetBullet(bid)
	return self.bulletActiveStorage[bid]
end


local rand = function ()
	return math.random(1, 0x7ffffff)
end

local srand = math.randomseed

function sdk.buildinittrace(init_count, fish_kind, trace_type)
	--assert(init_count >= 2 and init_count <= 3);
	local chair_id = rand() % def.maxplayer + 1;
	local rw = def.kResolutionWidth
	local rh = def.kResolutionHeight
	local center_x = rw / 2;
	local center_y = rh / 2;
	local factor = rand() % 2 == 0 and 1 or -1;

	local init_pos = {}
	table.insert(init_pos, {})
	table.insert(init_pos, {})
	table.insert(init_pos, {})

	local cfg = assert(sdk.config.fishcfg)

	local index = fish_kind + 1
	if chair_id == 3 then
		init_pos[1].x = rw + cfg[index].bbox_w * 2
		init_pos[1].y = center_y + factor * (rand() % center_y)
		init_pos[2].x = (center_x - (rand() % center_x))
		init_pos[2].y = (center_y + factor* (rand() % center_y))
		init_pos[3].x = -(cfg[index].bbox_w * 2)
		init_pos[3].y = (center_y - factor* (rand() % center_y))
	elseif chair_id == 4 or chair_id == 5 then
		init_pos[1].x = (center_x + factor * (rand() % center_x))
		init_pos[1].y = rh + (cfg[index].bbox_h * 2)
		init_pos[2].x = (center_x + factor * (rand() % center_x))
		init_pos[2].y = (center_y - (rand() % center_y))
		init_pos[3].x = (center_x - factor * (rand() % center_x))
		init_pos[3].y = (-cfg[index].bbox_h * 2)
	elseif chair_id == 6 then
		init_pos[1].x = (-cfg[index].bbox_w * 2);
		init_pos[1].y = (center_y + factor* (rand() % center_y));
		init_pos[2].x = (center_x + (rand() % center_x));
		init_pos[2].y = (center_y + factor* (rand() % center_y));
		init_pos[3].x = (rw + cfg[index].bbox_w * 2);
		init_pos[3].y = (center_y - factor* (rand() % center_y));
	else --1, 2
		init_pos[1].x = (center_x + factor * (rand() % center_x))
		init_pos[1].y = 0 - (cfg[index].bbox_h) * 2
		init_pos[2].x = (center_x + factor * (rand() % center_x))
		init_pos[2].y = (center_y + (rand() % center_y))
		init_pos[3].x = (center_x - factor * (rand() % center_x))
		init_pos[3].y = (rh + cfg[index].bbox_h * 2)
	end

	if trace_type == def.TRACE_LINEAR and init_count == 2 then
		init_pos[2].x = init_pos[3].x;
		init_pos[2].y = init_pos[3].y;
	end

	return init_pos
end

function sdk.buildfishtrace(g, fish_count, fish_kind_start, fish_kind_end)
	if dolog then
		log.debug("[sdk.buildfishtrace], fish_count:%d, start:%d, end:%d", fish_count, fish_kind_start, fish_kind_end)
	end
	local traces_info = {}
	local rm = g.roles

	local time = time()
	for i=1, fish_count do
		local fish = rm:ActiveFish()
		fish.kind = math.random(fish_kind_start, fish_kind_end)
		local randomseed = ((i*fish.id) * math.random(7, 2342)) * 0xf2314a + time
		if dolog then
			log.debug("[sdk.buildfishtrace] randomseed:%d", randomseed)
		end
		srand(randomseed);
		local fishtrace_bbc = {}
		fishtrace_bbc.fish_id = fish.id
		fishtrace_bbc.fish_kind = fish.kind

		if fish.kind == def.FISH_KIND_1 or fish.kind == def.FISH_KIND_2 then
			fishtrace_bbc.init_count = 2
			fishtrace_bbc.trace_type = def.TRACE_LINEAR
		else
			fishtrace_bbc.init_count = 3
			fishtrace_bbc.trace_type = def.TRACE_BEZIER
		end
		if dolog then
    		log.debug("[sdk.buildfishtrace] of fish_kind: %d, index: %d", fish.kind, i)
    	end

		fishtrace_bbc.init_pos = sdk.buildinittrace(fishtrace_bbc.init_count, fishtrace_bbc.fish_kind, fishtrace_bbc.trace_type);
		fish.init_pos = fishtrace_bbc.init_pos
		table.insert(traces_info, fishtrace_bbc)
	end

	return traces_info
end

function sdk.isBombFish(kind)
	if kind == def.FISH_KIND_24 then
		return true
	end
end

function sdk.isBankerFish(kind)
	return kind == def.FISH_KIND_23
end

function sdk.isFishKing(kind)
	if kind >= def.FISH_KIND_30 or kind <= def.FISH_KIND_40 then
		return true
	end
end

return sdk