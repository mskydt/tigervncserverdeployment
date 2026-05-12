# TigerVNC Server on Lubuntu — Deployment Guide

> Homelab reference — Proxmox jump VM  
> Tested on Lubuntu 24.04 LTS

---

## Overview

This guide covers deploying TigerVNC as a persistent, auto-starting VNC server on a Lubuntu VM in Proxmox. The VM acts as a graphical jump host accessible over LAN or via SSH tunnel.

---

## Quick Deploy (via script)

```bash
# Download and run
curl -O https://raw.githubusercontent.com/<your-repo>/main/deploy-tigervnc.sh
sudo bash deploy-tigervnc.sh
```

The script handles all steps below automatically.

---

## Manual Deployment

### 1. Install TigerVNC

```bash
sudo apt update
sudo apt install -y tigervnc-standalone-server tigervnc-common ufw
```

### 2. Set VNC Password

```bash
vncpasswd
```

Password is stored in `~/.vnc/passwd`. You will be prompted for it when connecting.

### 3. Configure xstartup

Create `~/.vnc/xstartup` to launch the LXQt desktop:

```bash
nano ~/.vnc/xstartup
```

```sh
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
exec startlxqt
```

```bash
chmod +x ~/.vnc/xstartup
```

> The two `unset` lines clear environment variables that can bleed in from
> an existing session and silently cause a grey/blank screen.

### 4. Test Manually First

Before setting up systemd, verify the desktop loads:

```bash
vncserver :1 -geometry 1280x800 -depth 24 -SecurityTypes VncAuth -localhost no
```

Connect from your workstation using TigerVNC Viewer to `<vm-ip>:5901`.  
Once confirmed working, kill the session before proceeding:

```bash
vncserver -kill :1
```

### 5. Create systemd Service

```bash
sudo nano /etc/systemd/system/vncserver@.service
```

```ini
[Unit]
Description=TigerVNC Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=mads
Group=mads
WorkingDirectory=/home/mads
Environment=DBUS_SESSION_BUS_ADDRESS=autolaunch:
ExecStartPre=-/usr/bin/vncserver -kill :%i
ExecStart=/usr/bin/vncserver :%i -geometry 1280x800 -depth 24 -SecurityTypes VncAuth -localhost no -fg
ExecStop=/usr/bin/vncserver -kill :%i
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Key design decisions:

| Setting | Reason |
|---|---|
| `Type=simple` + `-fg` | Keeps vncserver in foreground so systemd tracks the process correctly |
| `ExecStartPre=-` | The `-` prefix tells systemd to ignore failure (cleans up stale locks) |
| `Environment=DBUS_SESSION_BUS_ADDRESS=autolaunch:` | Fixes "connection to bus can't be made" error at boot |
| `Restart=on-failure` | Auto-recovers if vncserver crashes |
| `-localhost no` | Allows connections from LAN, not just loopback |
| `-SecurityTypes VncAuth` | Ensures password auth works with all VNC clients |

### 6. Enable User Lingering

```bash
sudo loginctl enable-linger mads
```

Without this, the user session (and D-Bus) doesn't exist at boot, causing the service to fail even when enabled.

### 7. Open Firewall Port

```bash
sudo ufw allow 5901/tcp
sudo ufw status numbered
```

### 8. Enable and Start Service

```bash
sudo systemctl daemon-reload
sudo systemctl enable vncserver@1.service
sudo systemctl start vncserver@1.service
sudo systemctl status vncserver@1.service
```

---

## Connecting

### Direct LAN

In TigerVNC Viewer connect to:

```
<vm-ip>:5901
```

### Via SSH Tunnel (recommended for security)

```bash
ssh -L 5901:localhost:5901 mads@<vm-ip>
```

Then connect TigerVNC Viewer to `localhost:5901`.

> Use SSH tunnel when connecting over any untrusted network.
> Direct LAN is acceptable within a trusted home/homelab network.

---

## Display / Port Mapping

| Display | Port |
|---|---|
| `:1` | `5901` |
| `:2` | `5902` |

The `@.service` template supports multiple displays — just start `vncserver@2.service` for a second session.

---

## Troubleshooting

### Service fails to start

```bash
journalctl -xeu vncserver@1.service --no-pager
```

### Stale lock files (after unclean shutdown)

```bash
vncserver -kill :1 --force
rm -f /tmp/.X1-lock
rm -f /tmp/.X11-unix/X1
sudo systemctl start vncserver@1.service
```

### Grey/blank screen on connect

- Verify `~/.vnc/xstartup` exists and is executable
- Confirm LXQt is installed: `sudo apt install lxqt`
- Check the two `unset` lines are present in xstartup

### "Connection refused (61)"

- Service is not running or not listening externally
- Check: `ss -tlnp | grep 5901`
- Ensure `-localhost no` flag is in the service ExecStart line

### "Connection to bus can't be made"

- `loginctl enable-linger <username>` not set
- `DBUS_SESSION_BUS_ADDRESS=autolaunch:` missing from service Environment

---

## Useful Commands

```bash
# Service status
sudo systemctl status vncserver@1.service

# Restart service
sudo systemctl restart vncserver@1.service

# View logs
journalctl -xeu vncserver@1.service --no-pager

# List active VNC sessions
vncserver -list

# Kill a session manually
vncserver -kill :1

# Check open ports
sudo ufw status numbered
ss -tlnp | grep 5901
```

---

## VM Sizing (Proxmox)

| Resource | Recommended |
|---|---|
| vCPU | 1–2 |
| RAM | 1 GB |
| Disk | 10 GB |
| Network | VirtIO |
| Guest Agent | qemu-guest-agent |

Install guest agent for clean Proxmox integration:

```bash
sudo apt install qemu-guest-agent
sudo systemctl enable --now qemu-guest-agent
```
