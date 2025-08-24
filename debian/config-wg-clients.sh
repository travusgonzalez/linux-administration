#!/bin/bash
set -e

### CONFIGURATION ###
WG_IF="wg0"
WG_PORT="51820"
VPN_NET="10.20.20.0/24"
SERVER_IP="10.20.20.1/24"
DNS="10.10.10.10"        # Pi-hole or other DNS
CLIENT_START=100          # first client IP for dynamic clients
RESERVED_START=2          # start of reserved range
RESERVED_END=99           # end of reserved range

WG_CONF_DIR="/etc/wireguard"
DDNS_HOSTNAME="domain.ddns.net"  # Use DDNS hostname for WireGuard endpoint

### USAGE FUNCTION ###
usage() {
    echo "Usage: $0 [-c client1 client2 ...]"
    echo
    echo "Options:"
    echo "  -c    Specify one or more client names separated by space"
    echo "  -h    Show this help message"
    echo
    echo "Example:"
    echo "  $0 -c alice bob charlie"
    exit 1
}

### PARSE ARGUMENTS ###
if [ $# -eq 0 ]; then
    usage
fi

while getopts ":c:h" opt; do
    case $opt in
        c)
            CLIENT_NAMES=($OPTARG "${@:OPTIND}")  # capture all client names
            break
            ;;
        h)
            usage
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            usage
            ;;
    esac
done

# Check server config exists
if [ ! -f "${WG_CONF_DIR}/${WG_IF}.conf" ]; then
    echo "Server config not found at ${WG_CONF_DIR}/${WG_IF}.conf. Run the main setup first."
    exit 1
fi

echo "Using DDNS hostname for Endpoint: $DDNS_HOSTNAME"

# Detect main network interface for NAT
MAIN_IF=$(ip route | grep '^default' | awk '{print $5}')
if [[ -z "$MAIN_IF" ]]; then
    echo "Unable to detect main network interface. Please set it manually in NAT rules."
    exit 1
fi
echo "Detected main network interface: $MAIN_IF"

# Build list of all used IP suffixes
USED_SUFFIXES=()
for ip in $(grep AllowedIPs "${WG_CONF_DIR}/${WG_IF}.conf" | cut -d'=' -f2 | cut -d'/' -f1 | cut -d'.' -f4); do
    USED_SUFFIXES+=($ip)
done

# Add reserved range
for ((i=RESERVED_START;i<=RESERVED_END;i++)); do
    USED_SUFFIXES+=($i)
done

NEXT_IP_SUFFIX=$CLIENT_START

for CLIENT_NAME in "${CLIENT_NAMES[@]}"; do
    CLIENT_CONF="${WG_CONF_DIR}/${CLIENT_NAME}.conf"

    # Skip existing clients
    if grep -q "${CLIENT_NAME}" "${WG_CONF_DIR}/${WG_IF}.conf"; then
        echo "Skipping ${CLIENT_NAME}, already exists."
        continue
    fi

    # Generate keys
    wg genkey | tee "${WG_CONF_DIR}/${CLIENT_NAME}_private.key" | wg pubkey > "${WG_CONF_DIR}/${CLIENT_NAME}_public.key"
    CLIENT_PRIVATE=$(cat "${WG_CONF_DIR}/${CLIENT_NAME}_private.key")
    CLIENT_PUBLIC=$(cat "${WG_CONF_DIR}/${CLIENT_NAME}_public.key")

    # Assign next available IP
    while [[ " ${USED_SUFFIXES[@]} " =~ " ${NEXT_IP_SUFFIX} " ]]; do
        NEXT_IP_SUFFIX=$((NEXT_IP_SUFFIX+1))
        if [ $NEXT_IP_SUFFIX -gt 254 ]; then
            echo "No available IPs left in 10.20.20.0/24!"
            exit 1
        fi
    done
    CLIENT_IP="10.20.20.${NEXT_IP_SUFFIX}/24"
    USED_SUFFIXES+=($NEXT_IP_SUFFIX)
    NEXT_IP_SUFFIX=$((NEXT_IP_SUFFIX+1))

    # Add client to server config
    cat >> "${WG_CONF_DIR}/${WG_IF}.conf" <<EOF

[Peer]
# ${CLIENT_NAME}
PublicKey = ${CLIENT_PUBLIC}
AllowedIPs = ${CLIENT_IP}
EOF

    # Create client config
    cat > "${CLIENT_CONF}" <<EOF
[Interface]
PrivateKey = ${CLIENT_PRIVATE}
Address = ${CLIENT_IP}
DNS = ${DNS}

[Peer]
PublicKey = $(cat "${WG_CONF_DIR}/server_public.key")
Endpoint = ${DDNS_HOSTNAME}:${WG_PORT}
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF

    # Show config + QR
    echo "===== ${CLIENT_NAME} CONFIG ====="
    cat "${CLIENT_CONF}"
    echo "================================="
    qrencode -t ansiutf8 < "${CLIENT_CONF}"

    echo "Client ${CLIENT_NAME} added with IP ${CLIENT_IP}"
done

# Add NAT rules if missing
if ! grep -q "PostUp" "${WG_CONF_DIR}/${WG_IF}.conf"; then
    sed -i "/\[Interface\]/a PostUp = iptables -A FORWARD -i ${WG_IF} -j ACCEPT; iptables -A FORWARD -o ${WG_IF} -j ACCEPT; iptables -t nat -A POSTROUTING -o ${MAIN_IF} -j MASQUERADE\nPostDown = iptables -D FORWARD -i ${WG_IF} -j ACCEPT; iptables -D FORWARD -o ${WG_IF} -j ACCEPT; iptables -t nat -D POSTROUTING -o ${MAIN_IF} -j MASQUERADE" "${WG_CONF_DIR}/${WG_IF}.conf"
    echo "Added NAT rules using detected interface ${MAIN_IF}"
fi

# Enable IP forwarding
sysctl -w net.ipv4.ip_forward=1
grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

# Enable and restart WireGuard
systemctl enable wg-quick@${WG_IF}
systemctl restart wg-quick@${WG_IF}

echo "All clients added and WireGuard restarted successfully."