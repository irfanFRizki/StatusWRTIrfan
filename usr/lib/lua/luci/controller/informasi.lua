-- LuCI Controller: Services > Informasi
-- Maintainer: irfanFRizki
-- Repo: https://github.com/irfanFRizki/StatusWRTIrfan
--
-- API Endpoints:
--   ?action=status          → CPU/RAM/Uptime/Hostname
--   ?action=network         → Interface list
--   ?action=storage         → Disk usage
--   ?action=clients         → DHCP clients (dari online.sh)
--   ?action=log             → logread tail
--   ?action=temp            → Suhu RPi
-- Route endpoints:
--   /allowed_data           → JSON list allowed IPs
--   /notallowed_data        → JSON list blocked IPs
--   /telegram_data          → JSON list IP baru (belum diregistrasi)
--   /allowed/delete?ip=...  → Hapus dari allowed
--   /notallowed/delete?ip=. → Buka blokir
--   /aksi?ip=...&aksi=...   → allow / kick IP baru
--   /data                   → Raw teks output online.sh

module("luci.controller.informasi", package.seeall)

-- File paths
local ALLOWED_FILE  = "/etc/allowed_ips.conf"
local KICKED_FILE   = "/etc/kicked_ips.conf"
local NOTIFIED_FILE = "/etc/notified_ips.conf"
local LEASES_FILE   = "/tmp/dhcp.leases"

-- =====================================================
-- Index: Daftarkan semua menu & routes
-- =====================================================
function index()
    -- Menu utama: Services > Informasi
    local e = entry(
        {"admin", "services", "informasi"},
        template("informasi/index"),
        _("Informasi"), 60
    )
    e.dependent = false

    -- Sub menu: Dashboard
    entry({"admin","services","informasi","dashboard"},
        template("informasi/dashboard"), _("Dashboard"), 10).dependent = false

    -- Sub menu: Info (Dashboard monitoring utama)
    entry({"admin","services","informasi","info"},
        template("informasi/info"), _("Monitor"), 15).dependent = false

    -- Sub menu: Klien Online (raw terminal output)
    entry({"admin","services","informasi","informasi"},
        template("informasi/informasi"), _("Data Mentah"), 20).dependent = false

    -- Sub menu: Klien Online (tabel modern)
    entry({"admin","services","informasi","clients"},
        template("informasi/clients"), _("Klien Online"), 25).dependent = false

    -- Sub menu: IP Baru / Telegram approval
    entry({"admin","services","informasi","telegram"},
        template("informasi/telegram"), _("IP Baru"), 30).dependent = false

    -- Sub menu: IP Diizinkan
    entry({"admin","services","informasi","allowed"},
        template("informasi/allowed"), _("IP Diizinkan"), 40).dependent = false

    -- Sub menu: IP Diblokir
    entry({"admin","services","informasi","notallowed"},
        template("informasi/notallowed"), _("IP Diblokir"), 50).dependent = false

    -- Sub menu: System Info
    entry({"admin","services","informasi","system"},
        template("informasi/system"), _("System Info"), 60).dependent = false

    -- Sub menu: Network
    entry({"admin","services","informasi","network"},
        template("informasi/network"), _("Network"), 70).dependent = false

    -- Sub menu: Storage
    entry({"admin","services","informasi","storage"},
        template("informasi/storage"), _("Storage"), 80).dependent = false

    -- === API Routes ===
    -- General API (action-based)
    entry({"admin","services","informasi","api"},
        call("action_api"), nil).leaf = true

    -- Data mentah (teks) dari online.sh
    entry({"admin","services","informasi","data"},
        call("action_data"), nil).leaf = true

    -- Allowed IPs JSON
    entry({"admin","services","informasi","allowed_data"},
        call("action_allowed_data"), nil).leaf = true

    -- Blocked IPs JSON
    entry({"admin","services","informasi","notallowed_data"},
        call("action_notallowed_data"), nil).leaf = true

    -- IP Baru / Telegram data JSON
    entry({"admin","services","informasi","telegram_data"},
        call("action_telegram_data"), nil).leaf = true

    -- Hapus dari allowed
    entry({"admin","services","informasi","allowed","delete"},
        call("action_allowed_delete"), nil).leaf = true

    -- Buka blokir
    entry({"admin","services","informasi","notallowed","delete"},
        call("action_notallowed_delete"), nil).leaf = true

    -- Aksi: allow / kick IP baru
    entry({"admin","services","informasi","aksi"},
        call("action_aksi"), nil).leaf = true
end

-- =====================================================
-- HELPERS: Baca/tulis file conf
-- =====================================================

-- Baca semua baris dari file, kembalikan table
local function read_lines(filepath)
    local lines = {}
    local f = io.open(filepath, "r")
    if f then
        for line in f:lines() do
            local trimmed = line:match("^%s*(.-)%s*$")
            if trimmed and #trimmed > 0 then
                table.insert(lines, trimmed)
            end
        end
        f:close()
    end
    return lines
end

