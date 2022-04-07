local skynet = require "skynet"
local sprotoloader = require "sprotoloader"

skynet.start(function()
    skynet.error("Server start")

    skynet.uniqueservice "protoloader"

    if not skynet.getenv "daemon" then
        local console = skynet.newservice("console")
    end

    skynet.newservice("debug_console", 8000)

    local loginserver = skynet.uniqueservice "logind"
    local gate = skynet.uniqueservice("gated", loginserver)
    skynet.call(gate, "lua", "open", {
        port = assert(tonumber(skynet.getenv "gameserver_port")),
        maxclient = 1024,
        servername = "server1",
	nodelay = true,
    })

    skynet.error("Server start finished")
    skynet.exit()
end)
