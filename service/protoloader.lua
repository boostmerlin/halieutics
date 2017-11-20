local skynet = require "skynet"
local sprotoparser = require "sprotoparser"
local sprotoloader = require "sprotoloader"
local service = require "common.service"
local log = require "common.log"

local proto_path

local loader = {}
local data = {}
local proto_id = 0

local function load_proto(name)
	local filename = string.format("%s/%s.sproto", proto_path, name)
	local f = assert(io.open(filename), "Can't open " .. filename)
	local t = f:read "a"
	f:close()
	return sprotoparser.parse(t)
end

function loader.load(name)
	proto_id = proto_id + 1

	local p = load_proto(name)
	data[name] = proto_id
	sprotoloader.save(p, proto_id)
	log.notice("save proto %s in slot %d", name, proto_id)
end

function loader.index(name)
    if data[name] == nil then
        loader.load(name)
    end
	return data[name]
end

service.init {
	command = loader,
	info = data,
    init = function()
        proto_path = skynet.getenv "proto_path"
    end
}
