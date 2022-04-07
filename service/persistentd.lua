local skynet = require "skynet"
local mysql = require "skynet.db.mysql"

local datetime = require "datetime_utils" .datetime

local persistent_types = {
    save_user_data = "save_user_data",
}

local mode, master = ...
if master then
    master = assert(tonumber(master))
end

if mode == "slave" then
    local db

    local function query(sql, mutlirows)
	local res = db:query(sql)
	if res.errno then
	    -- error occurs
	    skynet.error("persistent error ", res.err)
	    return nil
	end

	local result = false

	if mutlirows then
	    -- need return multi rows
	    if #res >= 1 then
		result = {}
		for _, v in ipairs(res) do
		    table.insert(result, v)
		end
	    end
	else
	    -- need extract one row
	    if res[1] then
		result = res[1]
	    end
	end

	-- nil means error, false means emtpy data
	return result
    end

    local CMD = {}
    local PERSISTENT_HANDLER = {}

    function PERSISTENT_HANDLER.save_user_data(task)
	local uid = task.uid
	local userdata = task.data

	local sql = string.format("update users set exp = %d, update_time = '%s' where id = %d limit 1",
	    userdata.exp, datetime(), uid)
	local res = db:query(sql)
	if res.err then
	    skynet.error("save_user_data, error: " .. res.err)
	    return false
	end

	return true
    end

    function CMD.do_persistent(taskid, task)
	local f = assert(PERSISTENT_HANDLER[task.type])
	local result = f(task)
	if result then
	    skynet.send(master, "lua", "finish_task", taskid, task.version)
	end
    end

    function CMD.load_user_data(uid)
	skynet.error("load_user_data, uid =", uid)
	local sql = string.format("select id, username, exp, create_time, update_time from users where id = %d limit 1", uid)
	local res = query(sql)

	if not res then
	    skynet.error("load_user_data, try to load not exists user uid =", uid)
	    return false
	end

	return res
    end

    skynet.start(function()
	skynet.dispatch("lua", function(_, _, cmd, ...)
	    local f = assert(CMD[cmd])
	    skynet.retpack(f(...))
	end)

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
		    db:query("select 'hello, mysql'")
		end)
		if not ok then
		    skynet.error("ping mysql error: " .. err)
		end

		-- sleep 60 seconds
		skynet.sleep(6000)
	    end
	end)
    end)
else
    local slaves = {}
    local save_queue = {} -- taskid -> taskdata
    --[[
	save task definition:
	{
	    taskid = number,
	    type = string,
	    uid = number,
	    data = table,
	}
    ]]

    local save_queue_uid2taskid = {}
    local save_queue_taskid2uid = {}

    local function is_user_data_pending_persistent(uid)
	local taskid = save_queue_uid2taskid[uid]
	if taskid then
	    return taskid
	end

	return false
    end

    local taskid = 0
    local function gen_taskid()
	taskid = taskid + 1
	return taskid
    end

    local balance = 1
    local function get_slave()
	local s = slaves[balance]
	balance = balance + 1
	if balance > #slaves then
	    balance = 1
	end

	return s
    end

    local CMD = {}

    local function update_table(old_t, new_t)
	for k, v in pairs(new_t) do
	    if type(v) ~= "table" then
		assert(type(old_t[k]) == type(v))
		old_t[k] = v
	    else
		assert(old_t[k] == "table" or old_t[k] == nil)

		old_t[k] = old_t[k] or {}
		update_table(old_t[k], v)
	    end
	end
    end

    function CMD.load_user_data(uid)
	local s = get_slave()
	local result = skynet.call(s, "lua", "load_user_data", uid)

	local taskid = is_user_data_pending_persistent(uid)
	if taskid then
	    skynet.error("persistent_master", "uid", uid, "user data in save queue to update userdata")

	    local task = save_queue[taskid]
	    update_table(result, task.data)
	end

	return result
    end

    local save_queue_co

    function CMD.save_user_data(uid, userdata)
	local taskid = save_queue_uid2taskid[uid]
	if taskid then
	    skynet.error("overwrite pending persistent data, uid =", uid)
	    local task = save_queue[taskid]
	    update_table(task.data, userdata)

	    task.send_to_slave = false
	    task.version = task.version + 1
	else
	    taskid = gen_taskid()
	    local task = {
		taskid = taskid,
		type = persistent_types.save_user_data,
		uid = uid,
		data = userdata,
		send_to_slave = false,

		version = 1,
	    }

	    save_queue[taskid] = task
	    save_queue_uid2taskid[uid] = taskid
	    save_queue_taskid2uid[taskid] = uid
	end

	skynet.wakeup(save_queue_co)
    end

    local function process_save_queue()
	while true do
	    local process = 0
	    for taskid, task in pairs(save_queue) do
		if not task.send_to_slave then
		    process = process + 1

		    local s = get_slave()
		    skynet.send(s, "lua", "do_persistent", taskid, task)

		    task.send_to_slave = true
		end
	    end

	    if process == 0 then
		skynet.wait(save_queue_co)
	    end
	end
    end

    -- call by persistent slave
    function CMD.finish_task(taskid, version)
	-- skynet.error(string.format("finish_task, taskid = %d, version = %d", taskid, version))

	local task = assert(save_queue[taskid], "task not found, taskid = " .. taskid)
	if task.send_to_slave and task.version == version then
	    save_queue[taskid] = nil

	    local uid = assert(save_queue_taskid2uid[taskid])
	    save_queue_taskid2uid[taskid] = nil
	    save_queue_uid2taskid[uid] = nil
	end
    end

    function CMD.query_service_status()
	local pending_tasks = 0
	for k in pairs(save_queue) do
	    pending_tasks = pending_tasks + 1
	end

	local state = {
	    pending_tasks = pending_tasks,
	}

	return state
    end

    skynet.start(function()
	local slave_pool_size = tonumber(skynet.getenv "persistent_slave_pool_size") or 1

	for i = 1, slave_pool_size do
	    local s = skynet.newservice(SERVICE_NAME, "slave", skynet.self())
	    table.insert(slaves, s)
	end

	skynet.dispatch("lua", function(_, _, cmd, ...)
	    local f = assert(CMD[cmd])
	    skynet.retpack(f(...))
	end)

	save_queue_co = skynet.fork(process_save_queue)
    end)
end
