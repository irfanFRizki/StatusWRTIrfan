#!/usr/bin/env python3
import os

DOCKGE_NAME = "dockge"
MYSPEED_NAME = "myspeed"
N8N_NAME = "n8n"

def run_cmd(cmd):
    print(f"\n>>> {cmd}")
    os.system(cmd)

# === Installers ===
def install_docker():
    print("\n=== Install Docker ===")
    run_cmd("opkg update && opkg install docker dockerd docker-compose")
    run_cmd("/etc/init.d/dockerd enable && /etc/init.d/dockerd start")

def install_dockge():
    run_cmd(f"docker run -d --name {DOCKGE_NAME} --network host "
            "-v /var/run/docker.sock:/var/run/docker.sock "
            "-v /root/Dockge/data:/app/data "
            "louislam/dockge")
    add_firewall("Dockge", "5001")

def install_myspeed():
    run_cmd(f"docker run -d --name {MYSPEED_NAME} --network host "
            "-v myspeed_data:/myspeed/data germannewsmaker/myspeed")
    add_firewall("MySpeed", "5216")

def install_n8n():
    run_cmd(f"docker run -d --name {N8N_NAME} --network host "
            "-v /root/n8n:/home/node/.n8n n8nio/n8n")
    add_firewall("n8n", "5678")

# === Uninstallers ===
def uninstall_service(name, rule):
    run_cmd(f"docker stop {name} || true")
    run_cmd(f"docker rm {name} || true")
    run_cmd(f"uci -q delete firewall.{rule}")
    run_cmd("uci commit firewall && /etc/init.d/firewall restart")

def uninstall_all():
    uninstall_service(DOCKGE_NAME, "Allow-Dockge")
    uninstall_service(MYSPEED_NAME, "Allow-MySpeed")
    uninstall_service(N8N_NAME, "Allow-n8n")

# === Control ===
def start_service(name):
    run_cmd(f"docker start {name}")

def stop_service(name):
    run_cmd(f"docker stop {name}")

def restart_services():
    for name in [DOCKGE_NAME, MYSPEED_NAME, N8N_NAME]:
        run_cmd(f"docker restart {name} || true")

# === Status ===
def status():
    print("\n=== Status Container ===")
    run_cmd("docker ps -a")
    print("\n=== Status Firewall Rules ===")
    run_cmd("uci show firewall | grep Allow")

# === Firewall ===
def add_firewall(name, port):
    run_cmd("uci add firewall rule")
    run_cmd(f"uci set firewall.@rule[-1].name='Allow-{name}'")
    run_cmd("uci set firewall.@rule[-1].src='lan'")
    run_cmd("uci set firewall.@rule[-1].proto='tcp'")
    run_cmd(f"uci set firewall.@rule[-1].dest_port='{port}'")
    run_cmd("uci set firewall.@rule[-1].target='ACCEPT'")
    run_cmd("uci commit firewall && /etc/init.d/firewall restart")

# === Submenu ===
def service_menu(name, install_func, rule):
    while True:
        print(f"""
==== {name} Menu ====
1) Install {name}
2) Uninstall {name}
3) Start {name}
4) Stop {name}
0) Kembali
""")
        choice = input(f"Pilih opsi {name}: ")
        if choice == "1":
            install_func()
        elif choice == "2":
            uninstall_service(name.lower(), rule)
        elif choice == "3":
            start_service(name.lower())
        elif choice == "4":
            stop_service(name.lower())
        elif choice == "0":
            break
        else:
            print("Pilihan tidak valid!")

# === Main Menu ===
def menu():
    while True:
        print("""
========================
  Docker Management Menu
========================
1) Install Docker
2) Dockge
3) MySpeed
4) n8n
5) Uninstall Semua
6) Status
7) Restart Semua
0) Exit
""")
        choice = input("Pilih opsi: ")

        if choice == "1":
            install_docker()
        elif choice == "2":
            service_menu("Dockge", install_dockge, "Allow-Dockge")
        elif choice == "3":
            service_menu("MySpeed", install_myspeed, "Allow-MySpeed")
        elif choice == "4":
            service_menu("n8n", install_n8n, "Allow-n8n")
        elif choice == "5":
            uninstall_all()
        elif choice == "6":
            status()
        elif choice == "7":
            restart_services()
        elif choice == "0":
            print("Keluar...")
            break
        else:
            print("Pilihan tidak valid!")

if __name__ == "__main__":
    menu()
