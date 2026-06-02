# microsocks-autosetup

A lightweight, snapshot-safe SOCKS5 proxy auto-deployment script for Debian-based systems.  
Built on top of [microsocks](https://github.com/rofl0r/microsocks), this script installs and
configures a SOCKS5 proxy service that dynamically detects the server's IP at each boot —
making it fully compatible with cloud snapshot/clone workflows (e.g., DigitalOcean Droplets,
Vultr snapshots, etc.).

---

## ✨ Features

- **One-command setup** — install, configure, and start SOCKS5 in seconds
- **Snapshot-safe** — bind IP is detected dynamically at every boot, no hardcoded IP
- **systemd integration** — auto-starts on boot with restart-on-failure policy
- **Configurable credentials** — pass root password and SOCKS5 password via CLI flags
- **Debian-based systems only** — Ubuntu, Debian, etc.

---

## 📋 Requirements

| Item | Detail |
|---|---|
| OS | Debian / Ubuntu (any version with `apt`) |
| Privileges | Must be run as `root` |
| Network | Outbound internet access (to install `microsocks`) |

---

## 🚀 Quick Start

### 1. Clone the repository

git clone https://github.com/<your-username>/microsocks-autosetup.git
cd microsocks-autosetup

### 2. Make the script executable

chmod +x setup.sh

### 3. Run with default settings

sudo ./setup.sh

### 4. Run with custom passwords

sudo ./setup.sh -rootpass MyRootPass123 -s5pass MyProxyPass456

---

## ⚙️ Parameters

| Parameter | Description | Default |
|---|---|---|
| `-rootpass` | Set / update the system `root` password | *(not changed)* |
| `-s5pass` | Set the SOCKS5 proxy password | `Bmp0xZoxrs0FpsIQ` |

> ⚠️ **Security Notice:** It is strongly recommended to change the default SOCKS5 password
> before deploying in any production or internet-facing environment.

---

## 📡 Proxy Details After Installation

| Item | Value |
|---|---|
| Protocol | SOCKS5 |
| Listen address | `0.0.0.0:80` |
| Username | `admin` |
| Password | *(as configured via `-s5pass`)* |
| Auto-start | ✅ Enabled via systemd |
| Snapshot-safe | ✅ Yes — IP detected dynamically at boot |

---

## 🔍 How It Works

```text
setup.sh
  │
  ├─ Installs microsocks via apt
  ├─ Writes /usr/local/bin/microsocks-start.sh   ← wrapper script
  │     └─ At each boot: auto-detects external interface & bind IP
  │            via: ip route get 8.8.8.8
  │     └─ Starts microsocks with the detected IP as -b flag
  │
  └─ Registers /etc/systemd/system/microsocks.service
        └─ After=network-online.target (waits for network)
        └─ Restart=always (auto-recover on crash)
