package.cpath = "../skynet/luaclib/?.so;" .. package.cpath

local socket = require "client.socket"
local crypt = require "client.crypt"

local base64decode = crypt.base64decode
local base64encode = crypt.base64encode

local M = setmetatable({}, {__index = _ENV,})
_ENV = M

local loginserver_host
local loginserver_port

local gameserver_host
local gameserver_port

local servername
local username
local password
local secret

local fd
local last = ""

local uid
local subid

local function unpack_f(f, nonblock)
    local function try_recv(fd, last)
	local result
	result, last = f(last)
	if result then
	    return result, last
	end

	local r = socket.recv(fd)
	if not r then
	    return nil, last
	end

	if r == "" then
	    error "Server closed"
	end

	return f(last .. r)
    end

    return function()
	while true do
	    local result
	    result, last = try_recv(fd, last)
	    if result then
		return result
	    end

	    if nonblock then break end

	    socket.usleep(100)
	end
    end
end

local function unpack_package(text)
    local size = #text
    if size < 2 then
	return nil, text
    end

    local sz = string.unpack(">I2", text)
    if size < 2 + sz then
	return nil, text
    end

    return text:sub(3, 2 + sz), text:sub(3 + sz)
end

readpackage = unpack_f(unpack_package)
try_read_package = unpack_f(unpack_package, true)

function send_package(pack)
    local package = string.pack(">s2", pack)
    socket.send(fd, package)
end

function login_loginserver(host, port, user, pwd, server)
    if fd then
	socket.close(fd)
	fd = nil
    end
    fd = assert(socket.connect(host, port))
    print(string.format("login_loginserver, fd: %d, sockname: %s, peername: %s",
	fd, socket.getsockname(fd), socket.getpeername(fd)))

    last = ""

    local challenge = base64decode(readpackage())

    local clientkey = crypt.randomkey()
    send_package(base64encode(crypt.dhexchange(clientkey)))
    secret = crypt.dhsecret(base64decode(readpackage()), clientkey)
    print("secret ", crypt.hexencode(secret))

    local hmac = crypt.hmac64(challenge, secret)
    send_package(base64encode(hmac))

    username = user
    password = pwd
    servername = server

    local token = {
	servername = servername,
	username = username,
	password = password,
    }

    local function encode_token(token)
	return string.format("%s@%s:%s",
	    base64encode(token.username),
	    base64encode(token.servername),
	    base64encode(token.password)
	)
    end

    local etoken = crypt.desencode(secret, encode_token(token))
    send_package(base64encode(etoken))

    local result = readpackage()
    print(result)

    local code = tonumber(string.sub(result, 1, 3))
    assert(code == 200)

    result = string.sub(result, 5)
    uid, subid = string.match(result, "([%S]+) ([%S]+)")
    uid = tonumber(base64decode(uid))
    subid = tonumber(base64decode(subid))
    print(string.format("login ok, uid = %d, subid = %d", uid, subid))

    socket.close(fd)
    fd = nil

    return uid, subid, secret
end

local index = 1

function login_gameserver(host, port)
    if fd then
	socket.close(fd)
	fd = nil
    end
    fd = assert(socket.connect(host, port))
    print(string.format("login_gameserver, fd: %d, sockname: %s, peername: %s",
	    fd, socket.getsockname(fd), socket.getpeername(fd)))

    last = ""

    local handshake = string.format("%s@%s#%s:%d",
			base64encode(uid),
			base64encode(servername),
			base64encode(subid),
			index
		    )
    index = index + 1
    local hmac = crypt.hmac64(crypt.hashkey(handshake), secret)
    send_package(handshake .. ":" .. base64encode(hmac))

    local result = readpackage()
    assert("200 OK" == result, result)
end

return M
