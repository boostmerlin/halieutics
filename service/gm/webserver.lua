local skynet = require "skynet"
local socket = require "skynet.socket"
local string = require "string"
local httpd = require "http.httpd"
local sockethelper = require "http.sockethelper"
local service = require "common.service"
local log = require "common.log"
local cjson = require "cjson"

local handler = {}
function handler.open(conf)
    --no config yet
end

local function handle_socket(id, host)
    -- limit request body size to 8192
    local code, url, method, header, body = httpd.read_request(sockethelper.readfunc(id), 8192)
    if not code or not url or not method then
        log.debug("unknown request form host: %s", host)
        sockethelper.close(id)
        return
    end

    if method ~= "GET" and method ~= "POST" then
        log.debug("unknown request form host: %s, method: %s", host, method)
        sockethelper.close(id)
        return
    end

    if url:match("/favicon.ico") then
        log.debug("~~~~~skip favicon.")
        sockethelper.close(id)
        return
    end

    log.debug("http raw data\n code: %d\n url: %s\n method:%s\n from host: %s\n", code, url, method, host)
    local t = {}
    for k, v in pairs(header) do
        table.insert(t, string.format("%s: %s\n", k, v))
    end
    log.debug("Header:\n%s", table.concat(t))

    local ret, status, respheader = service.gm.http(url, method, header, body)
    ret = ret or "OK"
    if true or type(ret) == "table" then
        ret = cjson.encode(ret)
    end
    if not respheader then
        respheader = {}
    end
    respheader["Content-Type"] = "application/json;charset=utf-8"
 --   end
    status = status or 200
    log.debug("[webserver] response: %s, status: %d", ret, status)
    httpd.write_response(sockethelper.writefunc(id), status, ret, respheader)
    sockethelper.close(id)
end

service.init{
    command = handler,
    require = {
        "gm"
    },
    init = function ()
        local address = "0.0.0.0:8081"
        log.debug("web server listen on: %s", address)
        local fd = assert(socket.listen(address))
        socket.start(fd , function(id, addr)
            socket.start(id)
            local host, _ = string.match(addr, "([^:]+):(.+)$")
            pcall(handle_socket, id, host)
        end)

    end
}
