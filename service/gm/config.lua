local skynet = require "skynet"
local service = require "common.service"
local timer = require "common.timer"
local log = require "common.log"
local sharedata = require "skynet.sharedata"
local cfgmod = require "module.sharedmod"
local cjson = require "cjson"
local broadcast = require "module.broadcast"

local data = {notice = {}, cli_notice = {}}
local CMD = {}

data.app = "fish" --!

local shopcfg
local noticecfg
local playcfg

local appconfig

local noticecache
local max_notice_id = 0

local shopcache
local diamondshopcache

local shareinfocache

local playcache

local MAX_NOTICE_EXPIRE = 25920000 --ten month

local function notice_monitor(buffer)
    local notice = buffer[1]
    if notice then
        local now = math.floor(skynet.time())
        if now >= notice.expire then
            CMD.noticedel(notice.id)
        end
        if #buffer > 0 then
            timer.add(buffer[1].expire - now, notice_monitor, buffer)
        end
    end
end

local function init_notice()
    local now = math.floor(skynet.time())
    noticecache = noticecfg:list()
    if not noticecache then
        noticecache = {}
        return
    end
        for _, v in ipairs(noticecache) do
        if v.id > max_notice_id then
            max_notice_id = v.id
        end
        if v.expire == nil then
            v.expire = math.floor(skynet.time()) + MAX_NOTICE_EXPIRE
        end
    end
    if noticecache and #noticecache > 0 then
        table.sort(noticecache, function(a, b) return a.expire < b.expire end)
        timer.add(noticecache[1].expire - now, notice_monitor, noticecache)
        log.debug("CMD notice id: %s, expire: %d NOW:%d", noticecache[1].id, noticecache[1].expire, now)
    end
end

local function update(mod, cfgname, value)
    sharedata.update(mod..":"..cfgname, value)
end

local function writecfg(mod, cfgname, contentstable)
    update(mod, cfgname, contentstable)

    local gcp = skynet.getenv "game_config_path"
    local cfgfile = appconfig[mod][cfgname]
    local file = string.format("%s/%s", gcp, cfgfile)
    local f = assert(io.open(file, "w+"), "Can't open " .. file)
    f:write(cjson.encode(contentstable))
    f:close()
end

function CMD.noticeadd(content, time, tp, expire)
    if not content then
        log.error("[gm.config] notice must have content.")
        return
    end
    max_notice_id = max_notice_id + 1
    local item = {}
    item.id = max_notice_id
    item.time = time and tonumber(time) or 5
    item.type = tp and tonumber(tp) or 1 --system notice
    item.expire = expire and tonumber(expire) or (math.floor(skynet.time()) + MAX_NOTICE_EXPIRE) --2592000
    item.content = content

    for i=#noticecache, 0, -1 do
        local v = noticecache[i]
        if v == nil or item.expire > v.expire then
            table.insert(noticecache, i+1, item)
            break
        end
    end
    if #noticecache > 0 then
        local now = math.floor(skynet.time())
        timer.add(noticecache[1].expire - now, notice_monitor, noticecache)
    end

    --write back to config.
    writecfg("notice", "system", noticecache)

    broadcast.noticeitem(item)
end

function CMD.noticedel(id)
    local found = false
    id = tonumber(id)
    for i, v in ipairs(noticecache) do
        if v.id == id then
            log.debug("[notice_monitor] remove notice %d", v.id)
            found = true
            table.remove(noticecache, i)
            broadcast.remove(id)
            break
        end
    end
    if found then
        writecfg("notice", "system", noticecache)
    else
        return {err="notice not found, id: " .. id}
    end
end

function CMD.noticegets()
    assert(noticecache, "??? noticecache nil")
    return noticecache
end

function CMD.noticeget(id)
    id = tonumber(id)
    for _, v in ipairs(noticecache) do
        if v.id == id then
            return v
        end
    end
    return {err="notice not found"}
end

function CMD.shareinfoset(stitle, scontent, surl, ititle, icontent, iurl)
    if stitle then
        shareinfocache.stitle = stitle
    end
        if scontent then
        shareinfocache.scontent = scontent
    end
        if surl then
        shareinfocache.surl = surl
    end
        if ititle then
        shareinfocache.ititle = ititle
    end
        if icontent then
        shareinfocache.icontent = icontent
    end
        if iurl then
        shareinfocache.iurl = iurl
    end
    writecfg("notice", "share", shareinfocache)
