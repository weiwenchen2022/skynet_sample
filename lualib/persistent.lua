local skynet = require "skynet"

local persistent = setmetatable({}, {__index = _ENV,})
_ENV = persistent

local persistentd

function load_user_data(uid)
    return skynet.call(persistentd, "lua", "load_user_data", uid)
end

function save_user_data(uid, userdata)
    skynet.send(persistentd, "lua", "save_user_data", uid, userdata)
end

function query_service_status()
    return skynet.call(persistentd, "lua", "query_service_status")
end

skynet.init(function()
    persistentd = skynet.uniqueservice "persistentd"
end)

return persistent