-- Tulis table ke file (satu baris per entry)
local function write_lines(filepath, lines)
    local f = io.open(filepath, "w")
    if f then
        for _, line in ipairs(lines) do
            f:write(line .. "\n")
        end
        f:close()
        return true
    end
    return false
end

-- Cek apakah IP ada di file
local function ip_in_file(filepath, ip)
    local lines = read_lines(filepath)
    for _, line in ipairs(lines) do
        local file_ip = line:match("^([^,]+)")
        if file_ip == ip then return true end
    end
    return false
end

-- Hapus baris yang mengandung IP dari file
local function remove_ip_from_file(filepath, ip)
    local lines = read_lines(filepath)
    local new_lines = {}
    for _, line in ipairs(lines) do
        local file_ip = line:match("^([^,]+)")
        if file_ip ~= ip then
            table.insert(new_lines, line)
        end
    end
    write_lines(filepath, new_lines)
end

-- Parse hostname dari dhcp.leases berdasarkan IP
local function get_hostname_from_leases(ip)
    local f = io.open(LEASES_FILE, "r")
    if not f then return nil end
    for line in f:lines() do
        local parts = {}
        for p in line:gmatch("%S+") do table.insert(parts, p) end
        -- Format: TIMESTAMP MAC IP HOSTNAME
        if parts[3] == ip then
            f:close()
            return parts[4] ~= "*" and parts[4] or nil
        end
    end
    f:close()
    return nil
end

-- Parse MAC dari dhcp.leases berdasarkan IP
local function get_mac_from_leases(ip)
    local f = io.open(LEASES_FILE, "r")
    if not f then return nil end
    for line in f:lines() do
        local parts = {}
        for p in line:gmatch("%S+") do table.insert(parts, p) end
        if parts[3] == ip then
            f:close()
            return parts[2]
        end
    end
    f:close()
    return nil
end

-- Apply iptables block/unblock
local function iptables_drop(ip)
    os.execute("iptables -I FORWARD -s " .. ip .. " -j DROP 2>/dev/null")
    os.execute("iptables -I FORWARD -d " .. ip .. " -j DROP 2>/dev/null")
end

local function iptables_allow(ip)
    os.execute("iptables -D FORWARD -s " .. ip .. " -j DROP 2>/dev/null")
    os.execute("iptables -D FORWARD -d " .. ip .. " -j DROP 2>/dev/null")
end

-- =====================================================
-- ACTION: General API (?action=...)
-- =====================================================
function action_api()
    local http = require("luci.http")
    local sys  = require("luci.sys")
    local json = require("luci.json")

    local action = http.formvalue("action") or "status"

    -- STATUS
    if action == "status" then
        local data = {
            uptime   = sys.uptime(),
            hostname = sys.hostname(),
            loadavg  = sys.loadavg(),
            meminfo  = sys.meminfo(),
        }
        http.prepare_content("application/json")
        http.write(json.encode(data))

    -- NETWORK
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

    -- STORAGE
    elseif action == "storage" then
        local data   = {}
        local handle = io.popen("df -h 2>/dev/null")
        if handle then
            data.df = handle:read("*a")
            handle:close()
        end
        http.prepare_content("application/json")
        http.write(json.encode(data))

    -- CLIENTS (online.sh JSON)
    elseif action == "clients" then
        local clients = {}
        local handle  = io.popen("/usr/bin/online.sh json 2>/dev/null")
        if handle then
            local raw = handle:read("*a")
            handle:close()
            if raw and #raw > 2 then
                local ok, parsed = pcall(json.decode, raw)
                if ok and type(parsed) == "table" then
                    clients = parsed
                end
            end
        end
        -- Fallback: parse teks biasa
        if #clients == 0 then
            local h2 = io.popen("/usr/bin/online.sh 2>/dev/null")
            if h2 then
                local first = true
                for line in h2:lines() do
                    if first then first = false
                    else
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
                    end
                end
                h2:close()
            end
        end
        http.prepare_content("application/json")
        http.write(json.encode(clients))

    -- LOG
    elseif action == "log" then
        local log    = ""
        local handle = io.popen("logread 2>/dev/null | tail -50")
        if handle then
            log = handle:read("*a")
            handle:close()
        end
        http.prepare_content("application/json")
        http.write(json.encode({log = log}))

    -- TEMPERATURE (Raspberry Pi)
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

-- =====================================================
-- ACTION: Raw teks output online.sh
-- =====================================================
function action_data()
    local http   = require("luci.http")
    local handle = io.popen("/usr/bin/online.sh 2>/dev/null")
    local output = ""
    if handle then
        output = handle:read("*a")
        handle:close()
    end
    http.prepare_content("text/plain; charset=utf-8")
    http.write(output)
end

-- =====================================================
-- ACTION: Allowed IPs → JSON
-- =====================================================
function action_allowed_data()
    local http    = require("luci.http")
    local json    = require("luci.json")
    local result  = {}
    local lines   = read_lines(ALLOWED_FILE)

    for _, line in ipairs(lines) do
        local ip, hostname = line:match("^([^,]+),?(.*)")
        if ip then
            table.insert(result, {
                ip       = ip,
                hostname = hostname and #hostname > 0 and hostname or get_hostname_from_leases(ip) or "Unknown",
            })
        end
    end

    http.prepare_content("application/json")
    http.write(json.encode(result))
