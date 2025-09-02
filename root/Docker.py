#!/usr/bin/env python3
import os
import subprocess

# =========================
# Helper Functions
# =========================

def run_cmd(cmd):
    try:
        return subprocess.check_output(cmd, shell=True, stderr=subprocess.STDOUT).decode().strip()
    except subprocess.CalledProcessError as e:
        return e.output.decode().strip()

def docker_installed():
    return run_cmd("command -v docker") != ""

def docker_running():
    return run_cmd("pgrep dockerd") != ""

def container_exists(name):
    return run_cmd(f"docker ps -a --format '{{{{.Names}}}}' | grep -w {name}") != ""

def container_running(name):
    return run_cmd(f"docker ps --format '{{{{.Names}}}}' | grep -w {name}") != ""

def container_exited(name):
    return run_cmd(f"docker ps -a --filter 'status=exited' --format '{{{{.Names}}}}' | grep -w {name}") != ""

def add_firewall_rule(name, port):
    rules = run_cmd("uci show firewall | grep dest_port")
    if port not in rules:
        os.system(f"uci add firewall rule")
        os.system(f"uci set firewall.@rule[-1].name='Allow-{name}'")
        os.system("uci set firewall.@rule[-1].src='lan'")
        os.system(f"uci set firewall.@rule[-1].proto='tcp'")
        os.system(f"uci set firewall.@rule[-1].dest_port='{port}'")
        os.system("uci set firewall.@rule[-1].target='ACCEPT'")
        os.system("uci commit firewall && /etc/init.d/firewall restart")

def remove_firewall_rule(name):
    os.system(f"uci -q delete firewall.@rule[?(@.name=='Allow-{name}')] && uci commit firewall && /etc/init.d/firewall restart")

# =========================
# Install Functions
# =========================

def install_docker():
    if docker_installed():
        if docker_running():
            print("[✔] Docker sudah terinstall & berjalan")
        else:
            print("[!] Docker ada tapi belum berjalan, coba start manual (service dockerd start)")
    else:
        print("[*] Menginstall Docker ...")
        os.system("opkg update && opkg install docker dockerd docker-compose")

def install_dockge():
    if container_exists("dockge"):
        if container_running("dockge"):
            print("[✔] Dockge sudah berjalan")
        elif container_exited("dockge"):
            print("[!] Dockge ada tapi exited, restart ...")
            os.system("docker start dockge")
        else:
            print("[!] Dockge container ada tapi tidak berjalan, starting ...")
            os.system("docker start dockge")
    else:
        print("[*] Menginstall Dockge ...")
        os.system("docker run -d --name dockge --network host "
                  "-v /var/run/docker.sock:/var/run/docker.sock "
                  "-v /root/Dockge/data:/app/data louislam/dockge")
    add_firewall_rule("Dockge", "5001")

def install_myspeed():
    if container_exists("myspeed"):
        if container_running("myspeed"):
            print("[✔] MySpeed sudah berjalan")
        elif container_exited("myspeed"):
            print("[!] MySpeed exited, restart ...")
            os.system("docker start myspeed")
        else:
            os.system("docker start myspeed")
    else:
        print("[*] Menginstall MySpeed ...")
        os.system("docker run -d --name myspeed --network host "
                  "-v myspeed_data:/myspeed/data germannewsmaker/myspeed")
    add_firewall_rule("MySpeed", "5216")

def install_n8n():
    if container_exists("n8n"):
        if container_running("n8n"):
            print("[✔] n8n sudah berjalan")
        elif container_exited("n8n"):
            print("[!] n8n exited, restart ...")
            os.system("docker start n8n")
        else:
            os.system("docker start n8n")
    else:
        print("[*] Menginstall n8n ...")
        os.system("docker run -d --name n8n --network host -v n8n_data:/home/node/.n8n n8nio/n8n")
    add_firewall_rule("n8n", "5678")

# =========================
# Uninstall / Start / Stop
# =========================

def uninstall_service(name, port=None):
    if container_exists(name):
        os.system(f"docker stop {name} && docker rm {name}")
        if port:
            remove_firewall_rule(name)
        print(f"[✔] {name} dihapus")
    else:
        print(f"[!] {name} belum terinstall")

def start_service(name):
    if container_exists(name):
        os.system(f"docker start {name}")
        print(f"[✔] {name} dijalankan")
    else:
        print(f"[!] {name} tidak ada")

def stop_service(name):
    if container_exists(name):
        os.system(f"docker stop {name}")
        print(f"[✔] {name} dihentikan")
    else:
        print(f"[!] {name} tidak ada")

def status_service(name):
    if container_running(name):
        print(f"[✔] {name} berjalan")
    elif container_exited(name):
        print(f"[!] {name} exited")
    elif container_exists(name):
        print(f"[!] {name} ada tapi tidak jalan")
    else:
        print(f"[✘] {name} belum terinstall")

# =========================
# Menu
# =========================

def main_menu():
    while True:
        print("""
=== MENU ===
1) Install Docker
2) Dockge
3) MySpeed
4) n8n
0) Exit
""")
        choice = input("Pilih opsi: ")

        if choice == "1":
            install_docker()
        elif choice == "2":
            service_menu("Dockge", install_dockge, "5001")
        elif choice == "3":
            service_menu("MySpeed", install_myspeed, "5216")
        elif choice == "4":
            service_menu("n8n", install_n8n, "5678")
        elif choice == "0":
            break
        else:
            print("[!] Pilihan tidak valid")

def service_menu(name, install_func, port):
    while True:
        print(f"""
--- {name} ---
1) Install
2) Uninstall
3) Start
4) Stop
5) Status
0) Back
""")
        c = input("Pilih opsi: ")
        if c == "1":
            install_func()
        elif c == "2":
            uninstall_service(name.lower(), port)
        elif c == "3":
            start_service(name.lower())
        elif c == "4":
            stop_service(name.lower())
        elif c == "5":
            status_service(name.lower())
        elif c == "0":
            break
        else:
            print("[!] Pilihan salah")

if __name__ == "__main__":
    main_menu()
