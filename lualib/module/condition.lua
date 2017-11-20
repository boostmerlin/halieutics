local service = require "common.service"

local tbl_insert = table.insert

local function fetch_hour(token)
    local st, et = token:match "(%d+):%d+-(%d+):%d+"
    st = tonumber(st)
    et = tonumber(et)
    assert(st ~= et)
    local buf = {}
    if et > st then 
        for i=st, et-1 do
            tbl_insert(buf, i)
        end
    else 
        for i=st, 23 do
            tbl_insert(buf, i)
        end
        for i=0, et-1 do
            tbl_insert(buf, i)
        end
    end
    return buf
end

local function check_cond(userid, cond)
    local r
    if cond.cycle == "hour" then
        local hours = fetch_hour(cond.time)
        r = 0
        for _, h in ipairs(hours) do
            local hr = service.userdb.get_record(userid, cond.record, cond.cycle, h)
            r = r + hr 
        end
    else
        r = service.userdb.get_record(userid, cond.record, cond.cycle)
    end
    return r >= (cond.value or 1), r
end

return check_cond
