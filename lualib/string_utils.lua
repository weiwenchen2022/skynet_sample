function string.split(str, sep)
    local tokens = {}
    local pattern = "[^" .. (sep or "%s").. "]+"

    for token in string.gmatch(str, pattern) do
	table.insert(tokens, token)
    end

    return tokens
end

do
    local tostring = _G.tostring

    local function serialize(o, level)
	local t = type(o)

	if t == "number" or t == "string" or t == "boolean" or t == "nil" then
	    return string.format("%q", o)
	elseif t == "table" then
	    level = (level or 0) + 1
	    local indent = string.rep("\t", level)

	    local list = {"{\n",}
	    for k, v in pairs(o) do
		table.insert(list, string.format("%s[%s] = %s,\n",
		    indent, serialize(k, level), serialize(v, level)))
	    end

	    if level == 1 then
		table.insert(list, string.rep("\t", level - 1) .. "}\n")
	    else
		table.insert(list, string.rep("\t", level - 1) .. "}")
	    end

	    return table.concat(list)
	else
	    return tostring(o)
	end
    end

    _G.tostring = function(o)
	local t = type(o)

	if t == "string" then
	    return o
	elseif t == "number" or t == "boolean" or t == "nil" then
	    return string.format("%q", o)
	elseif t == "table" then
	    return serialize(o)
	else
	    return tostring(o)
	end
    end

    local print = _G.print
    _G.print = function(...)
	local t = {...}
	for i, v in ipairs(t) do
	    t[i] = _G.tostring(v)
	end

	print(table.unpack(t))
    end
end
