module("luci.controller.informasi", package.seeall)
 
local fs = require "nixio.fs"

-- Fungsi bantu untuk menyaring pesan agar aman dijadikan argument shell
local function shell_quote(str)
    return "'" .. str:gsub("'", "'\\''") .. "'"
end

-----------------------------------------------------------------------
-- Fungsi pembantu: Baca whitelist dari /etc/allowed_ips.conf (format: ip,hostname)
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
        f = io.open(allowed_file, "w")
        if f then f:close() end
    end
    return ips
end

-- Simpan whitelist ke /etc/allowed_ips.conf
local function write_allowed_ips(ips_table)
    local allowed_file = "/etc/allowed_ips.conf"
    local f = io.open(allowed_file, "w")
    if f then
        for ip, hostname in pairs(ips_table) do
            f:write(ip .. "," .. hostname .. "\n")
        end
        f:close()
    end
end

-----------------------------------------------------------------------
-- Fungsi pembantu: Baca daftar kicked IP dari /etc/kicked_ips.conf
local function read_kicked_ips()
    local kicked_file = "/etc/kicked_ips.conf"
    local ips = {}
    local f = io.open(kicked_file, "r")
    if f then
        for line in f:lines() do
            local ip = line:match("^%s*(.-)%s*$")
            if ip and ip ~= "" then
                ips[ip] = true
            end
        end
        f:close()
    else
        f = io.open(kicked_file, "w")
        if f then f:close() end
    end
    return ips
end

-- Simpan daftar kicked IP ke /etc/kicked_ips.conf
local function write_kicked_ips(ips_table)
    local kicked_file = "/etc/kicked_ips.conf"
    local f = io.open(kicked_file, "w")
    if f then
        for ip, _ in pairs(ips_table) do
            f:write(ip .. "\n")
        end
        f:close()
    end
end

-----------------------------------------------------------------------
-- Fungsi pembantu: Baca daftar IP yang sudah diberi notifikasi dari /etc/notified_ips.conf
local function read_notified_ips()
    local notified_file = "/etc/notified_ips.conf"
    local ips = {}
    local f = io.open(notified_file, "r")
    if f then
        for line in f:lines() do
            local ip = line:match("^%s*(.-)%s*$")
            if ip and ip ~= "" then
                ips[ip] = true
            end
        end
        f:close()
    else
        f = io.open(notified_file, "w")
        if f then f:close() end
    end
    return ips
end

-- Simpan daftar IP yang sudah diberi notifikasi ke /etc/notified_ips.conf
local function write_notified_ips(ips_table)
    local notified_file = "/etc/notified_ips.conf"
    local f = io.open(notified_file, "w")
    if f then
        for ip, _ in pairs(ips_table) do
            f:write(ip .. "\n")
        end
        f:close()
    end
end

-----------------------------------------------------------------------
function index()
    -- Halaman Info sebagai default (prioritas 90)
    entry({"admin", "services", "informasi"}, alias("admin", "services", "informasi", "info"), _("Informasi Jaringan"), 90)
    entry({"admin", "services", "informasi", "info"}, template("informasi/info"), _("Dashboard"), 91)
    
    -- Data endpoint untuk dashboard
    entry({"admin", "services", "informasi", "data"}, call("action_data"), nil)
    
    -- Menu Daftar IP Baru
    entry({"admin", "services", "informasi", "telegram"}, template("informasi/telegram"), _("IP Tidak Terdaftar"), 92)
    entry({"admin", "services", "informasi", "telegram_data"}, call("action_telegram_data"), nil)
    entry({"admin", "services", "informasi", "aksi"}, call("action_aksi"), nil)
    
    -- Menu Daftar IP Diizinkan
    entry({"admin", "services", "informasi", "allowed"}, template("informasi/allowed"), _("IP Diizinkan"), 93)
    entry({"admin", "services", "informasi", "allowed_data"}, call("action_allowed_data"), nil)
    entry({"admin", "services", "informasi", "allowed", "delete"}, call("action_delete_allowed"), nil)
    
    -- Menu Daftar IP Tidak Diizinkan
    entry({"admin", "services", "informasi", "notallowed"}, template("informasi/notallowed"), _("IP Diblokir"), 94)
    entry({"admin", "services", "informasi", "notallowed_data"}, call("action_notallowed_data"), nil)
    entry({"admin", "services", "informasi", "notallowed", "delete"}, call("action_delete_notallowed"), nil)
    
    -- Menu Log
    entry({"admin", "services", "informasi", "log"}, template("informasi/log"), _("Log Telegram"), 95)
    
    -- Menu Jaringan (data mentah)
    entry({"admin", "services", "informasi", "raw"}, template("informasi/informasi"), _("Data Mentah"), 96)
end

