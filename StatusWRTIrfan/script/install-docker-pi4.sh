#!/bin/bash

# ===================================================================
# n8n One-Click Installer for OpenWRT v24 (Raspberry Pi 4B)
# Dengan Docker dan Dockge
# ===================================================================

set -e

# Warna untuk output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Fungsi untuk print dengan warna
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Banner
echo -e "${BLUE}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║           n8n Installer untuk OpenWRT v24                 ║
║              Raspberry Pi 4B Edition                      ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Cek apakah running sebagai root
if [ "$EUID" -ne 0 ]; then 
    print_error "Script ini harus dijalankan sebagai root!"
    exit 1
fi

# Dapatkan IP address
IP_ADDRESS=$(ip route get 1 | awk '{print $7;exit}')
print_info "IP Address OpenWRT: ${GREEN}$IP_ADDRESS${NC}"

# Konfigurasi
read -p "Masukkan password untuk database PostgreSQL [default: n8npassword123]: " DB_PASSWORD
DB_PASSWORD=${DB_PASSWORD:-n8npassword123}

read -p "Masukkan port untuk n8n [default: 5678]: " N8N_PORT
N8N_PORT=${N8N_PORT:-5678}

read -p "Masukkan port untuk Dockge [default: 5001]: " DOCKGE_PORT
DOCKGE_PORT=${DOCKGE_PORT:-5001}

echo ""
print_info "Aplikasi yang akan diinstall:"
echo "  1. n8n (Workflow Automation)"
echo "  2. Aria2 Pro (Download Manager)"
echo "  3. Jellyfin (Media Server)"
echo "  4. Glances (System Monitoring)"
echo "  5. Dockge (Docker Management)"
echo ""

read -p "Install Aria2 Pro juga? (y/n) [default: y]: " INSTALL_ARIA2
INSTALL_ARIA2=${INSTALL_ARIA2:-y}

if [[ $INSTALL_ARIA2 =~ ^[Yy]$ ]]; then
    read -p "Masukkan RPC Secret untuk Aria2 [default: token]: " ARIA2_SECRET
    ARIA2_SECRET=${ARIA2_SECRET:-token}
    
    read -p "Masukkan port RPC Aria2 [default: 6800]: " ARIA2_RPC_PORT
    ARIA2_RPC_PORT=${ARIA2_RPC_PORT:-6800}
    
    read -p "Masukkan port WebUI Aria2 [default: 6880]: " ARIA2_WEB_PORT
    ARIA2_WEB_PORT=${ARIA2_WEB_PORT:-6880}
    
    read -p "Masukkan port Listen Aria2 [default: 6881]: " ARIA2_LISTEN_PORT
    ARIA2_LISTEN_PORT=${ARIA2_LISTEN_PORT:-6881}
fi

read -p "Install Jellyfin Server juga? (y/n) [default: y]: " INSTALL_JELLYFIN
INSTALL_JELLYFIN=${INSTALL_JELLYFIN:-y}

if [[ $INSTALL_JELLYFIN =~ ^[Yy]$ ]]; then
    read -p "Masukkan port HTTP Jellyfin [default: 8096]: " JELLYFIN_PORT
    JELLYFIN_PORT=${JELLYFIN_PORT:-8096}
fi

read -p "Install Glances (System Monitor)? (y/n) [default: y]: " INSTALL_GLANCES
INSTALL_GLANCES=${INSTALL_GLANCES:-y}

if [[ $INSTALL_GLANCES =~ ^[Yy]$ ]]; then
    read -p "Masukkan port Glances [default: 61208]: " GLANCES_PORT
    GLANCES_PORT=${GLANCES_PORT:-61208}
fi

echo ""
print_info "Memulai instalasi dengan konfigurasi:"
echo "  - Database Password: $DB_PASSWORD"
echo "  - n8n Port: $N8N_PORT"
echo "  - Dockge Port: $DOCKGE_PORT"
if [[ $INSTALL_ARIA2 =~ ^[Yy]$ ]]; then
    echo "  - Aria2 RPC Secret: $ARIA2_SECRET"
    echo "  - Aria2 RPC Port: $ARIA2_RPC_PORT"
    echo "  - Aria2 WebUI Port: $ARIA2_WEB_PORT"
    echo "  - Aria2 Listen Port: $ARIA2_LISTEN_PORT"
