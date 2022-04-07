-- module proto at proto/proto.lua
package.path = "./proto/?.lua;" .. package.path

local skynet = require "skynet"
local sprotoloader = require "sprotoloader"
local proto = require "proto"

skynet.start(function()
    sprotoloader.save(proto.types, 0)
    sprotoloader.save(proto.c2s, 1)
    sprotoloader.save(proto.s2c, 2)

    -- Don't call skynet.exit(), because sproto.core may unload and the global slot become invalid
end)
