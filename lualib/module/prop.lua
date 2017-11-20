local service = require "common.service"
local log = require "common.log"
local em = require "def.errmsg"

local str_format = string.format 
local tbl_remove = table.remove

local mod = {}

local props
local userdb

function mod.init(s)
    userdb = assert(service.userdb)
    assert(next(s))
    props = s
end

function mod.bag(userid)
    local bag = userdb.get_user_bag(userid)
    if bag then
        for i=#bag, 1, -1 do
            local p = props[bag[i].id]
            if p == nil or p.close or p.X then
                tbl_remove(bag, i)
            end
        end
    end
    return bag
end

function mod.check(userid, propid, n)
    local has = userdb.get_user_prop(userid, propid)

    return has >= n
end

function mod.add(from, userid, id, num, detail)
    local p = props[id]
    if p then
        if p.record and p.record.get then
            userdb.add_record(userid, p.record.get, num)
        end
        -- add history
        return userdb.add_prop(userid, id, num)
    else
        log.error("add unknown prop %s", id)
    end
end

function mod.use(from, userid, id, num, detail)
    local p = props[id]
    if p then
        log.debug("use prop from: %s, user: %d, prop: %s, num: %s", from, userid, id, num)
        local left = userdb.use_prop(userid, id, num)
        if left and left >= 0 then
            -- add history
            if p.record and p.record.use then
                userdb.add_record(userid, p.record.use, num)
            end
        end
        return left
    else
        log.error("use unknown prop %s", id)
    end
end

function mod.madd(from, userid, m, detail)
    local s = {}
    for id, n in pairs(m) do
        local p = props[id]
        if p then
            s[id] = n
        else
            log.error("unknown prop %s", id)
        end
    end
    if next(s) then
        -- add history
        local ret = userdb.add_props(userid, s)
        for id, n in pairs(ret) do
            local p = props[id]
            if p and p.record and p.record.get then
                userdb.add_record(userid, p.record.get, s[id])
            end
        end
        return ret
    end
end

function mod.muse(from, userid, m, detail)
    local s = {}
    for id, n in pairs(m) do
        local p = props[id]
        if p then
            s[id] = n
        else
            log.error("unknown prop %s", id)
        end
    end
    if next(s) then
    end
end

function mod.name(id, num)
    local p = props[id]
    if p then
        if num then
            return str_format("%d%s%s", num, p.unit or "", p.name)
        else
            return p.name
        end
    end
end

local lack_err = em.prop_lack
function mod.error(id)
    local p = props[id]
    if p then
        return {
            prop = id,
            code = lack_err.code,
            msg = str_format(lack_err.msg, p.name),
        }
    end
    return em.prop_noexists
end

return mod

