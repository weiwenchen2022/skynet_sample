local skynet = require "skynet"
local socket = require "skynet.socket"
local sprotoloader = require "sprotoloader"

local persistent = require "persistent"
local room = require "room"

local roomconf = require "roomconf"

local host
local make_request

-- agent state
local self = {
    uid = nil,
    subid = nil,
    gate = nil,

    fd = nil,
    ip = nil,

    afk = false,
    last_active = nil,

    userdata = nil,

    logout_ing = false,
}

local function send_package(pack)
    if not self.fd then return end

    pack = string.pack(">s2", pack)
    socket.write(self.fd, pack)
end

local REQUEST = {}

local function request(name, arg, response)
    if self.logout_ing then return end

    local f = assert(REQUEST[name])
    local result = f(self, arg)

    if response then
	return response(result)
    end
end

skynet.register_protocol {
    name = "client",
    id = skynet.PTYPE_CLIENT,

    unpack = function(msg, sz)
	return host:dispatch(msg, sz)
    end,

    dispatch = function(fd, _, type, ...)
	assert(self.fd == fd) -- You can use fd to reply message
	skynet.ignoreret() -- session is fd, don't call skynet.ret
	-- skynet.trace()

	if type == "REQUEST" then
	    local ok, result = pcall(request, ...)
	    if ok then
		if result then
		    send_package(result)
		end
	    else
		skynet.error(result)
	    end
	else
	    assert(type == "RESPONSE")
	    error "Server doesn't support request client"
	end

	self.last_active = skynet.time()
    end,
}

local CMD = {}

-----------------------------------------------------------
function REQUEST:login()
    skynet.error("user uid =", self.uid, "login")

    return {
	userinfo = {
	    uid = self.uid,
	    username = self.userdata.username,
	    exp = self.userdata.exp,
	},
    }
end

function REQUEST:logout()
    skynet.error("logout")
    CMD.logout()
end

function REQUEST:list_room()
    local room = {}

    for _, v in pairs(roomconf) do
	room[v.id] = {
	    id = v.id,
	    name = v.name,
	    exp = v.exp,
	    interval = v.interval,
	}
    end

    return {room = room,}
end

function REQUEST:enter_room(arg)
    local ok, err, member, manager = room.enter_room(arg.roomid, self.userdata, skynet.self())
    return {ok = ok, err = err, roomid = arg.roomid, member = member, manager = manager,}
end

function REQUEST:leave_room()
    local ok, err = room.leave_room(self.uid)
    return {ok = ok, err = err,}
end

function REQUEST:say_public(arg)
    local ok, err = room.say_public(self.uid, arg.content)
    return {ok = ok, err = err,}
end

function REQUEST:say_private(arg)
    local ok, err = room.say_private(self.uid, arg.to_uid, arg.content)
    return {ok = ok, err = err,}
end

function REQUEST:send_exp(arg)
    local ok, err = room.send_exp(self.uid, arg.to_uid, arg.exp)
    return {ok = ok, err = err,}
end

function REQUEST:kick(arg)
    local ok, err = room.kick(self.uid, arg.uid)
    return {ok = ok, err = err,}
end

---------------------------------------------------------
function CMD.notify_exp_change(arg)
    self.userdata.exp = self.userdata.exp + arg.added

    send_package(make_request("exp_message", {uid = self.uid, exp = self.userdata.exp,}))
end

function CMD.notify_member_exp(roomid, member)
    send_package(make_request("member_exp_message", {roomid = roomid, member = member,}))
end

function CMD.notify_user_enter(roomid, userinfo, manager)
    local data = {
	roomid = roomid,
	uid = userinfo.id,
	username = userinfo.username,
	exp = userinfo.exp,
	manager = manager,
    }

    send_package(make_request("enter_room_message", data))
end