fi
if [[ $INSTALL_JELLYFIN =~ ^[Yy]$ ]]; then
    echo "  - Jellyfin Port: $JELLYFIN_PORT"
fi
if [[ $INSTALL_GLANCES =~ ^[Yy]$ ]]; then
    echo "  - Glances Port: $GLANCES_PORT"
fi
echo ""

read -p "Lanjutkan instalasi? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_warning "Instalasi dibatalkan."
    exit 0
fi

# ===================================================================
# 1. Install Docker
# ===================================================================
TOTAL_STEPS=7
if [[ $INSTALL_ARIA2 =~ ^[Yy]$ ]]; then
    TOTAL_STEPS=$((TOTAL_STEPS + 3))
fi
if [[ $INSTALL_JELLYFIN =~ ^[Yy]$ ]]; then
    TOTAL_STEPS=$((TOTAL_STEPS + 3))
fi
if [[ $INSTALL_GLANCES =~ ^[Yy]$ ]]; then
    TOTAL_STEPS=$((TOTAL_STEPS + 2))
fi

CURRENT_STEP=1
print_info "Step $CURRENT_STEP/$TOTAL_STEPS: Mengecek Docker..."

if ! command -v docker &> /dev/null; then
    print_info "Docker tidak ditemukan. Menginstall Docker..."
    opkg update
    opkg install docker dockerd docker-compose luci-app-dockerman
    
    # Start Docker service
    /etc/init.d/dockerd start
    /etc/init.d/dockerd enable
    
    print_success "Docker berhasil diinstall!"
else
    print_success "Docker sudah terinstall."
fi

# Tunggu Docker siap
sleep 3

# ===================================================================
# 2. Install Dockge
# ===================================================================
((CURRENT_STEP++))
print_info "Step $CURRENT_STEP/$TOTAL_STEPS: Mengecek Dockge..."

if docker ps -a | grep -q dockge; then
    print_warning "Dockge sudah terinstall. Melanjutkan..."
else
    print_info "Menginstall Dockge..."
    
    mkdir -p /opt/dockge /opt/stacks
    
    docker run -d \
        --name dockge \
        --restart unless-stopped \
        -p $DOCKGE_PORT:5001 \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v /opt/dockge:/app/data \
        -v /opt/stacks:/opt/stacks \
        -e DOCKGE_STACKS_DIR=/opt/stacks \
        louislam/dockge:1
    
    print_success "Dockge berhasil diinstall!"
fi

# ===================================================================
# 3. Membuat direktori untuk n8n
# ===================================================================
((CURRENT_STEP++))
print_info "Step $CURRENT_STEP/$TOTAL_STEPS: Membuat direktori untuk n8n..."

mkdir -p /opt/stacks/n8n
mkdir -p /opt/appdata/n8n/.n8n
mkdir -p /opt/appdata/n8n/pgdata
mkdir -p /opt/appdata/n8n/db

# Fix permission dengan ownership yang benar
print_info "Mengatur ownership dan permission..."
chown -R 1000:1000 /opt/appdata/n8n/.n8n
chown -R 999:999 /opt/appdata/n8n/pgdata

chmod -R 755 /opt/appdata/n8n/.n8n
chmod -R 700 /opt/appdata/n8n/pgdata

print_success "Direktori berhasil dibuat dengan permission yang benar!"

# ===================================================================
# 4. Membuat init script untuk PostgreSQL
# ===================================================================
((CURRENT_STEP++))
print_info "Step $CURRENT_STEP/$TOTAL_STEPS: Membuat init script database..."

cat > /opt/appdata/n8n/db/init-data.sh << 'EOF'
#!/bin/bash
set -e
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
EOSQL
EOF

chmod +x /opt/appdata/n8n/db/init-data.sh

print_success "Init script database berhasil dibuat!"

# ===================================================================
# 5. Membuat docker-compose.yml
# ===================================================================
((CURRENT_STEP++))
print_info "Step $CURRENT_STEP/$TOTAL_STEPS: Membuat docker-compose.yml..."

cat > /opt/stacks/n8n/docker-compose.yml << EOF
version: '3.8'

