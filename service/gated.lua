local msgserver = require "msgserver"
local crypt = require "skynet.crypt"
local skynet = require "skynet"

local loginserver = assert(tonumber(...))

local server = {}
local users = {}
local username_map = {}
local internal_id = 0
local servername

local agent_pool = setmetatable({}, {__mode = "v",})
local agent_meta = {
    __gc = function(t)
	skynet.send(t[1], "lua", "exit")
    end,
}

-- login server disallow multi login, so login_handler never be reentry
-- call by login server
function server.login_handler(uid, secret)
    if users[uid] then
	error(string.format("%s already login", uid))
    end

    internal_id = internal_id + 1
    local id = internal_id -- don' use internal_id directly
    local username = msgserver.username(uid, id, servername)

    -- You can use a pool to alloc new agent
    local agent = table.remove(agent_pool)
    if not agent then
	agent = setmetatable({skynet.newservice"msgagent",}, agent_meta)
    end

    local u = {
	username = username,
	agent = agent,
	uid = uid,
	subid = id,
    }

    -- trash subid (no used)
    skynet.call(agent[1], "lua", "login", uid, id, secret, skynet.self())

    users[uid] = u
    username_map[username] = u
    msgserver.login(username, secret)

    -- You should return unique subid
    return id
end

-- call by agent
function server.logout_handler(uid, subid)
    skynet.error("logout_handler", uid, subid)

    local u = users[uid]
    if u then
	local username = msgserver.username(uid, subid, servername)
	assert(u.username == username)

	msgserver.logout(u.username)

	users[uid] = nil
	username_map[u.username] = nil
	skynet.call(loginserver, "lua", "logout", uid, subid)
	table.insert(agent_pool, u.agent)
    end
end

-- call by login server
function server.kick_handler(uid, subid)
    skynet.error(string.format("kick_handler, uid = %d, subid = %d", uid, subid))

    local u = users[uid]
    if u then
	local username = msgserver.username(uid, subid, servername)
	assert(u.username == username)

	-- Note: logout may call skynet.exit(), so you should use pcall.
	pcall(skynet.call, u.agent[1], "lua", "logout")
    end
end

-- call by self (when socket disconnect)
function server.disconnect_handler(username)
    local u = username_map[username]
    if u then
	skynet.call(u.agent[1], "lua", "afk")
    end
end

-- call by self (when recv a request from client)
function server.request_handler(username, msg)
    local u = username_map[username]
    skynet.redirect(u.agent[1], 0, "client", u.fd, msg)
end

function server.auth_handler(uid, fd, ip)
    skynet.error(string.format("auth_handler, uid = %d, fd = %d, ip = %s", uid, fd, ip))

    local u = users[uid]
    u.fd = fd
    skynet.call(u.agent[1], "lua", "associate_fd_ip", fd, ip)
end

-- call by self (when gate open)
function server.register_handler(name)
    servername = name
    skynet.call(loginserver, "lua", "register_gate", servername, skynet.self())
end

skynet.info_func(function()
    local online_users = 0
    for _ in pairs(users) do
	online_users = online_users + 1
    end

    return {
	online_users = online_users,
	agent_pool_size = #agent_pool,
	recycled_agents = recycled_agents,
    }
end)

msgserver.start(server)
