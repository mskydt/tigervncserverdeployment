#!/bin/bash
# =============================================================================
# deploy-tigervnc.sh
# TigerVNC Server deployment script for Lubuntu (Proxmox VM / jump host)
# Tested on: Lubuntu 24.04 LTS
# Author: Mads Skydt
# =============================================================================

set -e

# --- Configuration -----------------------------------------------------------
VNC_USER="${SUDO_USER:-$(logname)}"
VNC_DISPLAY=1
VNC_PORT=$((5900 + VNC_DISPLAY))
VNC_GEOMETRY="1280x800"
VNC_DEPTH=24
VNC_HOME="/home/${VNC_USER}"
SERVICE_NAME="vncserver@${VNC_DISPLAY}.service"
# -----------------------------------------------------------------------------

echo ""
echo "============================================================"
echo "  TigerVNC Server - Deployment Script"
echo "  User   : ${VNC_USER}"
echo "  Display: :${VNC_DISPLAY}  (port ${VNC_PORT})"
echo "============================================================"
echo ""

# Verify running as root
if [[ $EUID -ne 0 ]]; then
  echo "ERROR: Run this script with sudo."
  echo "  sudo bash deploy-tigervnc.sh"
  exit 1
fi

# --- Step 1: Install packages ------------------------------------------------
echo "[1/7] Installing TigerVNC and LXQt session..."
apt-get update -qq
apt-get install -y tigervnc-standalone-server tigervnc-common ufw

echo "[1/7] Done."

# --- Step 2: Set VNC password ------------------------------------------------
echo ""
echo "[2/7] Setting VNC password for user '${VNC_USER}'..."
echo "      You will be prompted to enter a password (stored in ~/.vnc/passwd)"
sudo -u "${VNC_USER}" vncpasswd
echo "[2/7] Done."

# --- Step 3: Create xstartup -------------------------------------------------
echo ""
echo "[3/7] Creating ~/.vnc/xstartup for LXQt..."
mkdir -p "${VNC_HOME}/.vnc"

cat > "${VNC_HOME}/.vnc/xstartup" << 'EOF'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
exec startlxqt
EOF

chmod +x "${VNC_HOME}/.vnc/xstartup"
chown -R "${VNC_USER}:${VNC_USER}" "${VNC_HOME}/.vnc"
echo "[3/7] Done."

# --- Step 4: Create systemd service ------------------------------------------
echo ""
echo "[4/7] Creating systemd service..."

cat > /etc/systemd/system/vncserver@.service << EOF
[Unit]
Description=TigerVNC Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${VNC_USER}
Group=${VNC_USER}
WorkingDirectory=${VNC_HOME}
Environment=DBUS_SESSION_BUS_ADDRESS=autolaunch:
ExecStartPre=-/usr/bin/vncserver -kill :%i
ExecStart=/usr/bin/vncserver :%i -geometry ${VNC_GEOMETRY} -depth ${VNC_DEPTH} -SecurityTypes VncAuth -localhost no -fg
ExecStop=/usr/bin/vncserver -kill :%i
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

echo "[4/7] Done."

# --- Step 5: Enable user lingering -------------------------------------------
echo ""
echo "[5/7] Enabling user lingering for '${VNC_USER}'..."
loginctl enable-linger "${VNC_USER}"
echo "[5/7] Done."

# --- Step 6: UFW firewall rule ------------------------------------------------
echo ""
echo "[6/7] Adding UFW rule for port ${VNC_PORT}/tcp..."
ufw allow ${VNC_PORT}/tcp
echo "[6/7] Done."

# --- Step 7: Enable and start service ----------------------------------------
echo ""
echo "[7/7] Enabling and starting ${SERVICE_NAME}..."
systemctl daemon-reload
systemctl enable "${SERVICE_NAME}"
systemctl start "${SERVICE_NAME}"

sleep 2
systemctl status "${SERVICE_NAME}" --no-pager

echo ""
echo "============================================================"
echo "  Deployment complete."
echo ""
echo "  Connect from your workstation:"
echo "  -> Direct LAN:  ${VNC_PORT} on this VM's IP"
echo "  -> SSH tunnel:  ssh -L ${VNC_PORT}:localhost:${VNC_PORT} ${VNC_USER}@<vm-ip>"
echo "                  then connect TigerVNC Viewer to localhost:${VNC_PORT}"
echo ""
echo "  Check service status anytime:"
echo "  sudo systemctl status ${SERVICE_NAME}"
echo "============================================================"
echo ""
