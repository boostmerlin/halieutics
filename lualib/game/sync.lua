local skynet = require "skynet"
local log = require "common.log"

local coroutine = coroutine

local sync = {}

function sync.new(maxwait)
    return setmetatable({__maxwait = maxwait}, {__index = sync})
end

local driver_ot = {driver = "overtime"}

--ud true to add, false to remove
function sync:add(seat, ud)
    self.__users = self.__users or {count = 0, counter = 0}

    if self.__users[seat] then
        if not ud then
            self.__users[seat] = false
            self.__users.count = self.__users.count - 1
        end
    else
        if ud then
            self.__users[seat] = ud
            self.__users.count = self.__users.count + 1
        end
    end
end

local function def_users_mf(t, k)
    t[k] = true
    return t[k]
end

function sync:wait(st, time)
    assert(self.__wait == nil, string.format("already has a wait %s(%s)", self.__wait, st))
    self.__wait = st
    self.__co = coroutine.running()
   -- self.__users = self.__users or setmetatable({count = self.__maxwait, counter = 0}, {__index = def_users_mf}) 
    self.__driver = "timeout"
    if time then
        skynet.sleep(time * 100)
    else
        skynet.wait()
    end
    if self.__driver == "break" then
        self.__wait = nil
        error(self.__ud, 0)    -- raise a error skip logic, set level = 0 for capture error message
    end
    if self.__driver == "timeout" then
        self.__wait = nil
       -- self.__users = nil
    end
    return {driver = self.__driver, ud = self.__ud}
end

function sync:getusers()
    if self.__wait then
        return self.__users
    end
end

function sync:getstatus()
    return self.__wait
end

function sync:wakeup(st, ud)
    if self.__wait == st then
        self.__wait = nil
        self.__driver = "message"
        self.__ud = ud
        self.__users.counter = 0
        skynet.wakeup(self.__co)
    end
end

function sync:raise(ud)
    error(ud, 0)
end

function sync:abandon()
    if self.__wait then
        self.__wait = nil
        self.__users = nil
        self.__driver = "abandon"
        self.__ud = nil
        skynet.wakeup(self.__co)
    end
end

function sync:arrive(st, seat)
    if self.__wait == st then
        local ud = self.__users[seat]
        if ud then
            self.__users.counter = self.__users.counter + 1
        log.debug("-----sync:arrive, __wait: %s, st: %s, counter: %d, count: %d", self.__wait, st, self.__users.counter, self.__users.count)
            if self.__users.count == self.__users.counter then
                self.__users.counter = 0
                self:wakeup(st)
            end
            return ud
        end
    end
end

return sync