end

-- =====================================================
-- ACTION: Notallowed (kicked) IPs → JSON
-- =====================================================
function action_notallowed_data()
    local http   = require("luci.http")
    local json   = require("luci.json")
    local result = {}
    local lines  = read_lines(KICKED_FILE)

    for _, line in ipairs(lines) do
        local ip = line:match("^([%d%.]+)")
        if ip then
            table.insert(result, {
                ip       = ip,
                mac      = get_mac_from_leases(ip) or "-",
                hostname = get_hostname_from_leases(ip) or "Unknown",
            })
        end
    end

    http.prepare_content("application/json")
    http.write(json.encode(result))
end

-- =====================================================
-- ACTION: Telegram / IP Baru (notified) → JSON
-- =====================================================
function action_telegram_data()
    local http   = require("luci.http")
    local json   = require("luci.json")
    local result = {}

    -- Baca semua IP dari leases
    local leases_ips = {}
    local f = io.open(LEASES_FILE, "r")
    if f then
        for line in f:lines() do
            local parts = {}
            for p in line:gmatch("%S+") do table.insert(parts, p) end
            if parts[3] then
                leases_ips[parts[3]] = {
                    mac      = parts[2] or "-",
                    hostname = (parts[4] and parts[4] ~= "*") and parts[4] or "Unknown",
                }
            end
        end
        f:close()
    end

    -- Filter IP yang belum di allowed maupun kicked
    for ip, info in pairs(leases_ips) do
        if not ip_in_file(ALLOWED_FILE, ip) and not ip_in_file(KICKED_FILE, ip) then
            table.insert(result, {
                ip       = ip,
                mac      = info.mac,
                hostname = info.hostname,
            })
        end
    end

    http.prepare_content("application/json")
    http.write(json.encode(result))
end

-- =====================================================
-- ACTION: Hapus IP dari allowed
-- =====================================================
function action_allowed_delete()
    local http = require("luci.http")
    local ip   = http.formvalue("ip")

    if not ip or not ip:match("^%d+%.%d+%.%d+%.%d+$") then
        http.status(400, "Bad Request")
        http.write("IP tidak valid")
        return
    end

    remove_ip_from_file(ALLOWED_FILE, ip)
    http.prepare_content("text/plain")
    http.write("IP " .. ip .. " berhasil dihapus dari daftar diizinkan")
end

-- =====================================================
-- ACTION: Hapus IP dari kicked (buka blokir)
-- =====================================================
function action_notallowed_delete()
    local http = require("luci.http")
    local ip   = http.formvalue("ip")

    if not ip or not ip:match("^%d+%.%d+%.%d+%.%d+$") then
        http.status(400, "Bad Request")
        http.write("IP tidak valid")
        return
    end

    remove_ip_from_file(KICKED_FILE, ip)
    iptables_allow(ip)

    http.prepare_content("text/plain")
    http.write("IP " .. ip .. " berhasil dibuka blokirnya")
end

-- =====================================================
-- ACTION: Aksi pada IP baru (allow / kick)
-- =====================================================
function action_aksi()
    local http   = require("luci.http")
    local ip     = http.formvalue("ip")
    local aksi   = http.formvalue("aksi")

    if not ip or not ip:match("^%d+%.%d+%.%d+%.%d+$") then
        http.status(400, "Bad Request")
        http.write("IP tidak valid")
        return
    end

    if aksi == "allow" then
        -- Tambahkan ke allowed, hapus dari kicked jika ada
        if not ip_in_file(ALLOWED_FILE, ip) then
            local hostname = get_hostname_from_leases(ip) or "Unknown"
            local f = io.open(ALLOWED_FILE, "a")
            if f then
                f:write(ip .. "," .. hostname .. "\n")
                f:close()
            end
        end
        remove_ip_from_file(KICKED_FILE, ip)
        remove_ip_from_file(NOTIFIED_FILE, ip)
        iptables_allow(ip)

        http.prepare_content("text/plain")
        http.write("✓ IP " .. ip .. " berhasil diizinkan")

    elseif aksi == "kick" then
        -- Tambahkan ke kicked, hapus dari allowed jika ada
        if not ip_in_file(KICKED_FILE, ip) then
            local f = io.open(KICKED_FILE, "a")
            if f then
                f:write(ip .. "\n")
                f:close()
            end
        end
        remove_ip_from_file(ALLOWED_FILE, ip)
        remove_ip_from_file(NOTIFIED_FILE, ip)
        iptables_drop(ip)

        http.prepare_content("text/plain")
        http.write("✗ IP " .. ip .. " berhasil diblokir")

    else
        http.status(400, "Bad Request")
        http.write("Aksi tidak dikenal: " .. (aksi or "nil"))
    end
end
