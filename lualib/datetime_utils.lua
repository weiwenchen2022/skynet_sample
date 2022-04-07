local M = setmetatable({}, {__index = _ENV,})
_ENV = M

function datetime(time)
    return os.date("%Y-%m-%d %H:%M:%S", time)
end

return M
