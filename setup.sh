#!/bin/bash
set -e

# Default passwords
ROOT_PASS=""
S5_PASS="sSrEIa7S72z22lTz"

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -rootpass)
      ROOT_PASS="$2"
      shift 2
      ;;
    -s5pass)
      S5_PASS="$2"
      shift 2
      ;;
    *)
      echo "Unknown parameter: $1"
      echo "Usage: $0 [-rootpass ROOT_PASSWORD] [-s5pass SOCKS5_PASSWORD]"
      exit 1
      ;;
  esac
done

# Basic check: must be a Debian-based system
if [[ ! -f /etc/debian_version ]]; then
  echo "This script is intended for Debian-based systems."
  exit 1
fi

echo "[*] Updating apt index..."
apt-get update -y

echo "[*] Installing microsocks..."
apt-get install -y microsocks

# If a root password was provided, update it
if [[ -n "$ROOT_PASS" ]]; then
  echo "root:${ROOT_PASS}" | chpasswd
  echo "[*] Root password updated."
fi

# ============================================================
# Core change: create a startup wrapper script that dynamically
# detects the current IP at each boot.
# This way, snapshots restored to a new Droplet (with a
# different IP) will still work correctly.
# ============================================================

WRAPPER_SCRIPT="/usr/local/bin/microsocks-start.sh"
echo "[*] Creating wrapper script at ${WRAPPER_SCRIPT} ..."

cat > "$WRAPPER_SCRIPT" <<'WRAPPER_EOF'
#!/bin/bash
set -e

S5_USER="admin"
S5_PASS="__S5_PASS_PLACEHOLDER__"
S5_PORT="80"

# Wait for the network to be ready (up to 60 seconds)
MAX_WAIT=60
WAITED=0
while true; do
  EXTERNAL_INTERFACE=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $5; exit}')
  if [[ -n "$EXTERNAL_INTERFACE" ]]; then
    BIND_IP=$(ip -4 addr show "$EXTERNAL_INTERFACE" 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1)
    if [[ -n "$BIND_IP" ]]; then
      break
    fi
  fi
  if [[ "$WAITED" -ge "$MAX_WAIT" ]]; then
    echo "[!] Timeout waiting for network, starting without -b flag."
    BIND_IP=""
    break
  fi
  sleep 1
  WAITED=$((WAITED + 1))
done

echo "[*] Detected interface: ${EXTERNAL_INTERFACE:-unknown}"
echo "[*] Detected bind IP: ${BIND_IP:-none}"

# Build the startup command
CMD=("/usr/bin/microsocks" "-i" "0.0.0.0" "-p" "$S5_PORT" "-u" "$S5_USER" "-P" "$S5_PASS")

if [[ -n "$BIND_IP" ]]; then
  CMD+=("-b" "$BIND_IP")
fi

echo "[*] Starting microsocks: ${CMD[*]}"
exec "${CMD[@]}"
WRAPPER_EOF

# Replace the placeholder with the actual password in the wrapper script
sed -i "s|__S5_PASS_PLACEHOLDER__|${S5_PASS}|g" "$WRAPPER_SCRIPT"
chmod 755 "$WRAPPER_SCRIPT"

# Create systemd service (calls the wrapper script, not microsocks directly)
SERVICE_FILE="/etc/systemd/system/microsocks.service"
echo "[*] Creating systemd service at ${SERVICE_FILE} ..."

cat > "$SERVICE_FILE" <<'EOF'
[Unit]
Description=MicroSocks SOCKS5 proxy service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/microsocks-start.sh
Restart=always
RestartSec=5
LimitNOFILE=65535

# Prevent excessive log output
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and start the service
systemctl daemon-reload
systemctl enable --now microsocks

# Verify service status
sleep 2
if systemctl is-active --quiet microsocks; then
  echo "[*] microsocks service is running."
else
  echo "[!] Warning: microsocks service may not have started correctly."
  echo "[!] Check with: journalctl -u microsocks -n 20"
fi

# Retrieve the current actual bind info for display
CURRENT_IP=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $5; exit}' | xargs -I{} ip -4 addr show {} 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1)

echo "======================================="
echo "Socks5 proxy setup complete (microsocks)."
echo "Listen:           0.0.0.0:80"
echo "Outbound bind IP: ${CURRENT_IP:-auto}"
echo "Socks5 username:  admin"
echo "Socks5 password:  ${S5_PASS}"
echo ""
echo "Snapshot safe:    YES"
echo "  - IP is detected dynamically at each boot"
echo "  - Service is enabled for auto-start"
if [[ -n "$ROOT_PASS" ]]; then
  echo "Root password has been updated."
fi
echo "======================================="
