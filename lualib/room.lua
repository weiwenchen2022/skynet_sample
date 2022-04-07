local skynet = require "skynet"

local roomd
local room = setmetatable({}, {__index = _ENV,})
_ENV = room

function enter_room(roomid, userdata, agent)
    return skynet.call(roomd, "lua", "enter_room", roomid, userdata, agent)
end

function leave_room(uid)
    return skynet.call(roomd, "lua", "leave_room", uid)
end

function say_public(uid, content)
    return skynet.call(roomd, "lua", "say_public", uid, content)
end

function say_private(uid, to_uid, content)
    return skynet.call(roomd, "lua", "say_private", uid, to_uid, content)
end

function send_exp(uid, to_uid, exp)
    return skynet.call(roomd, "lua", "send_exp", uid, to_uid, exp)
end

function kick(uid, kick_uid)
    return skynet.call(roomd, "lua", "kick", uid, kick_uid)
end

skynet.init(function()
    roomd = skynet.uniqueservice "room"
end)

return room
