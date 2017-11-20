local skynet = require "skynet"
local os_date = os.date
local str_format = string.format
local m_ceil = math.ceil
local m_floor = math.floor

local utils = {DAY = 86400, WEEK = 7*86400}

local function get_date(diff)
    local now = math.floor(skynet.time()) - (diff or 0)
    return os_date("*t", now)
end

--  0 <= index <= 23 
function utils.get_hour_guid(index)
    local d = get_date()
    local hour = index or d.hour 
    if hour < 0 then hour = 0 end
    if hour > 23 then hour = 23 end
    return str_format("%d%02d%02d:%02d", d.year, d.month, d.day, hour)
end

-- diff <= 0
function utils.get_day_guid(diff)
    local d = get_date((diff or 0)*utils.DAY)
    return str_format("%d%02d%02d", d.year, d.month, d.day)
end

-- diff <= 0
function utils.get_week_guid(diff)
    local d = get_date((diff or 0)*utils.WEEK)
    local week = m_ceil(d.yday/7) 
    return str_format("%dW%02d", d.year, week)
end

function utils.get_month_guid()
    local d = get_date(diff)
    return str_format("%d%02d", d.year, d.month)
end

function utils.diff_days(t1, t2)
    if t1 > t2 then
        t1, t2 = t2, t1
    elseif t1 == t2 then
        return 0
    end
    local dt1 = t1 - (t1 % utils.DAY)
    local dt2 = t2 - (t2 % utils.DAY)
    return m_floor((dt2 - dt1) / utils.DAY)
end

local function decode_func(c)
    return string.char(tonumber(c, 16))
end

local function decode(str)
    local str = str:gsub('+', ' ')
    return str:gsub("%%(..)", decode_func)
end

function utils.trim(s)
    return string.gsub(s, "%s*(.+)%s*", "%1")
end

function utils.split(szFullString, szSeparator)
    local nFindStartIndex = 1
    local nSplitIndex = 1
    local nSplitArray = {}
    while true do
       local nFindLastIndex = string.find(szFullString, szSeparator, nFindStartIndex)
       if not nFindLastIndex then
        nSplitArray[nSplitIndex] = utils.trim(string.sub(szFullString, nFindStartIndex, string.len(szFullString)))
        break
       end
       nSplitArray[nSplitIndex] = utils.trim(string.sub(szFullString, nFindStartIndex, nFindLastIndex - 1))
       nFindStartIndex = nFindLastIndex + string.len(szSeparator)
       nSplitIndex = nSplitIndex + 1
    end
    return nSplitArray
end

function utils.parseUrl(url)
    local t1
    t1= utils.split(url,',')
    t1=utils.split(t1[1],'?')
    t1 = #t1 > 1 and t1[2] or t1[1]
    t1=utils.split(t1,'&')
    local res = {}
    for i, v in ipairs(t1) do
        t1 = utils.split(v,'=')
        if #t1 > 1 then
            res[decode(t1[1])]=decode(t1[2])
       --     res[i] = decode(t1[2])
        else
            res[i] = decode(t1[1])
        end
    end
    return res
end

return utils

