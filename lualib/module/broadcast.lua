local skynet = require "skynet"
local mc = require "skynet.multicast"
local sharedata = require "skynet.sharedata"
local em = require "def.errmsg"
local log = require "common.log"

local str_format = string.format
local tbl_insert = table.insert
local tbl_remove = table.remove
local co_running = coroutine.running

local M = {name = "broadcast"}

local MAX_QUEUE_SIZE = 10
local NOTICE_RESERVED = 5

local channel
local msg_queue = {}
local wait_response = {}
local broadcast_id = 0
local S

function M.init(app, s)
    local ch = sharedata.query("ch:broadcast:" .. app) 
    if ch then
        S = s
        channel = mc.new {
            channel = ch.channel, 
            dispatch = function(channel, source, msg, cmd)
                if cmd and cmd == "rem" then
                    for i= #msg_queue, 1, -1  do
                        if msg_queue[i].id == msg then
                            table.remove(msg_queue, i)
                            break
                        end
                    end
                else
                    tbl_insert(msg_queue, 1, msg)
                    while #msg_queue > MAX_QUEUE_SIZE do
                        local n = 0
                        for i= #msg_queue, 1, -1  do
                            if msg_queue[i].type == 1 then -- notice
                                n = n + 1
                                if n > NOTICE_RESERVED then
                                    j = i
                                    while j < #msg_queue do
                                        tbl_remove(msg_queue)
                                        j = j + 1
                                    end
                                    break
                                end
                            else
                                tbl_remove(msg_queue, i)
                                break
                            end
                        end
                    end
                    log.debug("braodcast:new %d", msg.bid)
                    local message = {lastid = msg.bid, items = {msg}}
                    for co, st in pairs(wait_response) do
                        if st == "WAIT" then
                            wait_response[co] = message
                            skynet.wakeup(co)
                        end
                    end
                end
            end
        }
        channel:subscribe()
    end
    log.debug("channel:broadcast:%s %s", app, ch and "open" or "close")
end

local empty_notice = {lastid = 0}
function M.pull(bid)
    if channel == nil then
        return
    end
    local q = {}
    for _,  m in ipairs(msg_queue) do
        if m.bid ~= bid then
            tbl_insert(q, m)
        else
            break
        end
    end
    if #q == 0 then
        local co = co_running()
        wait_response[co] = "WAIT" 
        skynet.wait()
        return wait_response[co] or empty_notice 
    else
        return {items = q, lastid = q[1].bid} 
    end
end

function M.notice(text)
    if channel == nil then
        return
    end
    broadcast_id = broadcast_id + 1
    channel:publish {
        bid = broadcast_id,
        content = str_format("%s", text),
        color = S.system.color,
        time = 10,
        type = 2
    }
    log.debug("broadcast:pub %d, %s", broadcast_id, text)
end

function M.remove(id)
    if channel == nil then
        return
    end
    channel:publish(id, "rem")
end

function M.noticeitem(item)
    if channel == nil then
        return
    end

    if item.expire and skynet.time() > item.expire then
        return
    end

    broadcast_id = broadcast_id + 1
    channel:publish {
        bid = broadcast_id,
        id= item.id,
        content = str_format("%s", item.content),
        color = item.color or S.system.color,
        time = item.time or 10,
        type = item.type or 1,
    }
    log.debug("broadcast:pub %d", broadcast_id)
end

function M.smallhorn(userid, text)
    if channel == nil then
        return false, em.cant_horn
    end
    broadcast_id = broadcast_id + 1
    channel:publish {
        bid = broadcast_id,
        content = str_format("［%s］%s", S.smallhorn.sign, text),
        color = S.smallhorn.color,
    }
    log.debug("broadcast:horn %d", broadcast_id)
end

function M.close()
    if channel then
        channel:unsubscribe()
    end
end

return M

