#!/bin/bash
# usr/bin/online.sh
# Menampilkan daftar klien DHCP beserta status koneksi realtime
# Maintainer: irfanFRizki
# Repo: https://github.com/irfanFRizki/StatusWRTIrfan

# File leases dan neighbors
LEASES_FILE="/tmp/dhcp.leases"
NEIGH_FILE=$(ip neigh show)

# Cek apakah file leases ada
if [ ! -f "$LEASES_FILE" ]; then
    echo "IP, MAC, Hostname, Status"
    echo "ERROR: File $LEASES_FILE tidak ditemukan"
    exit 1
fi

# Fungsi untuk menentukan prioritas status
get_priority() {
    status=$(echo "$1" | tr '[:lower:]' '[:upper:]' | xargs)
    case "$status" in
        "TERHUBUNG")             echo 1 ;;
        "TERHUBUNG TIDAK AKTIF") echo 2 ;;
        "TIDAK DIKETAHUI")       echo 3 ;;
        "TIDAK TERHUBUNG")       echo 4 ;;
        *)                       echo 5 ;;
    esac
}

# Buat file temporer untuk menyimpan data dengan kunci urutan
temp_file=$(mktemp)

# Simpan hostname dari file leases (gunakan asosiatif array)
declare -A HOSTNAMES

while read -r line; do
    TIMESTAMP=$(echo "$line" | awk '{print $1}')
    MAC=$(echo "$line" | awk '{print $2}')
    IP=$(echo "$line" | awk '{print $3}')
    HOSTNAME=$(echo "$line" | awk '{print $4}')

    if [[ -n "$MAC" ]]; then
        HOSTNAMES["$MAC"]="$HOSTNAME"
    fi

    # Default status
    STATUS="TIDAK TERHUBUNG"

    # Cek apakah IP ada di daftar ip neigh
    if echo "$NEIGH_FILE" | grep -q "$IP"; then
        STATE=$(echo "$NEIGH_FILE" | grep "$IP" | awk '{print $NF}' | tr '[:lower:]' '[:upper:]' | xargs)
        case "$STATE" in
            "REACHABLE") STATUS="TERHUBUNG" ;;
            "STALE")     STATUS="TERHUBUNG TIDAK AKTIF" ;;
            "FAILED")    STATUS="TIDAK TERHUBUNG" ;;
            *)           STATUS="TIDAK DIKETAHUI" ;;
        esac
    fi

    # Pastikan status konsisten
    STATUS=$(echo "$STATUS" | tr '[:lower:]' '[:upper:]' | xargs)

    # Dapatkan nilai prioritas
    priority=$(get_priority "$STATUS")

    # Simpan baris data dengan prefix nilai prioritas
    echo "$priority|$IP|$MAC|${HOSTNAMES[$MAC]:-unknown}|$STATUS" >> "$temp_file"

done < "$LEASES_FILE"

# Output format tergantung parameter
FORMAT="${1:-text}"

if [ "$FORMAT" = "json" ]; then
    # Output JSON untuk LuCI
    echo "["
    first=1
    sort -n -t'|' -k1,1 "$temp_file" | while IFS='|' read -r pri ip mac hostname status; do
        [ "$first" = "0" ] && echo ","
        printf '  {"ip":"%s","mac":"%s","hostname":"%s","status":"%s"}' \
            "$ip" "$mac" "$hostname" "$status"
        first=0
    done
    echo ""
    echo "]"
else
    # Output teks biasa
    echo "IP, MAC, Hostname, Status"
    sort -n -t'|' -k1,1 "$temp_file" | while IFS='|' read -r pri ip mac hostname status; do
        echo "IP: $ip, MAC: $mac, Hostname: $hostname, Status: $status"
    done
fi

# Hapus file temporer
rm -f "$temp_file"