-----------------------------------------------------------------------
-- Fungsi: Ambil data jaringan dari /usr/bin/online.sh
function action_data()
    local content = ""
    local f = io.popen("/usr/bin/online.sh")
    if f then
        content = f:read("*all")
        f:close()
    else
        content = "Tidak dapat menjalankan skrip."
    end
    luci.http.prepare_content("text/plain")
    luci.http.write(content)
end

-----------------------------------------------------------------------
-- Endpoint Notifikasi Telegram untuk IP Baru
function action_telegram_data()
    local json = require "luci.jsonc"
    local allowed_ips = read_allowed_ips()
    local kicked_ips = read_kicked_ips()
    local notified_ips = read_notified_ips()
    local result = {}
    local f = io.popen("/usr/bin/online.sh")
    if f then
        local content = f:read("*all")
        f:close()
        for line in content:gmatch("[^\r\n]+") do
            if not line:match("^IP,") then
                local ip = line:match("IP:%s*([^,]+)")
                if ip and not allowed_ips[ip] and not kicked_ips[ip] then
                    local hostname = line:match("Hostname:%s*([^,]+)")
                    local mac = line:match("MAC:%s*([^,]+)") or "-"
                    local wifiStatus = (line:match("TERHUBUNG") or line:match("Online")) and "Online" or "Offline"
                    if not notified_ips[ip] then
                        local msg = "🔔 **BOSS, ADA IP BARU!** 🔔\n" ..
      "╔══════════════════════════════╗\n" ..
      "📛 Nama Perangkat: " .. (hostname or "-") .. "\n" ..
      "🆔 IP\t\t: " .. ip .. "\n" ..
      "📡 MAC\t\t: " .. mac .. "\n" ..
      "🌐 Status WIFI\t: " .. wifiStatus .. "\n" ..
      "🚩 Status\t\t: **IP BARU**" ..
      "\n╚══════════════════════════════╝\n" ..
      "ℹ️ __Pantau terus di panel admin untuk aksi lebih lanjut__"
                        os.execute("/usr/bin/send_telegram.py " .. shell_quote(msg) .. " &")
                        notified_ips[ip] = true
                    end
                    table.insert(result, { ip = ip, hostname = hostname or "", info = line, mac = mac })
                end
            end
        end
        write_notified_ips(notified_ips)
    end
    luci.http.prepare_content("application/json")
    luci.http.write(json.stringify(result))
end

-----------------------------------------------------------------------
-- Aksi allow/kick untuk IP
function action_aksi()
    local ip = luci.http.formvalue("ip")
    local aksi = luci.http.formvalue("aksi")
    local allowed_ips = read_allowed_ips()
    local kicked_ips = read_kicked_ips()
    local notified_ips = read_notified_ips()
    local msg = ""
    if ip and aksi then
        if aksi == "allow" then
            os.execute("iptables -D INPUT -s " .. ip .. " -j DROP")
            local hostname = "-"
            local mac = "-"
            local f = io.popen("/usr/bin/online.sh")
            if f then
                local content = f:read("*all"); f:close()
                for line in content:gmatch("[^\r\n]+") do
                    if line:match("IP:%s*" .. ip .. "[,\s]") then
                        hostname = line:match("Hostname:%s*([^,]+)") or "-"
                        mac = line:match("MAC:%s*([^,]+)") or "-"
                        break
                    end
                end
            end
            allowed_ips[ip] = hostname; write_allowed_ips(allowed_ips)
            kicked_ips[ip] = nil; write_kicked_ips(kicked_ips)
            notified_ips[ip] = nil; write_notified_ips(notified_ips)
            msg = "✅ **IP DIIZINKAN** ✅\n" ..
      "╔══════════════════════════════╗\n" ..
      "📛 Nama Perangkat: " .. hostname .. "\n" ..
      "🆔 IP\t\t: " .. ip .. "\n" ..
      "📡 MAC\t\t: " .. mac .. "\n" ..
      "🌐 Status WIFI\t: Online\n" ..
      "✅ Status\t\t: **DIIZINKAN**" ..
      "\n╚══════════════════════════════╝\n" ..
      "💡 __Device ini dapat akses internet dan akan terus dipantau__"
            os.execute("/usr/bin/send_telegram.py " .. shell_quote(msg) .. " &")
        elseif aksi == "kick" then
            os.execute("iptables -I INPUT -s " .. ip .. " -j DROP")
            local hostname = "-"
            local mac = "-"
            local f = io.popen("/usr/bin/online.sh")
            if f then
                local content = f:read("*all"); f:close()
                for line in content:gmatch("[^\r\n]+") do
                    if line:match("IP:%s*" .. ip .. "[,\s]") then
                        hostname = line:match("Hostname:%s*([^,]+)") or "-"
                        mac = line:match("MAC:%s*([^,]+)") or "-"
                        break
                    end
                end
            end
            kicked_ips[ip] = true; write_kicked_ips(kicked_ips)
            notified_ips[ip] = nil; write_notified_ips(notified_ips)
            msg = "⛔ **IP DIBLOKIR** ⛔\n" ..
      "╔══════════════════════════════╗\n" ..
      "📛 Nama Perangkat: " .. hostname .. "\n" ..
      "🆔 IP\t\t: " .. ip .. "\n" ..
      "📡 MAC\t\t: " .. mac .. "\n" ..
      "🌐 Status WIFI\t: Offline\n" ..
      "⛔ Status\t\t: **DIBLOKIR**" ..
      "\n╚══════════════════════════════╝\n" ..
      "💡 __Akses internet untuk device ini telah ditutup__"
            os.execute("/usr/bin/send_telegram.py " .. shell_quote(msg) .. " &")
            kicked_ips[ip] = true
            write_kicked_ips(kicked_ips)
            if notified_ips[ip] then
                notified_ips[ip] = nil
                write_notified_ips(notified_ips)
            end
        else
            msg = "Aksi tidak dikenal."
        end
    else
        msg = "Parameter tidak lengkap."
    end
    luci.http.prepare_content("text/plain")
    luci.http.write(msg)
