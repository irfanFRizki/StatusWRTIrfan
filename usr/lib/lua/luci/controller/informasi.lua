
-- SPDX-License-Identifier: GPL-2.0-or-later
module("luci.controller.informasi", package.seeall)

local fs = require "nixio.fs"

-- Fungsi bantu untuk menyaring pesan agar aman dijadikan argument shell
local function shell_quote(str)
    return "'" .. str:gsub("'", "'\\''") .. "'"
end

-----------------------------------------------------------------------
-- Baca whitelist dari /etc/allowed_ips.conf (format: ip,hostname)
local function read_allowed_ips()
    local allowed_file = "/etc/allowed_ips.conf"
    local ips = {}
    local f = io.open(allowed_file, "r")
    if f then
        for line in f:lines() do
            local ip, hostname = line:match("^%s*([^,]+)%s*,%s*(.-)%s*$")
            if ip and ip ~= "" then
                ips[ip] = hostname or ""
            end
        end
        f:close()
    else
        io.open(allowed_file, "w"):close()
    end
    return ips
end

local function write_allowed_ips(ips_table)
    local f = io.open("/etc/allowed_ips.conf", "w")
    if f then
        for ip, hostname in pairs(ips_table) do
            f:write(ip .. "," .. hostname .. "\n")
        end
        f:close()
    end
end

-----------------------------------------------------------------------
-- Baca kicked IPs
local function read_kicked_ips()
    local file = "/etc/kicked_ips.conf"
    local ips = {}
    local f = io.open(file, "r")
    if f then
        for line in f:lines() do
            local ip = line:match("^%s*(.-)%s*$")
            if ip and ip ~= "" then ips[ip] = true end
        end
        f:close()
    else
        io.open(file, "w"):close()
    end
    return ips
end

local function write_kicked_ips(ips_table)
    local f = io.open("/etc/kicked_ips.conf", "w")
    if f then
        for ip in pairs(ips_table) do f:write(ip .. "\n") end
        f:close()
    end
end

-----------------------------------------------------------------------
-- Baca notified IPs
local function read_notified_ips()
    local file = "/etc/notified_ips.conf"
    local ips = {}
    local f = io.open(file, "r")
    if f then
        for line in f:lines() do
            local ip = line:match("^%s*(.-)%s*$")
            if ip and ip ~= "" then ips[ip] = true end
        end
        f:close()
    else
        io.open(file, "w"):close()
    end
    return ips
end

local function write_notified_ips(ips_table)
    local f = io.open("/etc/notified_ips.conf", "w")
    if f then
        for ip in pairs(ips_table) do f:write(ip .. "\n") end
        f:close()
    end
end

-----------------------------------------------------------------------
-- Dapatkan info device dari online.sh
local function get_device_info(target_ip)
    local hostname, mac = "-", "-"
    local f = io.popen("/usr/bin/online.sh")
    if f then
        local content = f:read("*all")
        f:close()
        for line in content:gmatch("[^\r\n]+") do
            local ip = line:match("IP:%s*([^,]+)")
            if ip == target_ip then
                hostname = line:match("Hostname:%s*([^,]+)") or hostname
                mac      = line:match("MAC:%s*([^,]+)") or mac
                break
            end
        end
    end
    return hostname, mac
end

-----------------------------------------------------------------------
function index()
    entry({"admin","services","informasi"},              template("informasi/informasi"),       _("Informasi Jaringan"),         90.5)
    entry({"admin","services","informasi","data"},       call("action_data"),                   nil)

    entry({"admin","services","informasi","telegram"},   template("informasi/telegram"),        _("Daftar IP Baru"),             91)
    entry({"admin","services","informasi","telegram_data"}, call("action_telegram_data"),       nil)
    entry({"admin","services","informasi","aksi"},       call("action_aksi"),                   nil)

    entry({"admin","services","informasi","info"},       template("informasi/info"),            _("Info"),                       90)

    entry({"admin","services","informasi","allowed"},    template("informasi/allowed"),         _("Daftar IP Diizinkan"),        93)
    entry({"admin","services","informasi","allowed_data"}, call("action_allowed_data"),        nil)
    entry({"admin","services","informasi","allowed","delete"}, call("action_delete_allowed"),   nil)

    entry({"admin","services","informasi","notallowed"}, template("informasi/notallowed"),      _("Daftar IP Tidak Diizinkan"),  94)
    entry({"admin","services","informasi","notallowed_data"}, call("action_notallowed_data"),  nil)
    entry({"admin","services","informasi","notallowed","delete"}, call("action_delete_notallowed"), nil)

    entry({"admin","services","informasi","log"},        template("informasi/log"),             _("Log Telegram"),               95)

    entry({"admin","services","informasi","send_telegram"}, call("action_send_telegram"),       nil).leaf = true
