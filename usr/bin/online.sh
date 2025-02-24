#!/bin/bash

# File leases dan neighbors
LEASES_FILE="/tmp/dhcp.leases"
NEIGH_FILE=$(ip neigh show)

# Fungsi untuk menentukan prioritas status
get_priority() {
    # Konversi ke huruf besar dan trim spasi ekstra
    status=$(echo "$1" | tr '[:lower:]' '[:upper:]' | xargs)
    case "$status" in
        "TERHUBUNG") echo 1 ;;
        "TERHUBUNG TIDAK AKTIF") echo 2 ;;
        "TIDAK DIKETAHUI") echo 3 ;;
        "TIDAK TERHUBUNG") echo 4 ;;
        *) echo 5 ;;
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
            "STALE") STATUS="TERHUBUNG TIDAK AKTIF" ;;
            "FAILED") STATUS="TIDAK TERHUBUNG" ;;
            *) STATUS="TIDAK DIKETAHUI" ;;
        esac
    fi

    # Pastikan status konsisten (huruf besar, tanpa spasi ekstra)
    STATUS=$(echo "$STATUS" | tr '[:lower:]' '[:upper:]' | xargs)
    
    # Dapatkan nilai prioritas
    priority=$(get_priority "$STATUS")
    
    # Simpan baris data dengan prefix nilai prioritas
    echo "$priority|IP: $IP, MAC: $MAC, Hostname: ${HOSTNAMES[$MAC]}, Status: $STATUS" >> "$temp_file"
done < "$LEASES_FILE"

# Tampilkan header
echo "IP, MAC, Hostname, Status"

# Urutkan data berdasarkan prioritas dan keluarkan output tanpa prefix
sort -n -t'|' -k1,1 "$temp_file" | cut -d'|' -f2-

# Hapus file temporer
rm "$temp_file"
