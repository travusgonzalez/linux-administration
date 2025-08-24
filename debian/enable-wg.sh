#!/bin/bash
set -e   # Exit immediately if a command fails

### CONFIGURATION ###
WG_IF="wg0"                   # Name of the WireGuard interface
WG_PORT="51820"                # WireGuard listening port (UDP)
SERVER_IP="10.20.20.1/24"     # Server VPN IP (first usable IP in subnet)
LAN_NET="10.10.10.0/24"       # Your home LAN subnet
DDNS_HOSTNAME="domain.ddns.net"  # DDNS hostname for client Endpoint
DNS="10.10.10.10"             # Default DNS for clients (Pi-hole)

# Notes on network layout:
# - Server: 10.20.20.1
# - Reserved for static/future use: 10.20.20.2–10.20.20.99
# - Client VPNs: start at 10.20.20.100 and increment automatically (handled by config-wg-clients.sh)

### INSTALL WIREGUARD ###
apt update && apt install -y wireguard qrencode   # Install WireGuard and qrencode

mkdir -p /etc/wireguard
cd /etc/wireguard

### GENERATE SERVER KEYS IF MISSING ###
umask 077   # Ensure keys are created with secure permissions
if [ ! -f server_private.key ]; then
    wg genkey | tee server_private.key | wg pubkey > server_public.key
fi

SERVER_PRIVATE=$(cat server_private.key)
SERVER_PUBLIC=$(cat server_public.key)

### CREATE SERVER CONFIG IF MISSING ###
# Creates wg0.conf with basic server settings and NAT rules for internet access
if [ ! -f ${WG_IF}.conf ]; then
cat > /etc/wireguard/${WG_IF}.conf <<EOF
[Interface]
Address = ${SERVER_IP}
SaveConfig = true
PrivateKey = ${SERVER_PRIVATE}
ListenPort = ${WG_PORT}

# NAT for VPN clients to access the internet
PostUp   = iptables -A FORWARD -i ${WG_IF} -j ACCEPT; iptables -A FORWARD -o ${WG_IF} -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i ${WG_IF} -j ACCEPT; iptables -D FORWARD -o ${WG_IF} -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
EOF
fi

### ENABLE IP FORWARDING ###
# Allow VPN traffic to be routed through the server
sysctl -w net.ipv4.ip_forward=1
grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

### ENABLE & START WIREGUARD ###
# Start WireGuard and enable on boot
systemctl enable wg-quick@${WG_IF}
systemctl start wg-quick@${WG_IF}

echo "WireGuard server setup complete."
echo "Server VPN IP: ${SERVER_IP}"
echo "Clients should be created using config-wg-clients.sh, which will automatically use DDNS hostname ${DDNS_HOSTNAME} for the Endpoint."