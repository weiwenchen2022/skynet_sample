local sprotoparser = require "sprotoparser"

local proto = {}

local types = [[
    .package {
	type 0 : integer
	session 1 : integer
    }

    .user {
	uid 0 : integer
	username 1 : string
	exp 2 : integer
    }

    .roominfo {
	id 0 : integer
	name 1 : string
	exp 2 : integer
	interval 3 : integer
    }
]]

local c2s = [[
    login 1 {
	request {
	}

	response {
	    userinfo 0 : user
	}
    }

    logout 2 {
	request {
	}
    }

    list_room 3 {
	request {
	}

	response {
	    room 0 : *roominfo(id)
	}
    }

    enter_room 4 {
	request {
	    roomid 0 : integer
	}

	response {
	    ok 0 : boolean
	    err 1 : string

	    roomid 2 : integer
	    member 3 : *user(uid)
	    manager 4 : integer
	}
    }

    leave_room 5 {
	request {
	}

	response {
	    ok 0 : boolean
	    err 1 : string
	}
    }

    say_public 6 {
	request {
	    content 0 : string
	}

	response {
	    ok 0 : boolean
	    err 1 : string
	}
    }

    say_private 7 {
	request {
	    to_uid 0 : integer
	    content 1 : string
	}

	response {
	    ok 0 : boolean
	    err 1 : string
	}
    }

    send_exp 8 {
	request {
	    to_uid 0 : integer
	    exp 1 : integer
	}

	response {
	    ok 0 : boolean
	    err 1 : string
	}
    }

    kick 9 {
	request {
	    uid 0 : integer
	}

	response {
	    ok 0 : boolean
	    err 1 : string
	}
    }
]]

--[[
]]
s2c = [[
    exp_message 1 {
	request {
	    uid 0 : integer
	    exp 1 : integer
	}
    }

    enter_room_message 2 {
	request {
	    roomid 0 : integer
	    uid 1 : integer
	    username 2 : string
	    exp 3 : integer
	    manager 4 : integer
	}
    }

    leave_room_message 3 {
	request {
	    roomid 0 : integer
	    uid 1 : integer
	    username 2 : string
	    manager 3 : integer
	}
    }

    member_exp_message 4 {
	request {
	    roomid 0 : integer
	    member 1 : *user(uid)
	}
    }

    talk_message 5 {
	request {
	    from_uid 0 : integer
	    to_uid 1 : integer
	    content 2 : string
	}
    }

    send_exp_message 6 {
	request {
	    from_uid 0 : integer
	    to_uid 1 : integer
	    exp 2 : integer
	    manager 3 : integer
	}
    }

    kick_message 7 {
	request {
	    from_uid 0 : integer
	    kick_uid 1 : integer
	}
    }
]]

proto.types = sprotoparser.parse(types)
proto.c2s = sprotoparser.parse(types .. c2s)
proto.s2c = sprotoparser.parse(types .. s2c)

return proto