services:
  app:
    container_name: n8n
    image: n8nio/n8n:latest
    restart: unless-stopped
    user: "1000:1000"
    ports:
      - $N8N_PORT:5678
    dns:
      - 8.8.8.8
      - 8.8.4.4
      - 1.1.1.1
    volumes:
      - /opt/appdata/n8n/.n8n:/home/node/.n8n
      - /etc/localtime:/etc/localtime:ro
    environment:
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_HOST=db-n8n
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_USER=n8nuser
      - DB_POSTGRESDB_PASSWORD=$DB_PASSWORD
      - N8N_HOST=0.0.0.0
      - N8N_PORT=5678
      - NODE_ENV=production
      - WEBHOOK_URL=http://$IP_ADDRESS:$N8N_PORT/
      - GENERIC_TIMEZONE=Asia/Jakarta
      - TZ=Asia/Jakarta
      # Task runners (recommended)
      - N8N_RUNNERS_ENABLED=true
      # Security settings
      - N8N_BLOCK_ENV_ACCESS_IN_NODE=false
      - N8N_GIT_NODE_DISABLE_BARE_REPOS=true
      # Disable telemetry
      - N8N_DIAGNOSTICS_ENABLED=false
      - N8N_PERSONALIZATION_ENABLED=false
      # Network timeout settings
      - AXIOS_TIMEOUT=60000
      - N8N_DEFAULT_BINARY_DATA_MODE=filesystem
      # Performance tuning
      - N8N_CONCURRENCY_PRODUCTION_LIMIT=10
      - EXECUTIONS_TIMEOUT=300
      - EXECUTIONS_TIMEOUT_MAX=600
    depends_on:
      db-n8n:
        condition: service_healthy

  db-n8n:
    container_name: db-n8n
    image: postgres:14.2
    restart: unless-stopped
    user: "999:999"
    volumes:
      - /opt/appdata/n8n/pgdata:/var/lib/postgresql/data
      - /opt/appdata/n8n/db/init-data.sh:/docker-entrypoint-initdb.d/init-data.sh
    environment:
      - POSTGRES_PASSWORD=$DB_PASSWORD
      - POSTGRES_USER=n8nuser
      - POSTGRES_DB=n8n
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -h localhost -U n8nuser -d n8n"]
      interval: 5s
      timeout: 5s
      retries: 10
EOF

print_success "docker-compose.yml berhasil dibuat!"

# ===================================================================
# 6. Deploy n8n dengan Docker Compose
# ===================================================================
((CURRENT_STEP++))
print_info "Step $CURRENT_STEP/$TOTAL_STEPS: Deploying n8n..."

cd /opt/stacks/n8n
docker-compose up -d

print_success "n8n berhasil di-deploy!"

# ===================================================================
# 7. Install Aria2 Pro (Opsional)
# ===================================================================
if [[ $INSTALL_ARIA2 =~ ^[Yy]$ ]]; then
    ((CURRENT_STEP++))
    print_info "Step $CURRENT_STEP/$TOTAL_STEPS: Membuat direktori untuk Aria2..."
    
    mkdir -p /opt/stacks/aria2
    mkdir -p /opt/appdata/aria2/config
    mkdir -p /opt/downloads
    
    # Set permission untuk Aria2
    chown -R 1000:1000 /opt/appdata/aria2
    chown -R 1000:1000 /opt/downloads
    chmod -R 755 /opt/appdata/aria2
    chmod -R 755 /opt/downloads
    
    print_success "Direktori Aria2 berhasil dibuat!"
    
    # ===================================================================
    # 8. Membuat docker-compose.yml untuk Aria2
    # ===================================================================
    ((CURRENT_STEP++))
    print_info "Step $CURRENT_STEP/$TOTAL_STEPS: Membuat docker-compose.yml untuk Aria2..."
    
    cat > /opt/stacks/aria2/docker-compose.yml << EOF
version: '3.8'

services:
  aria2:
    image: johngong/aria2:latest
    container_name: aria2
    restart: unless-stopped
    network_mode: bridge
    ports:
      - "$ARIA2_LISTEN_PORT:6881"
      - "$ARIA2_LISTEN_PORT:6881/udp"
      - "$ARIA2_RPC_PORT:6800"
      - "$ARIA2_WEB_PORT:8080"
    environment:
      - ARIA2_RPC_SECRET=$ARIA2_SECRET
      - ARIA2_RPC_LISTEN_PORT=6800
      - ARIA2_LISTEN_PORT=6881
      - UID=1000
      - GID=1000
      - UMASK=022
    volumes:
      - /opt/appdata/aria2/config:/config
      - /opt/downloads:/Downloads
    deploy:
      resources:
        reservations:
          memory: 64M
