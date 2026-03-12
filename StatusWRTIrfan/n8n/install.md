cara install di openwrt
1. docker
2. dockge
3. n8n
4. aria2

install docker di openwrt
```bash
# Update package list
opkg update

# Install Docker
opkg install docker dockerd docker-compose

# Install dependensi tambahan
opkg install luci-app-dockerman

# Start Docker service
/etc/init.d/dockerd start
/etc/init.d/dockerd enable
```

2. install dockge di openwrt
```bash
# Buat direktori untuk Dockge
mkdir -p /opt/dockge /opt/stacks

# Jalankan Dockge
docker run -d \
  --name dockge \
  --restart unless-stopped \
  -p 5001:5001 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /opt/dockge:/app/data \
  -v /opt/stacks:/opt/stacks \
  -e DOCKGE_STACKS_DIR=/opt/stacks \
  louislam/dockge:1
```

3. install n8n di openwrt
3.1. persiapan untuk n8n
```bash
# Buat direktori untuk n8n (sesuaikan path dari CasaOS ke OpenWRT)
mkdir -p /opt/stacks/n8n
mkdir -p /opt/appdata/n8n/.n8n
mkdir -p /opt/appdata/n8n/pgdata
mkdir -p /opt/appdata/n8n/db

# Buat init script untuk database
cat > /opt/appdata/n8n/db/init-data.sh << 'EOF'
#!/bin/bash
set -e
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
EOSQL
EOF

chmod +x /opt/appdata/n8n/db/init-data.sh
```

3.2. buat Docker Compose File untuk n8n, Buat file docker-compose.yml di /opt/stacks/n8n/:
```bash
version: '3.8'

services:
  app:
    container_name: n8n
    image: n8nio/n8n:1.116.1
    restart: unless-stopped
    user: "1000:1000"  # Tambahkan ini
    ports:
      - 5678:5678
    volumes:
      - /opt/appdata/n8n/.n8n:/home/node/.n8n
    environment:
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_HOST=db-n8n
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_USER=n8nuser
      - DB_POSTGRESDB_PASSWORD=n8npassword123
      - N8N_HOST=0.0.0.0
      - N8N_PORT=5678
      - WEBHOOK_URL=http://[IP-OPENWRT]:5678/
    depends_on:
      db-n8n:
        condition: service_healthy

  db-n8n:
    container_name: db-n8n
    image: postgres:14.2
    restart: unless-stopped
    user: "999:999"  # Tambahkan ini untuk postgres
    volumes:
      - /opt/appdata/n8n/pgdata:/var/lib/postgresql/data
      - /opt/appdata/n8n/db/init-data.sh:/docker-entrypoint-initdb.d/init-data.sh
    environment:
      - POSTGRES_PASSWORD=n8npassword123
      - POSTGRES_USER=n8nuser
      - POSTGRES_DB=n8n
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -h localhost -U n8nuser -d n8n"]
      interval: 5s
      timeout: 5s
      retries: 10
```

3.3. Firewall: Buka port 5678 di firewall OpenWRT jika perlu akses dari network lain
```bash
# Buka port di firewall
uci add firewall rule
uci set firewall.@rule[-1].name='Allow-n8n'
uci set firewall.@rule[-1].src='wan'
uci set firewall.@rule[-1].dest_port='5678'
uci set firewall.@rule[-1].proto='tcp'
uci set firewall.@rule[-1].target='ACCEPT'
uci commit firewall
/etc/init.d/firewall restart
```

3.4. permission direktori
```bash
# Set ownership ke UID 1000 (user node di dalam container)
chown -R 1000:1000 /opt/appdata/n8n/.n8n
chown -R 999:999 /opt/appdata/n8n/pgdata

# Set permission yang benar
chmod -R 755 /opt/appdata/n8n/.n8n
chmod -R 700 /opt/appdata/n8n/pgdata
```

4. install aria2 pro di dockge compose
```bash
name: aria2
services:
  aria2:
    image: johngong/aria2:latest
    container_name: aria2
    deploy:
      resources:
        reservations:
          memory: 64M
    restart: unless-stopped
    network_mode: bridge
    ports:
      - "6881:6881"
      - "6881:6881/udp"
      - "6800:6800"
      - "6880:8080"
    environment:
      - ARIA2_RPC_SECRET=token
      - ARIA2_RPC_LISTEN_PORT=6800
      - ARIA2_LISTEN_PORT=6881
      - UID=1000
      - GID=1000
      - UMASK=022
    volumes:
      - /DATA/AppData/aria2/config:/config
      - /DATA/Downloads:/Downloads

x-casaos:
  architectures:
    - amd64
    - arm
    - arm64
  author: Cp0204
  category: Downloader
  description:
    en_us: Aria2 is a lightweight multi-protocol & multi-source command-line download utility. It supports HTTP/HTTPS, FTP, SFTP, BitTorrent and Metalink.
    zh_cn: Aria2 是一款轻量级的多协议和多源命令行下载工具。它支持 HTTP/HTTPS、FTP、SFTP、BitTorrent 和 Metalink 。
  developer: johngong
  icon: https://cdn.jsdelivr.net/gh/Cp0204/CasaOS-AppStore-Play@main/Apps/aria2/icon.png
  screenshot_link:
    - https://cdn.jsdelivr.net/gh/Cp0204/CasaOS-AppStore-Play@main/Apps/aria2/screenshot-1.png
    - https://cdn.jsdelivr.net/gh/Cp0204/CasaOS-AppStore-Play@main/Apps/aria2/screenshot-2.png
  thumbnail: https://cdn.jsdelivr.net/gh/Cp0204/CasaOS-AppStore-Play@main/Apps/aria2/thumbnail.png
  main: aria2
  tagline:
    en_us: The lightweight multi-protocol & multi-source command-line download utility
    zh_cn: 轻量级的多协议和多源命令行下载工具
  tips:
    before_install:
      en_us: |
        Aria2 itself is a download kernel with no admin panel. This application integrates with WebUI [AriaNg](http://ariang.mayswind.net) for graphical management, but you still **need to set up the AriaNg connection information manually** after installation:

        | Environment | Default | Description |
        | --- | --- | --- |
        | ARIA2_RPC_SECRET | `token` | RPC SecretKey |
        | ARIA2_RPC_LISTEN_PORT | `6800` | RPC Port |

        Alternatively, you can use a mobile app to connect to the management, e.g. [Aria2App](https://github.com/devgianlu/Aria2App).

        **NOTE**: Changes to Aria2 settings using the third-party panel will only be saved for that sub-process, and will not modify the configuration file; if permanently modified, you should manually modify the Aria2 configuration file.
      zh_cn: |
        Aria2 本身是一个下载核心，没有管理面板。本应用集成 WebUI [AriaNg](http://ariang.mayswind.net) 供图形化管理，但安装后你仍然**需要手动设置 AriaNg 连接信息**：

        | 环境变量 | 默认值 | 说明 |
        | --- | --- | --- |
        | ARIA2_RPC_SECRET | `token` | RPC秘钥 |
        | ARIA2_RPC_LISTEN_PORT | `6800` | RPC端口 |

        此外，你也可以使用手机应用连接管理，例如：[Aria2App](https://github.com/devgianlu/Aria2App)。

        **注意**：使用第三方面板对 Aria2 设置的修改只会保存在该次进程中，不会修改配置文件，如果永久修改，你应该手动修改Aria2配置文件。
  title:
    en_us: Aria2
  scheme: http
  hostname: ""
  port_map: "6880"
  index: "/#!/downloading"
```
