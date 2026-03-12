-- LuCI Controller: Services > Informasi
-- Maintainer: irfanFRizki
-- Package: luci-app-informasi-wrt

module("luci.controller.informasi", package.seeall)

function index()
    -- Menu Services > Informasi
    local e = entry(
        {"admin", "services", "informasi"},
        template("informasi/index"),
        _("Informasi"), 60
    )
    e.dependent = false

    -- Sub menu: Dashboard
    entry(
        {"admin", "services", "informasi", "dashboard"},
        template("informasi/dashboard"),
        _("Dashboard"), 10
    ).dependent = false

    -- Sub menu: System Info
    entry(
        {"admin", "services", "informasi", "system"},
        template("informasi/system"),
        _("System Info"), 20
    ).dependent = false

    -- Sub menu: Network
    entry(
        {"admin", "services", "informasi", "network"},
        template("informasi/network"),
        _("Network"), 30
    ).dependent = false

    -- Sub menu: Storage
    entry(
        {"admin", "services", "informasi", "storage"},
        template("informasi/storage"),
        _("Storage"), 40
    ).dependent = false

    -- API endpoints
    entry({"admin", "services", "informasi", "api"},
        call("action_api"), nil).leaf = true
end

-- API handler untuk data real-time
function action_api()
    local http = require("luci.http")
    local sys  = require("luci.sys")
    local json = require("luci.json")

    local action = http.formvalue("action") or "status"

    if action == "status" then
        local data = {
            uptime    = sys.uptime(),
            hostname  = sys.hostname(),
            loadavg   = sys.loadavg(),
            meminfo   = sys.meminfo(),
        }
        http.prepare_content("application/json")
        http.write(json.encode(data))

    elseif action == "network" then
        local ifaces = {}
        local ubus   = require("ubus")
        local conn   = ubus.connect()
        if conn then
            local status = conn:call("network.interface", "dump", {})
            if status then
                ifaces = status.interface or {}
            end
            conn:close()
        end
        http.prepare_content("application/json")
        http.write(json.encode({interfaces = ifaces}))

    elseif action == "storage" then
        local data   = {}
        local handle = io.popen("df -h 2>/dev/null")
        if handle then
            data.df = handle:read("*a")
            handle:close()
        end
        http.prepare_content("application/json")
        http.write(json.encode(data))
    end
end
