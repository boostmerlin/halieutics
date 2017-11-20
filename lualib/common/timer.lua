local skynet = require "skynet"
local table = table
local math = math

local timer = {}

local tmr_id = 0
local tmr_queue = {}
local tmr_map = {}

local HEARTBEAT = 20

local function timer_update()
    local now = math.floor(skynet.time())
    while true do
        local tmr = tmr_queue[1]
        if tmr == nil then break end
        if not tmr.cancel then
            if now >= tmr.expire then
                tmr_map[tmr.id] = nil
                table.remove(tmr_queue, 1)
                tmr.func()
                if tmr.repeated then
                    tmr.expire = math.floor(skynet.time()) + tmr.timeout
                    timer.inneradd(tmr)
                end
            else
                break
            end
        else
            tmr_map[tmr.id] = nil
            table.remove(tmr_queue, 1)
        end
    end

    if #tmr_queue > 0 then
        skynet.timeout(HEARTBEAT, timer_update)
    end
end

function timer.get(tid)
    local tmr = tmr_map[tid]
    return tmr
end

function timer.inneradd(tmr)
    local idx
    for i, t in ipairs(tmr_queue) do
        if tmr.expire < t.expire then
            idx = i
            break
        end
    end
    idx = idx or (#tmr_queue + 1)
    table.insert(tmr_queue, idx, tmr) 
    tmr_map[tmr.id] = tmr
    if #tmr_queue == 1 then
        skynet.timeout(HEARTBEAT, timer_update)
    end
    return tmr.id
end

function timer.add(timeout, f, ...)
    tmr_id = tmr_id + 1

    local args = table.pack(...)
    local tmr = {
        id = tmr_id,
        expire = math.floor(skynet.time()) + timeout,
        timeout = timeout,
        func = function()
            f(table.unpack(args, 1, args.n))
        end
    }

    return timer.inneradd(tmr)
end

function timer.remove(tid)
    local tmr = tmr_map[tid]
    if tmr then
        tmr.cancel = true
    end
end

return timer


