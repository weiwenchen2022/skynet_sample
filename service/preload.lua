do
    local skynet = require "skynet"
    require "string_utils"

    local TIME_FMT = "%Y-%m-%d %H:%M:%S"
    local FMT = "%s.%02d [%s] %s"

    if skynet.getenv "logger" then
	TIME_FMT = nil
	FMT = "[%s] %s"
    end

    local error = skynet.error

    skynet.error = function(...)
	local t = {...}
	for i, v in ipairs(t) do
	    t[i] = tostring(v)
	end

	local msg = table.concat(t, " ")

	local info = debug.getinfo(2, "Sl")
	if info then
	    msg = string.format("[%s:%d] %s", info.short_src, info.currentline, msg)
	end

	if TIME_FMT then
	    msg = string.format(FMT, os.date(TIME_FMT, skynet.time() // 1), skynet.now() % 100, SERVICE_NAME, msg)
	else
	    msg = string.format(FMT, SERVICE_NAME, msg)
	end

	error(msg)
    end
end
