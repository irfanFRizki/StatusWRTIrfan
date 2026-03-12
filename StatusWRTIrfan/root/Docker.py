#!/usr/bin/env python3
import os
import subprocess

# ===== Service Config =====
SERVICES = {
    "Dockge": {
        "container": "dockge",
        "image": "louislam/dockge",
        "ports": [5001],
        "firewall": "Allow-Dockge",
        "run": "docker run -d --name dockge --network host -v /var/run/docker.sock:/var/run/docker.sock -v /root/Dockge/data:/app/data louislam/dockge"
    },
    "MySpeed": {
        "container": "myspeed",
        "image": "germannewsmaker/myspeed",
        "ports": [5216],
        "firewall": "Allow-MySpeed",
        "run": "docker run -d --name myspeed --network host -v myspeed_data:/myspeed/data germannewsmaker/myspeed"
    },
    "n8n": {
        "container": "n8n",
        "image": "n8nio/n8n",
        "ports": [5678],
        "firewall": "Allow-n8n",
        "run": "docker run -d --name n8n --network host -v n8n_data:/home/node/.n8n n8nio/n8n"
    }
}

# ===== Helper Functions =====
def run_cmd(cmd):
    try:
        return subprocess.check_output(cmd, shell=True, text=True).strip()
    except subprocess.CalledProcessError:
        return ""

def docker_installed():
    return bool(run_cmd("command -v docker"))

def install_docker():
    if docker_installed():
        print("[✔] Docker sudah terinstall.")
    else:
        print("[...] Menginstall Docker...")
        os.system("opkg update && opkg install docker dockerd docker-compose")

def container_exists(name):
    return bool(run_cmd(f"docker ps -a --format '{{{{.Names}}}}' | grep -w {name}"))

def container_running(name):
    return bool(run_cmd(f"docker ps --format '{{{{.Names}}}}' | grep -w {name}"))

def install_service(svc):
    if not container_exists(svc["container"]):
        print(f"[+] Install {svc['container']} ...")
        os.system(svc["run"])
        add_firewall(svc)
    else:
        if not container_running(svc["container"]):
            print(f"[~] Restarting exited {svc['container']}...")
            os.system(f"docker start {svc['container']}")
        ensure_firewall(svc)

def uninstall_service(svc):
    if container_exists(svc["container"]):
        print(f"[-] Removing {svc['container']}...")
        os.system(f"docker rm -f {svc['container']}")
        remove_firewall(svc)
    else:
        print(f"[i] {svc['container']} belum terinstall.")

def start_service(svc):
    if container_exists(svc["container"]):
        os.system(f"docker start {svc['container']}")
    else:
        print(f"[i] {svc['container']} belum ada, silakan install.")

def stop_service(svc):
    if container_running(svc["container"]):
        os.system(f"docker stop {svc['container']}")
    else:
        print(f"[i] {svc['container']} tidak sedang berjalan.")

def add_firewall(svc):
    for port in svc["ports"]:
        if not firewall_exists(svc["firewall"]):
            os.system(f"uci add firewall rule")
            os.system(f"uci set firewall.@rule[-1].name='{svc['firewall']}'")
            os.system(f"uci set firewall.@rule[-1].src='lan'")
            os.system(f"uci set firewall.@rule[-1].proto='tcp'")
            os.system(f"uci set firewall.@rule[-1].dest_port='{port}'")
            os.system(f"uci set firewall.@rule[-1].target='ACCEPT'")
            os.system("uci commit firewall && /etc/init.d/firewall restart")
            print(f"[✔] Firewall rule {svc['firewall']} ditambahkan.")

def remove_firewall(svc):
    os.system(f"uci show firewall | grep '{svc['firewall']}' | cut -d'.' -f2 | cut -d'=' -f1 | while read id; do uci delete firewall.$id; done")
    os.system("uci commit firewall && /etc/init.d/firewall restart")
    print(f"[✘] Firewall rule {svc['firewall']} dihapus.")

def firewall_exists(rule_name):
    return bool(run_cmd(f"uci show firewall | grep name | grep -w '{rule_name}'"))

def ensure_firewall(svc):
    if not firewall_exists(svc["firewall"]):
        add_firewall(svc)

def auto_heal():
    for svc in SERVICES.values():
        if container_exists(svc["container"]) and not container_running(svc["container"]):
            print(f"[Auto-Heal] Restart {svc['container']} karena exited...")
            os.system(f"docker restart {svc['container']}")

def status_firewall():
    print("\n[Firewall Rules Aktif]")
    for svc in SERVICES.values():
        if firewall_exists(svc["firewall"]):
            print(f"[✔] {svc['firewall']}")
        else:
            print(f"[ ] {svc['firewall']}")

def status_services():
    print("\n[Service Status]")
    for name, svc in SERVICES.items():
        if container_running(svc["container"]):
            print(f"[✔] {name} (Running)")
        elif container_exists(svc["container"]):
            print(f"[~] {name} (Exited)")
        else:
            print(f"[ ] {name} (Not Installed)")

# ===== Menu =====
def menu():
    while True:
        print("\n==== Docker Service Manager ====")
        print("1) Install Docker")
        print("2) Dockge")
        print("3) MySpeed")
        print("4) n8n")
        print("5) Status")
        print("6) Auto-Heal Containers")
        print("0) Exit")
        choice = input("Pilih: ")

        if choice == "1":
            install_docker()

        elif choice in ["2", "3", "4"]:
            svc = list(SERVICES.values())[int(choice) - 2]
            sub = input(f"\n-- {svc['container']} Menu --\n1) Install\n2) Uninstall\n3) Start\n4) Stop\nPilih: ")
            if sub == "1": install_service(svc)
            elif sub == "2": uninstall_service(svc)
            elif sub == "3": start_service(svc)
            elif sub == "4": stop_service(svc)

        elif choice == "5":
            sub = input("\n-- Status Menu --\n1) Firewall\n2) Services\nPilih: ")
            if sub == "1": status_firewall()
            elif sub == "2": status_services()

        elif choice == "6":
            auto_heal()

        elif choice == "0":
            break

        else:
            print("Pilihan tidak valid!")

if __name__ == "__main__":
    menu()
