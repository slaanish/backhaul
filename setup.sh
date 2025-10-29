#!/bin/bash

set -e

# Load environment variables
if [ -f .env ]; then
    source .env
else
    echo "Error: .env file not found. Please copy .env.example to .env and configure it."
    exit 1
fi

# Create wireguard directory if it doesn't exist
mkdir -p wireguard/wg_confs/

# Generate WireGuard configuration
cat > wireguard/wg_confs/wg0.conf <<EOF
[Interface]
PrivateKey = ${WG_PRIVATE_KEY}
Address = ${WG_ADDRESS}
DNS = ${WG_DNS}

# Post-up script to configure routing
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o eth+ -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o eth+ -j MASQUERADE

[Peer]
PublicKey = ${WG_SERVER_PUBLIC_KEY}
Endpoint = ${WG_SERVER_ENDPOINT}
AllowedIPs = ${WG_ALLOWED_IPS}
PersistentKeepalive = 25
EOF

echo "WireGuard configuration generated successfully at wireguard/wg0.conf"

# Set proper permissions
chmod 600 wireguard/wg_confs/wg0.conf

# Create Caddy directories
mkdir -p caddy_data caddy_config

echo ""
echo "Setup complete! You can now run: docker-compose up -d"
echo ""
echo "Important notes:"
echo "1. Make sure your DNS is pointing to the WireGuard exit IP"
echo "2. Ensure ports 80 and 443 are accessible through the WireGuard tunnel"
echo "3. Check logs with: docker-compose logs -f"
