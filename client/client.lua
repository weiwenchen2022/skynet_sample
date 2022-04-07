package.cpath = "skynet/luaclib/?.so"
package.path = "client/?.lua;"
		.. "proto/?.lua;"
		.. "lualib/?.lua;"
		.. "config/?.lua;"
		.. "skynet/lualib/?.lua"

if _VERSION ~= "Lua 5.4" then
    error "Use lua 5.4"
end

local socket = require "client.socket"
local sockethelper = require "sockethelper"
local proto = require "proto"
local sproto = require "sproto"
require "string_utils"

local roomconf = require "roomconf"

local host = sproto.new(proto.s2c):host "package"
local make_request = host:attach(sproto.new(proto.c2s))

local loginserver_host
local loginserver_port
local username
local password
local servername

local gameserver_host
local gameserver_port

local REQUEST = {}
local RESPONSE = {}

local session = 0
local index = 1
local session_map = {}

local self = {
    uid = nil,
    subid = nil,
    secret = nil,
    userinfo = nil,
}

local function send_request(name, arg)
    session = session + 1
    session_map[session] = name

    local str = make_request(name, arg, session)
    sockethelper.send_package(str)

    print("===>", session, name, arg)
    return session, name, arg
end

local function recv_response()
    local t, session, arg = host:dispatch(sockethelper.readpackage())
    assert(t == "RESPONSE")

    local name = assert(session_map[session])
    session_map[session] = nil

    print("<===", session, name, arg)
    local f = assert(RESPONSE[name])
    f(self, arg)
    return session, name, arg
end

local function handle_package(t, ...)
    if t == "REQUEST" then
	local name, arg = ...
	local f = assert(REQUEST[name])
	f(self, arg)

	return "REQUEST", name, arg
    else
	assert(t == "RESPONSE")
	local session, arg = ...

	local name = assert(session_map[session])
	session_map[session] = nil

	print("<===", session, name, arg)

	local f = assert(RESPONSE[name])
	f(self, arg)

	return "RESPONSE", session, name, arg
    end
end

local function disptach_package()
    while true do
	local v = sockethelper.try_read_package()
	if not v then break end

	handle_package(host:dispatch(v))
    end
end

-------------------------------------------------------------
function RESPONSE:login(arg)
    assert(self.uid == arg.userinfo.uid)
    self.userinfo = arg.userinfo

    print("retrieved userinfo:", self.userinfo)
end

function RESPONSE:list_room(arg)
    print("server have these rooms available")

    for _, v in pairs(arg.room) do
	print(string.format("id = %d, name = %s, exp = %d, interval = %d",
	    v.id, v.name, v.exp, v.interval))
    end
end

function RESPONSE:enter_room(arg)
    if arg.ok then
	assert(self.roominfo == nil)
	assert(arg.manager and arg.member[arg.manager])

	self.roominfo = {
	    roomid = arg.roomid,
	    member = arg.member,
	    manager = arg.manager,
	}

	print("room members:")
	for _, v in pairs(arg.member) do
	    print(string.format("uid = %d, username = %s, exp = %d", v.uid, v.username, v.exp))
	end

	print("room manager = " .. arg.manager)
    else
	print("enter_room, error: " .. arg.err)
    end
end

function RESPONSE:leave_room(arg)
    if self.roominfo then
	assert(arg.ok, arg.err)
	self.roominfo = nil
    else
	print("leave_room, error: " .. arg.err)
    end
end

function RESPONSE:say_public(arg)
    if self.roominfo then
	assert(arg.ok, arg.err)
    end
end

function RESPONSE:say_private(arg)
    if not arg.ok then
	print("say_private, error: " .. arg.err)
    end
end

function RESPONSE:send_exp(arg)
    if not arg.ok then
	print("send_exp, error: " .. arg.err)
    end
end

function RESPONSE:kick(arg)
    if not arg.ok then
	print("kick error: " .. arg.err)
    end
end
-------------------------------------------------