EOF
    
    print_success "docker-compose.yml untuk Aria2 berhasil dibuat!"
    
    # ===================================================================
    # 9. Deploy Aria2 dengan Docker Compose
    # ===================================================================
    ((CURRENT_STEP++))
    print_info "Step $CURRENT_STEP/$TOTAL_STEPS: Deploying Aria2..."
    
    cd /opt/stacks/aria2
    docker-compose up -d
    
    print_success "Aria2 berhasil di-deploy!"
fi

# ===================================================================
# Install Jellyfin Server (Opsional)
# ===================================================================
if [[ $INSTALL_JELLYFIN =~ ^[Yy]$ ]]; then
    ((CURRENT_STEP++))
    print_info "Step $CURRENT_STEP/$TOTAL_STEPS: Membuat direktori untuk Jellyfin..."
    
    mkdir -p /opt/stacks/jellyfin
    mkdir -p /opt/appdata/jellyfin/config
    mkdir -p /opt/appdata/jellyfin/cache
    mkdir -p /opt/media/movies
    mkdir -p /opt/media/tvshows
    mkdir -p /opt/media/music
    mkdir -p /opt/media/photos
    
    # Set permission untuk Jellyfin
    chmod -R 777 /opt/appdata/jellyfin
    chmod -R 777 /opt/media
    
    print_success "Direktori Jellyfin berhasil dibuat!"
    
    # ===================================================================
    # Membuat docker-compose.yml untuk Jellyfin
    # ===================================================================
    ((CURRENT_STEP++))
    print_info "Step $CURRENT_STEP/$TOTAL_STEPS: Membuat docker-compose.yml untuk Jellyfin..."
    
    cat > /opt/stacks/jellyfin/docker-compose.yml << EOF
version: '3.8'

services:
  jellyfin:
    image: jellyfin/jellyfin:latest
    container_name: jellyfin
    restart: unless-stopped
    user: root
    ports:
      - "$JELLYFIN_PORT:8096"
    environment:
      - TZ=Asia/Jakarta
      - JELLYFIN_PublishedServerUrl=http://$IP_ADDRESS:$JELLYFIN_PORT
    volumes:
      - /opt/appdata/jellyfin/config:/config
      - /opt/appdata/jellyfin/cache:/cache
      - /opt/media/movies:/media/movies:ro
      - /opt/media/tvshows:/media/tvshows:ro
      - /opt/media/music:/media/music:ro
      - /opt/media/photos:/media/photos:ro
    privileged: false
    security_opt:
      - no-new-privileges:true
EOF
    
    print_success "docker-compose.yml untuk Jellyfin berhasil dibuat!"
    
    # ===================================================================
    # Deploy Jellyfin dengan Docker Compose
    # ===================================================================
    ((CURRENT_STEP++))
    print_info "Step $CURRENT_STEP/$TOTAL_STEPS: Deploying Jellyfin..."
    
    cd /opt/stacks/jellyfin
    docker-compose up -d
    
    print_success "Jellyfin berhasil di-deploy!"
fi

# ===================================================================
# Install Glances (Opsional)
# ===================================================================
if [[ $INSTALL_GLANCES =~ ^[Yy]$ ]]; then
    ((CURRENT_STEP++))
    print_info "Step $CURRENT_STEP/$TOTAL_STEPS: Membuat docker-compose.yml untuk Glances..."
    
    mkdir -p /opt/stacks/glances
    
    cat > /opt/stacks/glances/docker-compose.yml << EOF
version: '3.8'

services:
  glances:
    image: nicolargo/glances:latest-full
    container_name: glances
    hostname: OpenWRT-Pi4B
    restart: unless-stopped
    privileged: true
    network_mode: host
    pid: host
    ports:
      - $GLANCES_PORT:61208
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
    environment:
      - TZ=Asia/Jakarta
      - GLANCES_OPT=-w
      - DOCKER_HOST=unix:///var/run/docker.sock
    deploy:
      resources:
        reservations:
          memory: 64M
EOF
    
    print_success "docker-compose.yml untuk Glances berhasil dibuat!"
    
    # ===================================================================
    # Deploy Glances dengan Docker Compose
    # ===================================================================
    ((CURRENT_STEP++))
    print_info "Step $CURRENT_STEP/$TOTAL_STEPS: Deploying Glances..."
    
    cd /opt/stacks/glances
    docker-compose up -d
    
    print_success "Glances berhasil di-deploy!"
