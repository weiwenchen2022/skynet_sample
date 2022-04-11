# 基于skynet开发的MUD游戏风格的完整示例
#### 介绍:
	这是一个简单但是完整的项目，展示了[skynet](https://github.com/cloudwu/skynet/)框架的用法。
	这个项目实现了一个多房间服务器，多个客户端可以同时连接到这个服务器，在不同的房间中切换，在房间里公开发言或者单独向某个用户发送信息。
	玩家呆在房间里时可以获得经验值，经验值最多的用户将自动成为房间管理员获得踢其他用户出去的权限。

## 特性
* 登陆服务器，网关服务器，用户代理架构，通讯使用sproto协议
* 登录服务器和网关服务器，使用二字节big-endian指定长度的二进制协议
* 使用一个agent池，缓存和自动回收空闲的agent
* 使用mysql存取用户数据，并对用户定期存档，或在离线和退出登录时自动存档

## 环境要求
mysql服务器监听于3306端口，密码为'root'的root账户
创建一个叫skynet_sample的数据库，并导入skynet_sample.sql

## 测试使用
git clone https://github.com/weiwenchen2022/skynet_sample.git

cd skynet_sample

make

./start.sh

./skynet/3rd/lua/lua client/client.lua username password [robot]

成功连接上后可以使用以下命令与服务器交互:

	login

	logout
	
	list_room
	
	enter_room roomid
	
	leave_room
	
	say content
	
	sayto to_userid content

	send_exp to_userid exp
	
	kick userid