function REQUEST:exp_message(arg)
    assert(self.roominfo.roomid)
    assert(self.uid == arg.uid)

    self.userinfo.exp = arg.exp
end

function REQUEST:member_exp_message(arg)
    assert(self.roominfo.roomid == arg.roomid)

    for _, v in pairs(self.roominfo.member) do
	assert(arg.member[v.uid])
	v.exp = arg.member[v.uid].exp
    end

    for _, v in pairs(arg.member) do
	assert(self.roominfo.member[v.uid])
    end
end

function REQUEST:enter_room_message(arg)
    assert(self.roominfo.roomid == arg.roomid)
    assert(self.roominfo.member[arg.uid] == nil)
    assert(arg.manager and (self.roominfo.member[arg.manager] or arg.uid == arg.manager))

    print(string.format("enter_room_message, uid = %d, username = %s, exp = %d, manager = %d",
	arg.uid, arg.username, arg.exp, arg.manager))

    self.roominfo.member[arg.uid] = {uid = arg.uid, username = arg.username, exp = arg.exp,}
    self.roominfo.manager = arg.manager
end

function REQUEST:leave_room_message(arg)
    assert(self.roominfo.roomid == arg.roomid)
    assert(self.roominfo.member[arg.uid])
    assert(arg.manager and arg.uid ~= arg.manager and self.roominfo.member[arg.manager])

    print(string.format("leave_room_message, uid = %d, username = %s, manager = %d",
	arg.uid, arg.username, arg.manager))
    self.roominfo.member[arg.uid] = nil
    self.roominfo.manager = arg.manager
end

function REQUEST:talk_message(arg)
    if arg.to_uid == 0 then
	print(string.format("talk_message, uid: %d, said: %s", arg.from_uid, arg.content))
    else
	assert(self.uid == arg.to_uid)

	print(string.format("talk_message, uid: %d, said to me: %s", arg.from_uid, arg.content))
    end
end

function REQUEST:send_exp_message(arg)
    assert(arg.from_uid ~= arg.to_uid)

    local from_member = assert(self.roominfo.member[arg.from_uid])
    local to_member = assert(self.roominfo.member[arg.to_uid])
    local exp = assert(arg.exp > 0 and arg.exp)
    assert(from_member.exp >= exp)
    assert(arg.manager and self.roominfo.member[arg.manager])

    print(string.format("send_exp_message, from_uid = %d, to_uid = %d, exp = %d, manager = %d",
	arg.from_uid, arg.to_uid, exp, arg.manager))

    from_member.exp = from_member.exp - exp
    to_member.exp = to_member.exp + exp
    self.roominfo.manager = arg.manager
end

function REQUEST:kick_message(arg)
    assert(self.roominfo)
    assert(self.roominfo.manager == arg.from_uid and self.roominfo.member[arg.from_uid])

    print(string.format("user = %d kicked the user %d out of room", arg.from_uid, arg.kick_uid))

    if self.uid == arg.kick_uid then
	assert(self.roominfo)
	self.roominfo = nil
    end
end
--------------------------------------------------