fi

# ===================================================================
# Konfigurasi Firewall (Opsional)
# ===================================================================
((CURRENT_STEP++))
print_info "Step $CURRENT_STEP/$TOTAL_STEPS: Konfigurasi firewall..."

read -p "Apakah Anda ingin membuka port di firewall? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Buka port n8n
    if ! uci show firewall | grep -q "Allow-n8n"; then
        uci add firewall rule
        uci set firewall.@rule[-1].name='Allow-n8n'
        uci set firewall.@rule[-1].src='wan'
        uci set firewall.@rule[-1].dest_port="$N8N_PORT"
        uci set firewall.@rule[-1].proto='tcp'
        uci set firewall.@rule[-1].target='ACCEPT'
        print_success "Port $N8N_PORT (n8n) berhasil dibuka di firewall!"
    else
        print_warning "Firewall rule untuk n8n sudah ada."
    fi
    
    # Buka port Aria2 jika diinstall
    if [[ $INSTALL_ARIA2 =~ ^[Yy]$ ]]; then
        # Port RPC
        if ! uci show firewall | grep -q "Allow-aria2-rpc"; then
            uci add firewall rule
            uci set firewall.@rule[-1].name='Allow-aria2-rpc'
            uci set firewall.@rule[-1].src='wan'
            uci set firewall.@rule[-1].dest_port="$ARIA2_RPC_PORT"
            uci set firewall.@rule[-1].proto='tcp'
            uci set firewall.@rule[-1].target='ACCEPT'
            print_success "Port $ARIA2_RPC_PORT (Aria2 RPC) berhasil dibuka!"
        fi
        
        # Port WebUI
        if ! uci show firewall | grep -q "Allow-aria2-web"; then
            uci add firewall rule
            uci set firewall.@rule[-1].name='Allow-aria2-web'
            uci set firewall.@rule[-1].src='wan'
            uci set firewall.@rule[-1].dest_port="$ARIA2_WEB_PORT"
            uci set firewall.@rule[-1].proto='tcp'
            uci set firewall.@rule[-1].target='ACCEPT'
            print_success "Port $ARIA2_WEB_PORT (Aria2 WebUI) berhasil dibuka!"
        fi
        
        # Port Listen (TCP & UDP)
        if ! uci show firewall | grep -q "Allow-aria2-listen"; then
            uci add firewall rule
            uci set firewall.@rule[-1].name='Allow-aria2-listen'
            uci set firewall.@rule[-1].src='wan'
            uci set firewall.@rule[-1].dest_port="$ARIA2_LISTEN_PORT"
            uci set firewall.@rule[-1].proto='tcpudp'
            uci set firewall.@rule[-1].target='ACCEPT'
            print_success "Port $ARIA2_LISTEN_PORT (Aria2 Listen) berhasil dibuka!"
        fi
    fi
    
    # Buka port Jellyfin jika diinstall
    if [[ $INSTALL_JELLYFIN =~ ^[Yy]$ ]]; then
        # Port HTTP
        if ! uci show firewall | grep -q "Allow-jellyfin"; then
            uci add firewall rule
            uci set firewall.@rule[-1].name='Allow-jellyfin'
            uci set firewall.@rule[-1].src='wan'
            uci set firewall.@rule[-1].dest_port="$JELLYFIN_PORT"
            uci set firewall.@rule[-1].proto='tcp'
            uci set firewall.@rule[-1].target='ACCEPT'
            print_success "Port $JELLYFIN_PORT (Jellyfin) berhasil dibuka!"
        fi
    fi
    
    # Buka port Glances jika diinstall
    if [[ $INSTALL_GLANCES =~ ^[Yy]$ ]]; then
        if ! uci show firewall | grep -q "Allow-glances"; then
            uci add firewall rule
            uci set firewall.@rule[-1].name='Allow-glances'
            uci set firewall.@rule[-1].src='wan'
            uci set firewall.@rule[-1].dest_port="$GLANCES_PORT"
            uci set firewall.@rule[-1].proto='tcp'
            uci set firewall.@rule[-1].target='ACCEPT'
            print_success "Port $GLANCES_PORT (Glances) berhasil dibuka!"
        fi
    fi
    
    uci commit firewall
    /etc/init.d/firewall restart
fi

# ===================================================================
# Menunggu container siap
# ===================================================================
print_info "Menunggu container siap..."
sleep 10

