local skynet = require "skynet"
local roomconf = require "roomconf"

local data = {}
local timers = {}
local user2room = {}

local CMD = {}

local function ontimer(id)
    local room = data[id]
    local members = room.members

    local change = {added = roomconf[id].exp,}

    local member = {}
    for _, v in pairs(members) do
	local userinfo = v.userinfo
	local exp = userinfo.exp
	exp = exp + roomconf[id].exp
	userinfo.exp = exp

	member[v.userinfo.id] = {uid = v.userinfo.id, exp = exp,}

	skynet.send(v.agent, "lua", "notify_exp_change", change)
    end

    for _, v in pairs(members) do
	skynet.send(v.agent, "lua", "notify_member_exp", id, member)
    end
end

local function get_room_manager(roomid, exclude_uid)
    local room = data[roomid]
    local max_exp = 0
    local manager

    for uid, v in pairs(room.members) do
	if not exclude_uid or uid ~= exclude_uid then
	    if max_exp < v.userinfo.exp then
		max_exp = v.userinfo.exp
		manager = uid
	    end
	end
    end

    return manager
end

function CMD.enter_room(roomid, userinfo, agent)
    local room = data[roomid]
    if not room then
	return false, "room not exists"
    end

    if user2room[userinfo.id] then
	return false, "user already in room, please leave room first"
    end

    skynet.error("enter_room", roomid, userinfo.id)

    local members = room.members
    if members[userinfo.id] then
	return false, "user already in room"
    end


    members[userinfo.id] = {
	userinfo = userinfo,
	agent = agent,
    }
    user2room[userinfo.id] = roomid
    room.manager = get_room_manager(roomid)

    local member = {}
    for uid, v in pairs(members) do
	if userinfo.id ~= uid then
	    skynet.send(v.agent, "lua", "notify_user_enter", roomid, userinfo, room.manager)
	end

	local userinfo = v.userinfo
	member[userinfo.id] = {
	    uid = userinfo.id,
	    username = userinfo.username,
	    exp = userinfo.exp,
	}
    end

    return true, nil, member, room.manager
end

function CMD.leave_room(uid)
    local roomid = user2room[uid]
    if not roomid then
	return false, "user not in room"
    end

    local room = data[roomid]
    local members = room.members
    assert(members[uid])

    local leave_member = members[uid]
    members[uid] = nil
    user2room[uid] = nil
    room.manager = get_room_manager(roomid)

    for _, v in pairs(members) do
	skynet.send(v.agent, "lua", "notify_user_leave", roomid, leave_member.userinfo, room.manager)
    end

    return true
end

function CMD.say_public(uid, content)
    local roomid = user2room[uid]
    if not roomid then
	return false, "not in room"
    end

    local room = data[roomid]
    local members = room.members
    local message = {
	from_uid = uid,
	to_uid = 0,
	content = content,
    }

    for _, v in pairs(members) do
	skynet.send(v.agent, "lua", "notify_talk_message", message)
    end

    return true
end

function CMD.say_private(uid, to_uid, content)
    local roomid = user2room[uid]
    if not roomid then
	return false, "not in room"
    end

    if uid == to_uid then
	return false, "can not talk to self"
    end

    local room = data[roomid]
    local to_member = room.members[to_uid]
    if not to_member then
	return false, "no member"
    end

    skynet.send(to_member.agent, "lua", "notify_talk_message", {
	from_uid = uid,
	to_uid = to_uid,
	content = content,
    })

    return true
end

function CMD.send_exp(uid, to_uid, exp)
    local from_roomid = user2room[uid]
    local to_roomid = user2room[to_uid]

    if not from_roomid or from_roomid ~= to_roomid then
	return false, "not in the same room"
    end

    if uid == to_uid then
	return false, "can not send exp to self"
    end

    local room = data[from_roomid]
    local from_member = room.members[uid]
    local to_member = room.members[to_uid]

    skynet.error(from_member.userinfo.exp, exp)
    if exp <= 0 or from_member.userinfo.exp < exp then
	return false, "no enough exp"
    end

    from_member.userinfo.exp = from_member.userinfo.exp - exp
    to_member.userinfo.exp = to_member.userinfo.exp + exp
    room.manger = get_room_manager(room.id)

    skynet.send(from_member.agent, "lua", "notify_exp_change", {added = -exp,})
    skynet.send(to_member.agent, "lua", "notify_exp_change", {added = exp,})

    local data = {
	from_uid = uid,
	to_uid = to_uid,
	exp = exp,
	manager = room.manager,
    }
    for _, v in pairs(room.members) do
	skynet.send(v.agent, "lua", "notify_send_exp_message", data)
    end

    return true
end


function CMD.kick(uid, kick_uid)
    local roomid = user2room[uid]
    if not roomid then
	return false, "not in room"
    end

    local room = data[roomid]
    if room.manager ~= uid then
	return false, "not a room manager"
    end

    if uid == kick_uid then
	return false, "can not kick self"
    end

    if not room.members[kick_uid] then
	return false, "no member"
    end

    local kick_member = room.members[kick_uid]

    local data = {
	from_uid = uid,
	kick_uid = kick_uid,
    }

    for _, v in pairs(room.members) do
	skynet.send(v.agent, "lua", "notify_user_leave", roomid, kick_member.userinfo, room.manager)
	skynet.send(v.agent, "lua", "notify_kick_message", data)
    end

    room.members[kick_uid] = nil
    user2room[kick_uid] = nil

    return true
end

local function init()
    for _, v in ipairs(roomconf) do
	local id = v.id
	assert(data[id] == nil)

	local interval = v.interval
	local room = {
	    id = id,
	    name = v.name,
	    exp = v.exp,
	    interval = interval,

	    members = {},
	}
	data[id] = room

	timers["timer" .. id] = function()
	    ontimer(id)
	    skynet.timeout(interval * 100, timers["timer" .. id])
	end

	skynet.timeout(interval * 100, timers["timer" .. id])
    end
end

skynet.start(function()
    skynet.dispatch("lua", function(_, _, cmd, ...)
	local f = assert(CMD[cmd])
	skynet.retpack(f(...))
    end)

    init()
end)
