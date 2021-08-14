-- Copyright (C) 2017 yushi studio <ywb94@qq.com>
-- Licensed to the public under the GNU General Public License v3.
module("luci.controller.shadowsocksr", package.seeall)
local fs=require"nixio.fs"
local http=require"luci.http"
CALL=luci.sys.call
EXEC=luci.sys.exec
function index()
	if not nixio.fs.access("/etc/config/shadowsocksr") then
		call("act_reset")
	end
	local page
	page = entry({"admin", "services", "shadowsocksr"}, alias("admin", "services", "shadowsocksr", "client"), _("bywall"), 10)
	page.dependent = true
	page.acl_depends = { "luci-app-ssr-plus" }
	entry({"admin", "services", "shadowsocksr", "client"}, cbi("shadowsocksr/client"), _("SSR Client"), 10).leaf = true
	entry({"admin", "services", "shadowsocksr", "servers"}, arcombine(cbi("shadowsocksr/servers", {autoapply = true}), cbi("shadowsocksr/client-config")), _("Severs Nodes"), 20).leaf = true
	entry({"admin", "services", "shadowsocksr", "control"}, cbi("shadowsocksr/control"), _("Access Control"), 30).leaf = true
	entry({"admin", "services", "shadowsocksr", "advanced"}, cbi("shadowsocksr/advanced"), _("Advanced Settings"), 50).leaf = true
	entry({"admin", "services", "shadowsocksr", "server"}, arcombine(cbi("shadowsocksr/server"), cbi("shadowsocksr/server-config")), _("SSR Server"), 60).leaf = true
	entry({"admin", "services", "shadowsocksr", "status"}, form("shadowsocksr/status"), _("Status"), 70).leaf = true
	entry({"admin", "services", "shadowsocksr", "check"}, call("check_status"))
	entry({"admin", "services", "shadowsocksr", "checknet"}, call("check_net"))
	entry({"admin", "services", "shadowsocksr", "refresh"}, call("refresh_data"))
	entry({"admin", "services", "shadowsocksr", "subscribe"}, call("subscribe"))
	entry({"admin", "services", "shadowsocksr", "checkport"}, call("check_port"))
	entry({"admin", "services", "shadowsocksr", "log"}, cbi('shadowsocksr/log'), _("Log"), 80).leaf = true
	entry({"admin", "services", "shadowsocksr", "run"}, call("act_status"))
	entry({"admin", "services", "shadowsocksr", "ping"}, call("act_ping"))
	entry({"admin", "services", "shadowsocksr", "reset"}, call("act_reset"))
	entry({"admin", "services", "shadowsocksr", "restart"}, call("act_restart"))
	entry({"admin", "services", "shadowsocksr", "delete"}, call("act_delete"))
	entry({"admin", "services", "shadowsocksr", "cache"}, call("act_cache"))

	 entry({"admin","services","shadowsocksr","getlog"},call("getlog")) 
         entry({"admin","services","shadowsocksr","dellog"},call("dellog")) 
end

function subscribe()
	CALL("/usr/bin/lua /usr/share/shadowsocksr/subscribe.lua >>/var/log/ssrplus.log")
	luci.http.prepare_content("application/json")
	luci.http.write_json({ret = 1})
end

function check_net()
	local r=0
	if CALL("nslookup www."..http.formvalue("url")..".com >/dev/null 2>&1")==0 then
		r=EXEC("curl -m 5 -o /dev/null -sw %{time_starttransfer} www."..http.formvalue("url")..".com | awk '{printf ($1*1000+0.5)}'")
		if r~~="0" then
			r=EXEC("echo -n "..r.." | sed 's/\\..*//'")
			if r=="0" then r="1" end
		end
	end
	http.prepare_content("application/json")
	http.write_json({ret=r})
