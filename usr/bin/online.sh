#!/bin/bash

# File leases dan neighbors
LEASES_FILE="/tmp/dhcp.leases"
NEIGH_FILE=$(ip neigh show)

# Header output
echo "IP, MAC, Hostname, Status"

# Baca daftar perangkat dari DHCP leases
declare -A HOSTNAMES
while read -r line; do
    TIMESTAMP=$(echo "$line" | awk '{print $1}')
    MAC=$(echo "$line" | awk '{print $2}')
    IP=$(echo "$line" | awk '{print $3}')
    HOSTNAME=$(echo "$line" | awk '{print $4}')
    
    # Simpan hostname berdasarkan MAC
    if [[ -n "$MAC" ]]; then
        HOSTNAMES["$MAC"]="$HOSTNAME"
    fi
    
    # Default status (TIDAK TERHUBUNG)
    STATUS="TIDAK TERHUBUNG"
    
    # Cek apakah ada di daftar `ip neigh`
    if echo "$NEIGH_FILE" | grep -q "$IP"; then
        STATE=$(echo "$NEIGH_FILE" | grep "$IP" | awk '{print $NF}')
        
        case "$STATE" in
            REACHABLE) STATUS="TERHUBUNG" ;;
            STALE) STATUS="TERHUBUNG TIDAK AKTIF" ;;
            FAILED) STATUS="TIDAK TERHUBUNG" ;;
            *) STATUS="TIDAK DIKETAHUI" ;;
        esac
    fi

    # Tampilkan data perangkat
    echo "IP: $IP, MAC: $MAC, Hostname: ${HOSTNAMES[$MAC]}, Status: $STATUS"
done < "$LEASES_FILE"