end

-----------------------------------------------------------------------
function action_data()
    local f       = io.popen("/usr/bin/online.sh")
    local content = f and f:read("*all") or "Tidak dapat menjalankan skrip."
    if f then f:close() end
    luci.http.prepare_content("text/plain")
    luci.http.write(content)
end

-----------------------------------------------------------------------
-- Notifikasi IP Baru (HTML mode)
function action_telegram_data()
    local json    = require "luci.jsonc"
    local allowed = read_allowed_ips()
    local kicked  = read_kicked_ips()
    local noted   = read_notified_ips()
    local result  = {}

    for line in io.popen("/usr/bin/online.sh"):lines() do
        if not line:match("^IP,") then
            local ip = line:match("IP:%s*([^,]+)")
            if ip and not allowed[ip] and not kicked[ip] then
                local hn, mac = get_device_info(ip)
                local wifi    = line:match("TERHUBUNG") and "Online" or "Offline"
                if not noted[ip] then
                    local msg = table.concat({
                        "<b>🔔 BOSS, ADA IP BARU!</b>",
                        "══════════════════════════",
                        string.format("<b>Nama Perangkat:</b> %s", hn or "-"),
                        string.format("<b>IP:</b> %s", ip),
                        string.format("<b>MAC:</b> %s", mac),
                        string.format("<b>Status WiFi:</b> %s", wifi),
                        string.format("<b>State:</b> <i>IP BARU</i>"),
                        "══════════════════════════",
                        "<i>Pantau terus di panel admin untuk aksi lebih lanjut</i>"
                    }, "\n")

                    os.execute("/usr/bin/send_telegram.py " .. shell_quote(msg) .. " &")
                    noted[ip] = true
                end
                table.insert(result, { ip = ip, hostname = hn or "", info = line })
            end
        end
    end

    write_notified_ips(noted)
    luci.http.prepare_content("application/json")
    luci.http.write(json.stringify(result))
end

-----------------------------------------------------------------------
-- Aksi allow/kick (HTML mode)
function action_aksi()
    local ip      = luci.http.formvalue("ip")
    local aksi    = luci.http.formvalue("aksi")
    local allowed = read_allowed_ips()
    local kicked  = read_kicked_ips()

    if not ip or not aksi then
        luci.http.status(400, "Parameter tidak lengkap.")
        return luci.http.write("Parameter tidak lengkap.")
    end

    local hn, mac = get_device_info(ip)
    local msg

    if aksi == "allow" then
        os.execute("iptables -D INPUT -s " .. ip .. " -j DROP")
        allowed[ip] = hn
        write_allowed_ips(allowed)
        kicked[ip] = nil; write_kicked_ips(kicked)

        msg = table.concat({
            "<b>✅ IP DIIZINKAN ✅</b>",
            "══════════════════════════",
            string.format("<b>Nama:</b> %s", hn),
            string.format("<b>IP:</b> %s", ip),
            string.format("<b>MAC:</b> %s", mac),
            "<b>Status WiFi:</b> Online",
            "<b>State:</b> <i>DIIZINKAN</i>",
            "══════════════════════════",
            "<i>Device ini dapat akses internet dan akan terus dipantau</i>"
        }, "\n")

    elseif aksi == "kick" then
        os.execute("iptables -I INPUT -s " .. ip .. " -j DROP")
        kicked[ip] = true; write_kicked_ips(kicked)
        allowed[ip] = nil; write_allowed_ips(allowed)

        msg = table.concat({
            "<b>⛔ IP DIBLOKIR ⛔</b>",
            "══════════════════════════",
            string.format("<b>Nama:</b> %s", hn),
            string.format("<b>IP:</b> %s", ip),
            string.format("<b>MAC:</b> %s", mac),
            "<b>Status WiFi:</b> Offline",
            "<b>State:</b> <i>DIBLOKIR</i>",
            "══════════════════════════",
            "<i>Akses internet untuk device ini telah ditutup</i>"
        }, "\n")

    else
        msg = "Aksi tidak dikenal."
    end

    os.execute("/usr/bin/send_telegram.py " .. shell_quote(msg) .. " &")
    luci.http.prepare_content("text/plain")
    luci.http.write(msg)