local function readstdin(robot)
    if not robot then
        return socket.readstdin()
    end

    if math.random(1, 100) <= 0 then
	return nil
    end

    if math.random(1, 100) > 50 then
	local sleep = math.random(100, 500)
	socket.usleep(sleep * 1000)
    end

    local function say_content()
	local contents = {
	    "hello world",
	}

	return contents[math.random(1, #contents)]
    end

    local function room_member()
	if self.roominfo then
	    local members = {}
	    for uid in pairs(self.roominfo.member) do
		if self.uid ~= uid then
		    table.insert(members, uid)
		end
	    end

	    if next(members) then
		return members[math.random(1, #members)]
	    end
	end

	return self.uid
    end

    local function send_exp()
	return math.random(1, self.userinfo.exp)
    end

    local cmds = {
	{"login",},
	{"logout",},

	{"list_room",},
	{"enter_room", function() return roomconf[math.random(1, #roomconf)].id end,},
	{"leave_room",},

	{"say", say_content,},
	{"sayto", room_member, say_content,},

	{"send_exp", room_member, send_exp,},
	{"kick", room_member,},
    }

    local c = cmds[math.random(1, #cmds)]
    local list = {}
    for i, v in ipairs(c) do
	local t = type(v)
	if i == 1 then
	    assert(t == "string")
	end

	if t == "string" then
	    table.insert(list, v)
	else
	    assert(t == "function")
	    table.insert(list, table.concat({v(),}, " "))
	end
    end

    return table.concat(list, " ")
end

function main_loop(loginserver_host, loginserver_port, gameserver_host, gameserver_port, username, password, robot)
    print "trying to login with login server"
    self.uid, self.subid, self.secret = sockethelper.login_loginserver(loginserver_host, loginserver_port, username, password, "server1")

    sockethelper.login_gameserver(gameserver_host, gameserver_port)
    self.roominfo = nil

    print "login"
    send_request("login", {})
    recv_response()

    send_request("list_room", {})
    recv_response()

    math.randomseed(os.time())
    local roomid = roomconf[1].id or roomconf[math.random(1, #roomconf)].id
    send_request("enter_room", {roomid = roomid,})
    recv_response()

    -- local sleep = math.random(1, 7)
    -- print("leave room after " .. sleep .. " seconds")
    -- socket.usleep(sleep * 1000000)

    -- send_request("leave_room", {})
    -- recv_response()

    -- send_request("logout", {})
    -- recv_response()

    while true do
        disptach_package()

	local line = readstdin(robot)
        -- local line = socket.readstdin()
        if line then
            local arg = string.split(line)
            local cmd = arg[1]

	    if cmd == "login" then
		send_request("login", {})
	    elseif cmd == "logout" then
                send_request("logout", {})
	    elseif cmd == "list_room" then
		send_request("list_room", {})
	    elseif cmd == "enter_room" then
		local roomid = tonumber(arg[2])
		if not roomid then
		    print "enter_room roomid"
		    goto continue
		end

		send_request("enter_room", {roomid = roomid,})
	    elseif cmd == "leave_room" then
		send_request("leave_room", {})
	    elseif cmd == "say" then
		if #arg < 2 then
		    print("say content")
		    goto continue
		end

		local content = table.concat(arg, " ", 2)

		send_request("say_public", {content = content,})
	    elseif cmd == "sayto" then
		local to_uid = tonumber(arg[2])

		if #arg < 3 or not to_uid then
		    print("sayto to_uid content")
		    goto continue
		end

		local content = table.concat(arg, " ", 3)

		send_request("say_private", {to_uid = to_uid, content = content,})
	    elseif cmd == "send_exp" then
		local to_uid = tonumber(arg[2])
		local exp = tonumber(arg[3])

		if #arg ~= 3 or not to_uid or not exp then
		    print("send_exp to_uid exp")
		    goto continue
		end

		send_request("send_exp", {to_uid = to_uid, exp = exp,})
	    elseif cmd == "kick" then
		local uid = tonumber(arg[2])
		if not uid then
		    print "kick uid"
		    goto continue
		end

		send_request("kick", {uid = uid,})
            else
        	print("Unknown cmd " .. cmd)
            end
        else
            socket.usleep(100)
        end

	::continue::
    end
end

local username, password = "test", "test"
local robot = false

if #arg == 1 then
    robot = arg[1] == "robot"
elseif #arg >= 2 then
    username = arg[1]
    password = arg[2]
    robot = arg[3] == "robot"
end

print "test start"

while true do
    local ok, err = pcall(main_loop, "127.0.0.1", 8001, "127.0.0.1", 8888, username, password, robot)
    assert(not ok)

    if type(err) == "string" and (string.find(err, "Server closed") or string.find(err, "Broken pipe")) then
	--  continue
    else
	print("main_loop, error: ", tostring(err))
	break
    end
end

print "test finished"
