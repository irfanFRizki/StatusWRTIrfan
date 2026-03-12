-- LuCI Controller: Services > Informasi
-- Maintainer: irfanFRizki
-- Package: luci-app-informasi-wrt

module("luci.controller.informasi", package.seeall)

function index()
    -- Menu utama: Services > Informasi
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

    -- Sub menu: Klien Online ← BARU
    entry(
        {"admin", "services", "informasi", "clients"},
        template("informasi/clients"),
        _("Klien Online"), 20
    ).dependent = false

    -- Sub menu: System Info
    entry(
        {"admin", "services", "informasi", "system"},
        template("informasi/system"),
        _("System Info"), 30
    ).dependent = false

    -- Sub menu: Network
    entry(
        {"admin", "services", "informasi", "network"},
        template("informasi/network"),
        _("Network"), 40
    ).dependent = false

    -- Sub menu: Storage
    entry(
        {"admin", "services", "informasi", "storage"},
        template("informasi/storage"),
        _("Storage"), 50
    ).dependent = false

    -- API endpoint (leaf = tanpa sub-entry lagi)
    entry({"admin", "services", "informasi", "api"},
        call("action_api"), nil).leaf = true
end

-- =====================================================
-- API Handler
-- =====================================================
function action_api()
    local http = require("luci.http")
    local sys  = require("luci.sys")
    local json = require("luci.json")

    local action = http.formvalue("action") or "status"

    -- ── STATUS (CPU / Memory / Uptime / Hostname) ──────────
    if action == "status" then
        local data = {
            uptime   = sys.uptime(),
            hostname = sys.hostname(),
            loadavg  = sys.loadavg(),
            meminfo  = sys.meminfo(),
        }
        http.prepare_content("application/json")
        http.write(json.encode(data))

    -- ── NETWORK INTERFACES ─────────────────────────────────
    elseif action == "network" then
        local ifaces = {}
        local ubus   = require("ubus")
        local conn   = ubus.connect()
        if conn then
            local status = conn:call("network.interface", "dump", {})
            if status then ifaces = status.interface or {} end
            conn:close()
        end
        http.prepare_content("application/json")
        http.write(json.encode({interfaces = ifaces}))

    -- ── STORAGE (df -h) ────────────────────────────────────
    elseif action == "storage" then
        local data   = {}
        local handle = io.popen("df -h 2>/dev/null")
        if handle then
            data.df = handle:read("*a")
            handle:close()
        end
        http.prepare_content("application/json")
        http.write(json.encode(data))

    -- ── CLIENTS ONLINE (online.sh) ←── BARU ───────────────
    elseif action == "clients" then
        local clients = {}
        -- Jalankan online.sh dengan output JSON
        local handle = io.popen("/usr/bin/online.sh json 2>/dev/null")
        if handle then
            local raw = handle:read("*a")
            handle:close()
            -- Parse JSON dari output script
            if raw and #raw > 2 then
                local ok, parsed = pcall(json.decode, raw)
                if ok and type(parsed) == "table" then
                    clients = parsed
                end
            end
        end
        -- Fallback: parse teks biasa jika JSON gagal
        if #clients == 0 then
            local h2 = io.popen("/usr/bin/online.sh 2>/dev/null")
            if h2 then
                local first = true
                for line in h2:lines() do
                    if first then first = false; goto continue end -- skip header
                    -- Format: IP: x.x.x.x, MAC: xx:xx, Hostname: name, Status: STATUS
                    local ip  = line:match("IP: ([%d%.]+)")
                    local mac = line:match("MAC: ([%x:]+)")
                    local hn  = line:match("Hostname: ([^,]+)")
                    local st  = line:match("Status: (.+)$")
                    if ip then
                        table.insert(clients, {
                            ip       = ip,
                            mac      = mac or "",
                            hostname = hn and hn:gsub("%s+$","") or "unknown",
                            status   = st and st:gsub("%s+$","") or "TIDAK DIKETAHUI",
                        })
                    end
                    ::continue::
                end
                h2:close()
            end
        end
        http.prepare_content("application/json")
        http.write(json.encode(clients))

    -- ── SYSTEM LOG ─────────────────────────────────────────
    elseif action == "log" then
        local log    = ""
        local handle = io.popen("logread 2>/dev/null | tail -50")
        if handle then
            log = handle:read("*a")
            handle:close()
        end
        http.prepare_content("application/json")
        http.write(json.encode({log = log}))

    -- ── TEMPERATURE (Raspberry Pi) ─────────────────────────
    elseif action == "temp" then
        local temp   = nil
        local handle = io.open("/sys/class/thermal/thermal_zone0/temp", "r")
        if handle then
            local raw = handle:read("*n")
            handle:close()
            if raw then temp = math.floor(raw / 1000) end
        end
        http.prepare_content("application/json")
        http.write(json.encode({temp = temp}))
    end
end