# ===================================================================
# Verifikasi instalasi
# ===================================================================
echo ""
print_info "Memverifikasi instalasi..."

if docker ps | grep -q "n8n"; then
    print_success "✓ Container n8n running"
else
    print_error "✗ Container n8n tidak running"
fi

if docker ps | grep -q "db-n8n"; then
    print_success "✓ Container db-n8n running"
else
    print_error "✗ Container db-n8n tidak running"
fi

if docker ps | grep -q "dockge"; then
    print_success "✓ Container dockge running"
else
    print_error "✗ Container dockge tidak running"
fi

if [[ $INSTALL_ARIA2 =~ ^[Yy]$ ]]; then
    if docker ps | grep -q "aria2"; then
        print_success "✓ Container aria2 running"
    else
        print_error "✗ Container aria2 tidak running"
    fi
fi

if [[ $INSTALL_JELLYFIN =~ ^[Yy]$ ]]; then
    if docker ps | grep -q "jellyfin"; then
        print_success "✓ Container jellyfin running"
    else
        print_error "✗ Container jellyfin tidak running"
    fi
fi

if [[ $INSTALL_GLANCES =~ ^[Yy]$ ]]; then
    if docker ps | grep -q "glances"; then
        print_success "✓ Container glances running"
    else
        print_error "✗ Container glances tidak running"
    fi
fi

# ===================================================================
# Informasi akses
# ===================================================================
echo ""
echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║            INSTALASI BERHASIL DISELESAIKAN!               ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

echo -e "${BLUE}Akses aplikasi Anda:${NC}"
echo -e "  ${GREEN}n8n:${NC}       http://$IP_ADDRESS:$N8N_PORT"
echo -e "  ${GREEN}Dockge:${NC}    http://$IP_ADDRESS:$DOCKGE_PORT"
if [[ $INSTALL_ARIA2 =~ ^[Yy]$ ]]; then
    echo -e "  ${GREEN}Aria2:${NC}     http://$IP_ADDRESS:$ARIA2_WEB_PORT"
fi
if [[ $INSTALL_JELLYFIN =~ ^[Yy]$ ]]; then
    echo -e "  ${GREEN}Jellyfin:${NC}  http://$IP_ADDRESS:$JELLYFIN_PORT"
fi
if [[ $INSTALL_GLANCES =~ ^[Yy]$ ]]; then
    echo -e "  ${GREEN}Glances:${NC}   http://$IP_ADDRESS:$GLANCES_PORT"