function CMD.notify_user_leave(roomid, userinfo, manager)
    local data = {
	roomid = roomid,
	uid = userinfo.id,
	username = userinfo.username,
	manager = manager,
    }

    send_package(make_request("leave_room_message", data))
end

function CMD.notify_talk_message(arg)
    local data = {
	from_uid = arg.from_uid,
	to_uid = arg.to_uid,
	content = arg.content,
    }

    send_package(make_request("talk_message", data))
end

function CMD.notify_send_exp_message(arg)
    local data = {
	from_uid = arg.from_uid,
	to_uid = arg.to_uid,
	exp = arg.exp,
	manager = arg.manager,
    }

    send_package(make_request("send_exp_message", data))
end

function CMD.notify_kick_message(arg)
    local data = {
	from_uid = arg.from_uid,
	kick_uid = arg.kick_uid,
    }

    send_package(make_request("kick_message", data))
end
---------------------------------------------------------

local function save_user_data()
    persistent.save_user_data(self.uid, self.userdata)
end

local agent_bgsave_interval = tonumber(skynet.getenv "agent_bgsave_interval") or 7

local function bg_save()
    if not self.userdata then return end

    save_user_data()
    skynet.timeout(agent_bgsave_interval * 100, bg_save)
end

local agent_check_idle_interval = 1 or tonumber(skynet.getenv "agent_check_idle_interval") or 60
local agent_session_expire = tonumber(skynet.getenv "agent_session_expire") or 180

local function check_idle()
    if not self.uid or not self.last_active then return end

    if skynet.time() - self.last_active >= agent_session_expire then
	skynet.error("uid =", self.uid, "recycleable detected")
	skynet.send(skynet.self(), "lua", "logout")
	return
    end

    skynet.timeout(agent_check_idle_interval * 100, check_idle)
end

function CMD.associate_fd_ip(fd, ip)
    skynet.error(string.format("associate_fd_ip, uid = %d, fd = %d, ip = %s",
	self.uid, fd, ip))

    local s = string.match(ip, "([^:]+):.*")
    if s then
	ip = s
    end

    self.fd = fd
    self.ip = ip
    self.afk = false
    self.last_active = skynet.time()

    skynet.timeout(agent_check_idle_interval, check_idle)
end

function CMD.login(uid, sid, secret, gateserver)
    -- You may use secret to make a encrypted data stream
    skynet.error(string.format("%d login", uid))

    self.gate = gateserver
    self.uid = uid
    self.subid = sid

    -- You may load user data from database
    local userdata = persistent.load_user_data(uid)
    self.userdata = userdata

    skynet.timeout(agent_bgsave_interval * 100, bg_save)
end

local function logout()
    self.logout_ing = true

    room.leave_room(self.uid)
    save_user_data()

    if self.gate then
        skynet.call(self.gate, "lua", "logout", self.uid, self.subid)
    end

    skynet.error("uid =", self.uid, "data reset for reuse")
    self.uid = nil
    self.subid = nil
    self.gate = nil
    self.fd = nil
    self.ip = nil
    self.afk = true
    self.last_active = nil
    self.userdata = nil
    self.logout_ing = false
    -- skynet.exit()
end

function CMD.logout()
    -- Note: the logout may be reentry
    skynet.error(string.format("uid = %d, logout", self.uid))
    logout()

    return true
end

function CMD.afk()
    -- the connection is broken, but user may back
    skynet.error(string.format("afk, uid = %d, name = %s",
	self.uid, self.userdata.username))

    save_user_data()

    self.fd = nil
    self.ip = nil
    self.afk = true
end

function CMD.exit()
    skynet.exit()
end

skynet.start(function()
    -- If you want to fork a work thread, you must do it in CMD.login()
    skynet.dispatch("lua", function(_, _, cmd, ...)
	local f = assert(CMD[cmd])
	skynet.retpack(f(...))
    end)

    host = sprotoloader.load(1):host "package"
    make_request = host:attach(sprotoloader.load(2))
end)