end
function act_ping()
	local e = {}
	local domain = luci.http.formvalue("domain")
	local port = luci.http.formvalue("port")
	local transport = luci.http.formvalue("transport")
	local wsPath = luci.http.formvalue("wsPath")
	local tls = luci.http.formvalue("tls")
	e.index = luci.http.formvalue("index")
	local iret = CALL("ipset add ss_spec_wan_ac " .. domain .. " 2>/dev/null")
	if transport == "ws" then
		local prefix = tls=='1' and "https://" or "http://"
		local address = prefix..domain..':'..port..wsPath
		local result = EXEC("curl --http1.1 -m 2 -ksN -o /dev/null -w 'time_connect=%{time_connect}\nhttp_code=%{http_code}' -H 'Connection: Upgrade' -H 'Upgrade: websocket' -H 'Sec-WebSocket-Key: SGVsbG8sIHdvcmxkIQ==' -H 'Sec-WebSocket-Version: 13' "..address)
		e.socket = string.match(result,"http_code=(%d+)")=="101"
		e.ping = tonumber(string.match(result, "time_connect=(%d+.%d%d%d)"))*1000
	else
		local socket = nixio.socket("inet", "stream")
		socket:setopt("socket", "rcvtimeo", 3)
		socket:setopt("socket", "sndtimeo", 3)
		e.socket = socket:connect(domain, port)
		socket:close()
		-- 	e.ping = EXEC("ping -c 1 -W 1 %q 2>&1 | grep -o 'time=[0-9]*.[0-9]' | awk -F '=' '{print$2}'" % domain)
		-- 	if (e.ping == "") then
		e.ping = EXEC(string.format("echo -n $(tcping -q -c 1 -i 1 -t 2 -p %s %s 2>&1 | grep -o 'time=[0-9]*' | awk -F '=' '{print $2}') 2>/dev/null", port, domain))
		-- 	end
	end
	if (iret == 0) then
		CALL(" ipset del ss_spec_wan_ac " .. domain)
	end
	luci.http.prepare_content("application/json")
	luci.http.write_json(e)
end

function check_status()
	local e = {}
	e.ret = CALL("/usr/bin/ssr-check www." .. luci.http.formvalue("set") .. ".com 80 3 1")
	luci.http.prepare_content("application/json")
	luci.http.write_json(e)
end


function act_status()
    math.randomseed(os.time())
    local e = {}

    e.global = CALL('busybox ps -w | grep ssrplus- | grep -v grep  >/dev/null ') == 0

    e.pdnsd = CALL('busybox ps -w | grep pdnsds | grep -v grep  >/dev/null ') == 0

    e.udp = CALL('busybox ps -w | grep -ssrplus-reudp | grep -v grep  >/dev/null') == 0

    e.shunt= CALL('busybox ps -w | grep shunt- | grep -v grep  >/dev/null') == 0
    luci.http.prepare_content('application/json')
    luci.http.write_json(e)
end

function refresh_data()
	local set = luci.http.formvalue("set")
	local retstring = loadstring("return " .. EXEC("/usr/bin/lua /usr/share/shadowsocksr/update.lua " .. set))()
	luci.http.prepare_content("application/json")
	luci.http.write_json(retstring)
end

function check_port()
	local retstring = "<br /><br />"
	local s
	local server_name = ""
	local uci = luci.model.uci.cursor()
	local iret = 1
	uci:foreach("shadowsocksr", "servers", function(s)
		if s.alias then
			server_name = s.alias
		elseif s.server and s.server_port then
			server_name = "%s:%s" % {s.server, s.server_port}
		end
		iret = CALL("ipset add ss_spec_wan_ac " .. s.server .. " 2>/dev/null")
		socket = nixio.socket("inet", "stream")
		socket:setopt("socket", "rcvtimeo", 3)
		socket:setopt("socket", "sndtimeo", 3)
		ret = socket:connect(s.server, s.server_port)
		if tostring(ret) == "true" then
			socket:close()
			retstring = retstring .. "<font color = 'green'>[" .. server_name .. "] OK.</font><br />"
		else
			retstring = retstring .. "<font color = 'red'>[" .. server_name .. "] Error.</font><br />"
		end
		if iret == 0 then
			CALL("ipset del ss_spec_wan_ac " .. s.server)
		end
	end)
	luci.http.prepare_content("application/json")
	luci.http.write_json({ret = retstring})
end

function act_reset()
	CALL("/etc/init.d/shadowsocksr reset &")
	luci.http.redirect(luci.dispatcher.build_url("admin", "services", "shadowsocksr"))
end

function act_restart()
	CALL("/etc/init.d/shadowsocksr restart &")
	luci.http.redirect(luci.dispatcher.build_url("admin", "services", "shadowsocksr"))
end

function act_delete()
	CALL("/etc/init.d/shadowsocksr restart &")
	luci.http.redirect(luci.dispatcher.build_url("admin", "services", "shadowsocksr", "servers"))
end

function act_cache()
	local e = {}
	e.ret = CALL("pdnsd-ctl -c /var/etc/ssrplus/pdnsds empty-cache >/dev/null")
	luci.http.prepare_content("application/json")
	luci.http.write_json(e)
end
function getlog()
	logfile="/var/log/ssrplus.log"
	if not fs.access(logfile) then
		http.write("")
		return
	end
	local f=io.open(logfile,"r")
	local a=f:read("*a") or ""
	f:close()
	a=string.gsub(a,"\n$","")
	http.prepare_content("text/plain; charset=utf-8")
	http.write(a)
end

function dellog()
	fs.writefile("/var/log/ssrplus.log","")
	http.prepare_content("application/json")
	http.write('')
end