fi
echo ""
echo -e "${BLUE}Informasi Database:${NC}"
echo -e "  Database: n8n"
echo -e "  User: n8nuser"
echo -e "  Password: $DB_PASSWORD"
echo ""
if [[ $INSTALL_ARIA2 =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}Informasi Aria2:${NC}"
    echo -e "  RPC Secret: $ARIA2_SECRET"
    echo -e "  RPC Port: $ARIA2_RPC_PORT"
    echo -e "  WebUI Port: $ARIA2_WEB_PORT"
    echo -e "  Listen Port: $ARIA2_LISTEN_PORT"
    echo -e "  ${YELLOW}Koneksi AriaNg:${NC}"
    echo -e "    - Host: $IP_ADDRESS"
    echo -e "    - Port: $ARIA2_RPC_PORT"
    echo -e "    - Protocol: http"
    echo -e "    - Secret Token: $ARIA2_SECRET"
    echo ""
fi
if [[ $INSTALL_JELLYFIN =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}Informasi Jellyfin Server:${NC}"
    echo -e "  Port: $JELLYFIN_PORT"
    echo -e "  ${YELLOW}Setup Wizard:${NC}"
    echo -e "    Buka http://$IP_ADDRESS:$JELLYFIN_PORT untuk setup awal"
    echo -e "    Ikuti wizard untuk membuat akun admin"
    echo -e "  ${YELLOW}Media Libraries:${NC}"
    echo -e "    - Movies: /media/movies"
    echo -e "    - TV Shows: /media/tvshows"
    echo -e "    - Music: /media/music"
    echo -e "    - Photos: /media/photos"
    echo ""
fi
if [[ $INSTALL_GLANCES =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}Informasi Glances:${NC}"
    echo -e "  Monitoring real-time sistem dan Docker containers"
    echo -e "  Port: $GLANCES_PORT"
    echo ""
fi
echo -e "${BLUE}Perintah berguna:${NC}"
echo -e "  ${YELLOW}n8n:${NC}"
echo -e "    Lihat logs:  docker logs -f n8n"
echo -e "    Stop:        cd /opt/stacks/n8n && docker-compose down"
echo -e "    Start:       cd /opt/stacks/n8n && docker-compose up -d"
echo -e "    Restart:     cd /opt/stacks/n8n && docker-compose restart"
if [[ $INSTALL_ARIA2 =~ ^[Yy]$ ]]; then
    echo -e "  ${YELLOW}Aria2:${NC}"
    echo -e "    Lihat logs:  docker logs -f aria2"
    echo -e "    Stop:        cd /opt/stacks/aria2 && docker-compose down"
    echo -e "    Start:       cd /opt/stacks/aria2 && docker-compose up -d"
    echo -e "    Restart:     cd /opt/stacks/aria2 && docker-compose restart"
fi
if [[ $INSTALL_JELLYFIN =~ ^[Yy]$ ]]; then
    echo -e "  ${YELLOW}Jellyfin:${NC}"
    echo -e "    Lihat logs:  docker logs -f jellyfin"
    echo -e "    Stop:        cd /opt/stacks/jellyfin && docker-compose down"
    echo -e "    Start:       cd /opt/stacks/jellyfin && docker-compose up -d"
    echo -e "    Restart:     cd /opt/stacks/jellyfin && docker-compose restart"
fi
if [[ $INSTALL_GLANCES =~ ^[Yy]$ ]]; then
    echo -e "  ${YELLOW}Glances:${NC}"
    echo -e "    Lihat logs:  docker logs -f glances"
    echo -e "    Stop:        cd /opt/stacks/glances && docker-compose down"
    echo -e "    Start:       cd /opt/stacks/glances && docker-compose up -d"
    echo -e "    Restart:     cd /opt/stacks/glances && docker-compose restart"
fi
echo ""
echo -e "${BLUE}Lokasi data:${NC}"
echo -e "  n8n data:      /opt/appdata/n8n/.n8n"
echo -e "  Database data: /opt/appdata/n8n/pgdata"
echo -e "  Compose file:  /opt/stacks/n8n/docker-compose.yml"
if [[ $INSTALL_ARIA2 =~ ^[Yy]$ ]]; then
    echo -e "  Aria2 config:  /opt/appdata/aria2/config"
    echo -e "  Downloads:     /opt/downloads"
    echo -e "  Compose file:  /opt/stacks/aria2/docker-compose.yml"
fi
if [[ $INSTALL_JELLYFIN =~ ^[Yy]$ ]]; then
    echo -e "  Jellyfin config: /opt/appdata/jellyfin/config"
    echo -e "  Jellyfin cache:  /opt/appdata/jellyfin/cache"
    echo -e "  Media Movies:    /opt/media/movies"
    echo -e "  Media TV:        /opt/media/tvshows"
    echo -e "  Media Music:     /opt/media/music"
    echo -e "  Media Photos:    /opt/media/photos"
    echo -e "  Compose file:    /opt/stacks/jellyfin/docker-compose.yml"
fi
if [[ $INSTALL_GLANCES =~ ^[Yy]$ ]]; then
    echo -e "  Compose file:  /opt/stacks/glances/docker-compose.yml"
fi
echo ""
echo -e "${YELLOW}PENTING:${NC}"
echo -e "  - Simpan password database: ${GREEN}$DB_PASSWORD${NC}"
if [[ $INSTALL_ARIA2 =~ ^[Yy]$ ]]; then
    echo -e "  - Simpan RPC Secret Aria2: ${GREEN}$ARIA2_SECRET${NC}"
    echo -e "  - Setelah akses WebUI Aria2, setup koneksi RPC di AriaNg Settings"
fi
if [[ $INSTALL_JELLYFIN =~ ^[Yy]$ ]]; then
    echo -e "  - Setup Jellyfin: Buka WebUI dan ikuti wizard untuk buat akun admin"
    echo -e "  - Upload media ke /opt/media/* untuk ditambahkan ke library"
fi
if [[ $INSTALL_GLANCES =~ ^[Yy]$ ]]; then
    echo -e "  - Glances: Monitor CPU, RAM, Network, Disk, dan Docker containers"
fi
echo ""
print_success "Selamat menggunakan home server stack Anda!"
echo ""
