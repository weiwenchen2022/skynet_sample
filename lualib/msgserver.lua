local skynet = require "skynet"
local gateserver = require "snax.gateserver"
local netpack = require "skynet.netpack"
local crypt = require "skynet.crypt"
local socketdriver = require "skynet.socketdriver"

local assert = assert
local b64encode = crypt.base64encode
local b64decode = crypt.base64decode

--[[
Protocol:

    All the number type is big-endian

    Shakehands (The first package)

    Client -> Server:
	base64(uid)@base64(server)#base64(subid):index:base64(hmac)

    Server -> Client

	ErrorCode
	    404 User Not Found
	    403 Index Expired
	    401 Unauthorized
	    400 Bad Request
	    200 OK

    Req-Resp

	Client -> Server: Request
		size word (Not include this)
		content bytes (size - 4)
		session dword

	Server -> Client: Response
		size word (Not include this)
		content bytes (size - 5)
		ok byte (1 is ok, 0 is error)
		session dword

API:
	msgserver.userid(username): return uid, subid, server

	msgserver.username(uid, subid, server): return username

	msgserver.login(username, secret): update user secret

	msgserver.logout(username): user logout

	msgserver.ip(username): return ip when connection establish, or nil

	msgserver.start(conf): start server

Supported skynet command:
	kick username (may used by loginserver)
	login username secret (used by loginserver)
	logout username (used by agent)

Config for msgserver.start():
	conf.login_handler(uid, secret) : return subid, the function when a new user login, alloc a subid for it. (may call by login server)

	conf.logout_handler(uid, subid) : the function when a user logout. (may call by agent)

	conf.kick_handler(uid, subid) : the function when a user logout. (may call by login server)

	conf.request_handler(username, msg, sz) : the function when recv a new request

	conf.register_handler(servername) : call when gate open

	conf.disconnect_handler(username) : call when a connection disconnect (afk)
]]

local msgserver = {}

skynet.register_protocol {
    name = "client",
    id = skynet.PTYPE_CLIENT,
}

local user_online = {}
local handshake = {}
local connection = {}

function msgserver.userid(username)
    -- base64(uid)@base64(server)#base64(subid)
    local uid, servername, subid = username:match "([^@]*)@([^#]*)#(.*)"
    return tonumber(b64decode(uid)), tonumber(b64decode(subid)), b64decode(servername)
end

function msgserver.username(uid, subid, servername)
    return string.format("%s@%s#%s", b64encode(uid), b64encode(servername), b64encode(subid))
end

function msgserver.logout(uid)
    local u = user_online[uid]
    user_online[uid] = nil

    if u.fd then
	gateserver.closeclient(u.fd)
	connection[u.fd] = nil
    end
end

function msgserver.login(username, secret)
    assert(user_online[username] == nil)

    user_online[username] = {
	secret = secret,
	version = 0,
	username = username,
    }
end

function msgserver.ip(username)
    local u = user_online[username]
    if u and u.fd then
	return u.ip
    end
end

function msgserver.fd(username)
    local u = user_online[username]
    if u and u.fd then
	return u.fd
    end
end

function msgserver.start(conf)
    local handler = {}

    local CMD = {
	login = assert(conf.login_handler),
	logout = assert(conf.logout_handler),
	kick = assert(conf.kick_handler),
    }

    function handler.command(cmd, source, ...)
	local f = assert(CMD[cmd])
	return f(...)
    end

    function handler.open(source, gateconf)
	local servername = assert(gateconf.servername)
	return conf.register_handler(servername)
    end

    function handler.connect(fd, addr)
	handshake[fd] = addr
	gateserver.openclient(fd)
    end

    function handler.disconnect(fd)
	handshake[fd] = nil

	local c = connection[fd]
	if c then
	    connection[fd] = nil
	    c.fd = nil

	    if conf.disconnect_handler then
		conf.disconnect_handler(c.username)
	    end
	end
    end

    handler.error = handler.disconnect

    -- atomic, no yield
    local function do_auth(fd, message, addr)
	local username, index, hmac = string.match(message, "([^:]*):([^:]*):([^:]*)")
	local u = user_online[username]
	if u == nil then
	    return "404 User Not Found"
	end

	local idx = assert(tonumber(index))
	hmac = b64decode(hmac)

	if idx <= u.version then
	    return "403 Index Expired"
	end

	local text = string.format("%s:%s", username, index)
	local v = crypt.hmac_hash(u.secret, text)
	if v ~= hmac then
	    return "401 Unauthorized"
	end

	u.version = idx
	u.fd = fd
	u.ip = addr
	u.username = username
	connection[fd] = u
    end

    local auth_handler = assert(conf.auth_handler)

    local function auth(fd, addr, msg, sz)
	local message = netpack.tostring(msg, sz)
	local ok, result = pcall(do_auth, fd, message, addr)
	if not ok then
	    skynet.error(result)
	    result = "400 Bad Request"
	end

	local close = result ~= nil

	if result == nil then
	    result = "200 OK"
	end

	if not close then
	    local u = connection[fd]
	    auth_handler(msgserver.userid(u.username), u.fd, u.ip)
	end

	socketdriver.send(fd, netpack.pack(result))

	if close then
	    gateserver.closeclient(fd)
	end
    end

    local request_handler = assert(conf.request_handler)

    local function do_request(fd, message)
	local u = assert(connection[fd], "invalid fd")
	request_handler(u.username, message)
    end

    local function request(fd, msg, sz)
	local message = netpack.tostring(msg, sz)
	local ok, err = pcall(do_request, fd, message)
	-- Not atomic, may yield
	if not ok then
	    skynet.error(string.format("Invalid package %s : %s", err, message))

	    if connection[fd] then
		gateserver.closeclient(fd)
	    end
	end
    end

    function handler.message(fd, msg, sz)
	local addr = handshake[fd]
	if addr then
	    auth(fd, addr, msg, sz)
	    handshake[fd] = nil
	else
	    request(fd, msg, sz)
	end
    end

    return gateserver.start(handler)
end

return msgserver
