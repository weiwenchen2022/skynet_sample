local skynet = require "skynet"
local persistent = require "persistent"
require "string_utils"

skynet.start(function()
    local userdata = persistent.load_user_data("test")
    assert(userdata)
    skynet.error("userdata =", tostring(userdata))

    userdata.exp = 10
    persistent.save_user_data(userdata.id, userdata)
    userdata.exp = 100
    persistent.save_user_data(userdata.id, userdata)

    userdata = persistent.load_user_data("test")
    assert(userdata.exp == 100)

    skynet.error("query_service_status =", tostring(persistent.query_service_status()))

    skynet.exit()
end)
