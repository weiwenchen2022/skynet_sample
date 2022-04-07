local login = require "loginserver"
local crypt = require "skynet.crypt"
local skynet = require "skynet"
local auth = require "auth"

local server = {
    host = assert(skynet.getenv "loginserver_host"),
    port = assert(tonumber(skynet.getenv "loginserver_port")),
    multilogin = false, -- disallow multilogin
    name = "login_master",
}

local server_list = {}
local user_online = {}
local user_login = {}

function server.auth_handler(token)
    -- the token is base64(user)@base64(server):base64(password)
    local user, server, password = token:match("([^@]+)@([^:]+):(.+)")
    user = crypt.base64decode(user)
    server = crypt.base64decode(server)
    password = crypt.base64decode(password)
    -- assert(password == "password", "Invalid password")

    local uid = assert(auth(user, password))
    return server, uid
end

function server.login_handler(server, uid, secret)
    skynet.error(string.format("%s@%s login, secret %s", uid, server, crypt.hexencode(secret)))

    local gameserver = assert(server_list[server], "Unknow server")

    -- only one can login, because disallow multilogin
    local last = user_online[uid]
    if last then
	skynet.call(last.address, "lua", "kick", uid, last.subid)
    end

    if user_online[uid] then
	error(string.format("user is already online", uid))
    end

    local subid = tostring(skynet.call(gameserver, "lua", "login", uid, secret))
    user_online[uid] = {address = gameserver, subid = subid, server = server,}

    return subid
end

local CMD = {}

function CMD.register_gate(server, address)
    server_list[server] = address
end

function CMD.logout(uid, subid)
    skynet.error("logout", uid, subid)

    local u = user_online[uid]
    if u then
	skynet.error(string.format("%s@%s logout", uid, u.server))
	user_online[uid] = nil
    end
end

function server.command_handler(cmd, ...)
    local f = assert(CMD[cmd])
    return f(...)
end

login(server)