end

-----------------------------------------------------------------------
-- Mengembalikan daftar IP diizinkan (dengan hostname)
function action_allowed_data()
    local json = require "luci.jsonc"
    local allowed_ips = read_allowed_ips()
    local list = {}
    for ip, hostname in pairs(allowed_ips) do
        table.insert(list, { ip = ip, hostname = hostname })
    end
    luci.http.prepare_content("application/json")
    luci.http.write(json.stringify(list))
end

-----------------------------------------------------------------------
-- Menghapus IP dari whitelist
function action_delete_allowed()
    local ip = luci.http.formvalue("ip")
    if ip then
        local allowed_ips = read_allowed_ips()
        if allowed_ips[ip] then
            allowed_ips[ip] = nil
            write_allowed_ips(allowed_ips)
            luci.http.prepare_content("text/plain")
            luci.http.write("IP " .. ip .. " telah dihapus dari daftar diizinkan.")
        else
            luci.http.prepare_content("text/plain")
            luci.http.write("IP " .. ip .. " tidak ditemukan dalam daftar diizinkan.")
        end
    else
        luci.http.status(400, "Parameter tidak lengkap.")
        luci.http.write("Parameter tidak lengkap.")
    end
end

-----------------------------------------------------------------------
-- Mengembalikan daftar IP tidak diizinkan (yang ada di kicked list)
function action_notallowed_data()
    local json = require "luci.jsonc"
    local kicked_ips = read_kicked_ips()
    local result = {}
    local f = io.popen("/usr/bin/online.sh")
    if f then
        local content = f:read("*all")
        f:close()
        for line in content:gmatch("[^\r\n]+") do
            if not line:match("^IP,") then
                local ip = line:match("IP:%s*([^,]+)")
                if ip and kicked_ips[ip] then
                    local hostname = line:match("Hostname:%s*([^,]+)")
                    local mac = line:match("MAC:%s*([^,]+)") or "-"
                    table.insert(result, { ip = ip, hostname = hostname or "", mac = mac })
                end
            end
        end
    end
    luci.http.prepare_content("application/json")
    luci.http.write(json.stringify(result))
end

-----------------------------------------------------------------------
-- Menghapus IP dari daftar Tidak Diizinkan (un-kick: hapus rule iptables dan hapus dari kicked)
function action_delete_notallowed()
    local ip = luci.http.formvalue("ip")
    if ip then
        local kicked_ips = read_kicked_ips()
        if kicked_ips[ip] then
            os.execute("iptables -D INPUT -s " .. ip .. " -j DROP")
            kicked_ips[ip] = nil
            write_kicked_ips(kicked_ips)
            local msg = "🔄 **IP DIBUKA KEMBALI** 🔄\n" ..
      "╔══════════════════════════════╗\n" ..
      "🆔 IP\t\t: " .. ip .. "\n" ..
      "🌐 Status\t\t: **DIPANTAU ULANG**" ..
      "\n╚══════════════════════════════╝\n" ..
      "ℹ️ __Device ini akan dipantau dan notifikasi akan aktif kembali__"
            os.execute("/usr/bin/send_telegram.py " .. shell_quote(msg) .. " &")
            luci.http.prepare_content("text/plain")
            luci.http.write(msg)
        else
            luci.http.prepare_content("text/plain")
            luci.http.write("IP " .. ip .. " tidak ditemukan dalam daftar Tidak Diizinkan.")
        end
    else
        luci.http.status(400, "Parameter tidak lengkap.")
        luci.http.write("Parameter tidak lengkap.")
    end
end