local skynet = require "skynet"
local auth = require "auth"

skynet.start(function()
    local uid = auth("test", "test")
    skynet.error("uid =", uid)

    -- skynet.exit()
end)
