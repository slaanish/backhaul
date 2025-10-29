# WireGuard + Caddy HTTPS Proxy

This solution routes all Caddy traffic through a WireGuard tunnel, enabling you to expose HTTPS websites with automatic Let's Encrypt certificates via DNS challenge, while keeping all traffic routed through a VPN.

## Architecture

```
Internet → [WireGuard Tunnel] → Caddy (HTTPS) → Backend Service
```

**Key Components:**
- **WireGuard**: Creates a secure tunnel that acts as the network backhaul
- **Caddy**: Runs in the WireGuard network namespace, handles HTTPS/TLS termination and DNS-01 challenge
- **Backend**: Your application (optional, can proxy to external services)

**Network Flow:**
1. All Caddy traffic routes through the WireGuard tunnel
2. DNS challenges are performed through the tunnel
3. HTTPS traffic enters through WireGuard's endpoint IP
4. Caddy terminates SSL and proxies to backend

## Prerequisites

- Docker and Docker Compose installed
- A WireGuard VPN server with public IP
- Domain name pointing to the WireGuard exit IP
- DNS provider API credentials (for Let's Encrypt DNS challenge)
- WireGuard private key and server public key

## Supported DNS Providers

Caddy supports many DNS providers for Let's Encrypt challenges:
- Cloudflare
- Route53 (AWS)
- DigitalOcean
- Google Cloud DNS
- Azure DNS
- And many more: https://caddyserver.com/docs/modules/

## Quick Start

### 1. Clone or Create the Directory Structure

```bash
mkdir wireguard-caddy && cd wireguard-caddy
# Copy all files from this project
```

### 2. Generate WireGuard Keys (if needed)

```bash
# Generate private key
wg genkey > private.key

# Generate public key from private key
cat private.key | wg pubkey > public.key

# Generate preshared key (optional)
wg genpsk > preshared.key
```

### 3. Configure Environment Variables

```bash
cp .env.example .env
nano .env
```

Edit the following values in `.env`:

```bash
# Your domain
DOMAIN=yourdomain.com
ACME_EMAIL=your-email@example.com

# Backend service (where Caddy will proxy requests)
BACKEND_HOST=backend  # or external IP/domain
BACKEND_PORT=8080

# DNS Provider (e.g., cloudflare, route53, digitalocean)
DNS_PROVIDER=cloudflare
DNS_API_TOKEN=your_cloudflare_api_token

# WireGuard Configuration
WG_PRIVATE_KEY=your_client_private_key
WG_ADDRESS=10.0.0.2/24
WG_SERVER_PUBLIC_KEY=your_server_public_key
WG_SERVER_ENDPOINT=vpn.yourserver.com:51820
WG_ALLOWED_IPS=0.0.0.0/0  # Route all traffic through tunnel
```

### 4. Generate Configuration and Start

```bash
# Generate WireGuard config from environment variables
./setup.sh

# Start the services
docker-compose up -d

# Check logs
docker-compose logs -f
```

## Configuration Details

### DNS Provider Setup

#### Cloudflare Example
1. Get API token from: https://dash.cloudflare.com/profile/api-tokens
2. Create token with permissions: `Zone:DNS:Edit` for your domain
3. Set in `.env`:
   ```
   DNS_PROVIDER=cloudflare
   DNS_API_TOKEN=your_token_here
   ```

#### AWS Route53 Example
1. Create IAM user with Route53 permissions
2. Set in `.env`:
   ```
   DNS_PROVIDER=route53
   DNS_API_TOKEN=AWS_ACCESS_KEY_ID:AWS_SECRET_ACCESS_KEY
   ```

#### Other Providers
Check Caddy's DNS module documentation for your provider's specific requirements.

### WireGuard Configuration

The `setup.sh` script generates `wireguard/wg0.conf` from your environment variables. Key settings:

- **AllowedIPs**: `0.0.0.0/0` routes ALL traffic through the tunnel
  - Change to specific IPs (e.g., `10.0.0.0/24`) to route only VPN traffic
- **PersistentKeepalive**: Helps with NAT traversal (25 seconds recommended)
- **DNS**: DNS servers to use inside the tunnel

### Network Architecture

The key architectural decision is using `network_mode: "service:wireguard"` for Caddy:
- Caddy shares WireGuard's network namespace
- All Caddy traffic automatically routes through the tunnel
- Ports are exposed through the WireGuard container

## Port Forwarding

Ensure your WireGuard server forwards these ports to the client:
- Port 80 (HTTP - for ACME challenges)
- Port 443 (HTTPS)

On your WireGuard server, add these rules:

```bash
# Forward ports to WireGuard client
iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 80 -j DNAT --to-destination 10.0.0.2:80
iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 443 -j DNAT --to-destination 10.0.0.2:443
iptables -A FORWARD -p tcp -d 10.0.0.2 --dport 80 -j ACCEPT
iptables -A FORWARD -p tcp -d 10.0.0.2 --dport 443 -j ACCEPT
```

## Customization

### Custom Caddyfile

Edit `Caddyfile` to customize your proxy behavior:

```caddyfile
{$DOMAIN} {
    tls {
        dns {$DNS_PROVIDER} {$DNS_API_TOKEN}
    }

    # Simple reverse proxy
    reverse_proxy {$BACKEND_HOST}:{$BACKEND_PORT}

    # Or serve static files
    # root * /var/www/html
    # file_server

    # Or multiple backends with load balancing
    # reverse_proxy backend1:8080 backend2:8080 {
    #     lb_policy round_robin
    # }
}
```

### Multiple Domains

Add more domain blocks to the Caddyfile:

```caddyfile
{$DOMAIN} {
    tls {
        dns {$DNS_PROVIDER} {$DNS_API_TOKEN}
    }
    reverse_proxy backend1:8080
}

app.{$DOMAIN} {
    tls {
        dns {$DNS_PROVIDER} {$DNS_API_TOKEN}
    }
    reverse_proxy backend2:3000
}
```

## Troubleshooting

### Check WireGuard Connection

```bash
docker-compose exec wireguard wg show
```

Expected output:
```
interface: wg0
  public key: <your_public_key>
  private key: (hidden)
  listening port: xxxxx

peer: <server_public_key>
  endpoint: <server_ip>:51820
  allowed ips: 0.0.0.0/0
  latest handshake: X seconds ago
  transfer: X.XX GiB received, X.XX GiB sent
```

### Check Caddy Logs

```bash
docker-compose logs caddy
```

### Test DNS Resolution Through Tunnel

```bash
docker-compose exec wireguard ping -c 4 1.1.1.1
docker-compose exec wireguard nslookup yourdomain.com
```

### Verify Certificate Issuance

```bash
# Check Caddy data directory for certificates
ls -la caddy_data/caddy/certificates/acme-v02.api.letsencrypt.org-directory/
```

### Common Issues

1. **Certificate not issued**: 
   - Verify DNS API token has correct permissions
   - Check DNS records are pointing to WireGuard exit IP
   - Review Caddy logs for DNS challenge errors

2. **WireGuard not connecting**:
   - Verify server public key is correct
   - Check server endpoint is reachable
   - Ensure UDP port 51820 is open on server

3. **Traffic not routing through tunnel**:
   - Verify `AllowedIPs = 0.0.0.0/0` in WireGuard config
   - Check IP forwarding is enabled
   - Verify iptables rules on server

## Security Considerations

- Store `.env` file securely (add to `.gitignore`)
- Use strong WireGuard keys (generated with `wg genkey`)
- Consider adding preshared keys for quantum resistance
- Regularly update Docker images
- Monitor logs for suspicious activity
- Implement rate limiting in Caddyfile if needed

## Updating

```bash
# Pull latest images
docker-compose pull

# Recreate containers
docker-compose up -d

# Clean up old images
docker image prune -f
```

## License

This configuration is provided as-is for educational and production use.
