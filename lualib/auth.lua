local skynet = require "skynet"
local mysql = require "skynet.db.mysql"

local db

local function auth(username, password)
    local sql = string.format("select id from users where username = '%s' and password = '%s' limit 1",
		    username, password)
    local res = db:query(sql)
    if res.err then
	return nil, res.err
    end

    assert(#res <= 1)

    if #res == 0 then
	return nil, string.format("Unknow user, username = '%s', password = '%s'", username, password)
    end

    return res[1].id
end

skynet.init(function()
    db = mysql.connect {
	host = skynet.getenv "mysql_host" or "127.0.0.1",
	port = tonumber(skynet.getenv "mysql_port") or 3306,
	database = skynet.getenv "mysql_database",
	user = skynet.getenv "mysql_username",
	password = skynet.getenv "mysql_password",
	max_packet_size = 1024 * 1024,

	on_connect = function(db)
	    db:query "set charset utf8"
	end,
    }
    assert(db, "connect to mysql failed")

    -- keep mysql alive
    skynet.fork(function()
	while true do
	    local ok, err = pcall(function()
		local res = db:query("select 'hello, mysql'")
		if res.err then
		    error(res.err)
		end
	    end)

	    if not ok then
		skynet.error("ping mysql error: " .. err)
	    end

	    -- sleep 60 seconds
	    skynet.sleep(6000)
	end
    end)
end)

return auth
