local skynet = require "skynet"

skynet.start(function()
    skynet.error("Server start", {a = 1, b = 2,})

    skynet.exit()
end)