end

-----------------------------------------------------------------------
-- Daftar IP Diizinkan (JSON)
function action_allowed_data()
    local json    = require "luci.jsonc"
    local allowed = read_allowed_ips()
    local list    = {}
    for ip, hn in pairs(allowed) do
        table.insert(list, { ip = ip, hostname = hn })
    end
    luci.http.prepare_content("application/json")
    luci.http.write(json.stringify(list))
end

-----------------------------------------------------------------------
-- Hapus IP dari whitelist
function action_delete_allowed()
    local ip = luci.http.formvalue("ip")
    if not ip then
        luci.http.status(400, "Parameter tidak lengkap.")
        return luci.http.write("Parameter tidak lengkap.")
    end
    local allowed = read_allowed_ips()
    if allowed[ip] then
        allowed[ip] = nil
        write_allowed_ips(allowed)
        luci.http.prepare_content("text/plain")
        luci.http.write("IP " .. ip .. " telah dihapus dari daftar diizinkan.")
    else
        luci.http.prepare_content("text/plain")
        luci.http.write("IP " .. ip .. " tidak ditemukan dalam daftar diizinkan.")
    end
end

-----------------------------------------------------------------------
-- Daftar IP Tidak Diizinkan (JSON)
function action_notallowed_data()
    local json   = require "luci.jsonc"
    local kicked = read_kicked_ips()
    local result = {}
    for line in io.popen("/usr/bin/online.sh"):lines() do
        if not line:match("^IP,") then
            local ip = line:match("IP:%s*([^,]+)")
            if ip and kicked[ip] then
                local hn = line:match("Hostname:%s*([^,]+)") or "-"
                table.insert(result, { ip = ip, hostname = hn })
            end
        end
    end
    luci.http.prepare_content("application/json")
    luci.http.write(json.stringify(result))
end

-----------------------------------------------------------------------
-- Hapus IP dari kicked list dan buka kembali
function action_delete_notallowed()
    local ip     = luci.http.formvalue("ip")
    if not ip then
        luci.http.status(400, "Parameter tidak lengkap.")
        return luci.http.write("Parameter tidak lengkap.")
    end
    local kicked = read_kicked_ips()
    if kicked[ip] then
        os.execute("iptables -D INPUT -s " .. ip .. " -j DROP")
        kicked[ip] = nil
        write_kicked_ips(kicked)

        local msg = table.concat({
            "🔄 <b>IP DIBUKA KEMBALI</b> 🔄",
            "══════════════════════════",
            string.format("<b>IP:</b> %s", ip),
            "<b>State:</b> <i>DIPANTAU ULANG</i>",
            "══════════════════════════",
            "<i>Device ini akan dipantau dan notifikasi akan aktif kembali</i>"
        }, "\n")

        os.execute("/usr/bin/send_telegram.py " .. shell_quote(msg) .. " &")
        luci.http.prepare_content("text/plain")
        luci.http.write(msg)
    else
        luci.http.prepare_content("text/plain")
        luci.http.write("IP " .. ip .. " tidak ditemukan dalam daftar Tidak Diizinkan.")
    end
end
