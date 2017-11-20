local service = require "common.service"
local log = require "common.log"
local prop = require "module.prop"
local em = require "def.errmsg"

local tbl_insert = table.insert
local str_format = string.format

local mod = {name = "invite"}

local userdb
--local bossdb
local invite_info

function mod.init(s)
    userdb = assert(service.userdb)
  --  bossdb = assert(service.bossdb)
    invite_info = s
end

function mod.bind(userid, recode)
    if string.len(recode) ~= 5 then
        return false, em.invalid_recode
    end

    -- local ok = bossdb.bind(recode, userid)
    local ok -- invoke pmp interface
    if ok or true then
        userdb.invite_bind(userid, recode)
        userdb.add_record(userid, "b:recode")
        local r = prop.madd("invite:bind", userid, invite_info.bind)
        local list = {}
        for id, n in pairs(r) do
            tbl_insert(list, {prop = id, num = n})
        end
        return true, list
    else
        log.error("invalid recode or rebind : %s", recode)
        return false, em.invalid_recode
    end
end

return mod