end

function CMD.shareinfoget()
    return shareinfocache
end

--shop don't go here now. 2017.10.12
function CMD.shopadd(id, prop, num, price)
    assert(id and prop and num and price)
    
    if prop ~= "diamond" then
        log.error("[gm.shopadd] unknown prop")
        return {err="prop is not diamond"}
    end
    local item = {id = id, prop=prop, num=tonumber(num), price=tonumber( price )}
    table.insert(diamondshopcache, item)
    writecfg("shop", "diamond", shopcache)
end

function CMD.shopdel(id)
    for i, v in ipairs(diamondshopcache) do
        if v.id == id then
            table.remove(diamondshopcache, i)
            break
        end
    end
    writecfg("shop", "diamond", shopcache)
end

function CMD.shopgets()
    assert(diamondshopcache, "??? diamondshopcache nil")
    return diamondshopcache
end

function CMD.shopget(id)
    for i, v in ipairs(diamondshopcache) do
        if v.id == id then
            return v
        end
    end
end

--key:
--probability
--elapsed
--count
--countMax
local valid_keys = {"probability", "count", "countMax", "elapsed"}
function CMD.gamefish(kind, key, nv)
    local found = false
    for _, v in ipairs( valid_keys ) do
        if v == key then
            found = true
            break
        end
    end
    if not found then
        return {err="key should be one of {probability, count, countMax, elapsed}"}
    end

    local paramtype = type(kind)
    assert(paramtype == type(nv), "params type error.")
    local fishes = playcache["Fish"]

    if paramtype == "table" then
        assert(#kind == #nv, "params len error.")

        for k, v in pairs(kind) do
            kind[k] = tonumber(v)
        end

        for k, v in pairs(nv) do
            nv[k] = tonumber(v)
        end

        for _, v in ipairs(fishes) do
            local k = v["kind"]
            for i, vv in ipairs(kind) do
                if vv == k then
                    v[key] = nv[i]
              --      table.remove(kind, i)
                    log.debug("[gm.gamefish] group modify playcfg kind: %d, %s:%d", k, key, nv[i])

                    break
                end
            end
        end
    else
        kind = tonumber(kind)
        for _, v in ipairs(fishes) do
            if v["kind"] == kind then
                v[key] = tonumber(nv)
                log.debug("[gm.gamefish] modify playcfg kind: %d, %s:%d", kind, key, nv)
                break
            end
        end
    end

    writecfg("gameplay", "play", playcache)
end

function CMD.playcfg()
    local fishes = playcache["Fish"]
    return fishes
end

function CMD.stockcfg()
    local stocks = playcache["Stock"]
    return stocks
end

function CMD.stockthreshold(value, prob)
    assert(value)
    local stocks = playcache["Stock"]
    local nvalue = tonumber(value)
    for i, v in ipairs(stocks) do
        if v.value == nvalue then
            if not prob then
                table.remove(stocks, i)
                writecfg("gameplay", "play", playcache)
                return "remove"
            else
                v.prob = tonumber(prob)
                writecfg("gameplay", "play", playcache)
                return "update"
            end
        end
    end
    if prob then
        local nprob=tonumber(prob)
        table.insert(stocks, {value=nvalue, prob=nprob})
        writecfg("gameplay", "play", playcache)
        return "new"
    else
        return "unknown"
    end
end

service.init {
    command = CMD,
    info = data,
 --   require = {"gmdb"},
    init = function()
     --  shopcfg = cfgmod.init("shop", "diamond")
     --   shopcache = shopcfg:list()
     --   diamondshopcache = shopcache["diamond"]
        noticecfg = cfgmod.init("notice", "system")

        init_notice()
        shareinfocache = cfgmod.listconfig("notice", "share")

        log.debug("[gm.config] max notice id: %d", max_notice_id)
        playcfg = cfgmod.init("gameplay", "play")
        playcache = playcfg:list()
        appconfig = sharedata.deepcopy("appconfig."..data.app)

        broadcast.init(data.app, appconfig.broadcast)
    end,
}

