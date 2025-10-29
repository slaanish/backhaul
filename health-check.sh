#!/bin/bash

# Health check script for WireGuard + Caddy setup

echo "================================================"
echo "WireGuard + Caddy Health Check"
echo "================================================"
echo ""

# Check if Docker Compose is running
echo "1. Checking Docker Compose status..."
if docker-compose ps | grep -q "Up"; then
    echo "   ✓ Docker Compose services are running"
else
    echo "   ✗ Docker Compose services are not running"
    echo "   Run: docker-compose up -d"
    exit 1
fi
echo ""

# Check WireGuard connection
echo "2. Checking WireGuard connection..."
WG_STATUS=$(docker-compose exec -T wireguard wg show 2>/dev/null)
if echo "$WG_STATUS" | grep -q "latest handshake"; then
    HANDSHAKE=$(echo "$WG_STATUS" | grep "latest handshake" | awk '{print $3, $4, $5}')
    echo "   ✓ WireGuard tunnel is active"
    echo "   Last handshake: $HANDSHAKE"
else
    echo "   ✗ WireGuard tunnel is not connected"
    echo "   Check your WireGuard configuration and server status"
fi
echo ""

# Check WireGuard IP
echo "3. Checking WireGuard interface IP..."
WG_IP=$(docker-compose exec -T wireguard ip addr show wg0 2>/dev/null | grep "inet " | awk '{print $2}')
if [ ! -z "$WG_IP" ]; then
    echo "   ✓ WireGuard interface IP: $WG_IP"
else
    echo "   ✗ WireGuard interface not found"
fi
echo ""

# Check internet connectivity through tunnel
echo "4. Checking internet connectivity through tunnel..."
if docker-compose exec -T wireguard ping -c 2 -W 2 1.1.1.1 >/dev/null 2>&1; then
    echo "   ✓ Internet connectivity through tunnel is working"
else
    echo "   ✗ Cannot reach internet through tunnel"
fi
echo ""

# Check DNS resolution through tunnel
echo "5. Checking DNS resolution..."
source .env 2>/dev/null
if [ ! -z "$DOMAIN" ]; then
    if docker-compose exec -T wireguard nslookup $DOMAIN >/dev/null 2>&1; then
        RESOLVED_IP=$(docker-compose exec -T wireguard nslookup $DOMAIN | grep "Address:" | tail -1 | awk '{print $2}')
        echo "   ✓ DNS resolution working for $DOMAIN"
        echo "   Resolved to: $RESOLVED_IP"
    else
        echo "   ✗ DNS resolution failed for $DOMAIN"
    fi
else
    echo "   ⚠ DOMAIN not set in .env file"
fi
echo ""

# Check Caddy status
echo "6. Checking Caddy status..."
if docker-compose ps caddy | grep -q "Up"; then
    echo "   ✓ Caddy container is running"
    
    # Check for certificates
    if [ -d "caddy_data/caddy/certificates" ]; then
        CERT_COUNT=$(find caddy_data/caddy/certificates -name "*.crt" 2>/dev/null | wc -l)
        if [ $CERT_COUNT -gt 0 ]; then
            echo "   ✓ SSL certificates found ($CERT_COUNT)"
        else
            echo "   ⚠ No SSL certificates found yet (may be in progress)"
        fi
    fi
else
    echo "   ✗ Caddy container is not running"
fi
echo ""

# Check Caddy logs for errors
echo "7. Checking Caddy logs for recent errors..."
CADDY_ERRORS=$(docker-compose logs --tail=50 caddy 2>/dev/null | grep -i "error" | tail -3)
if [ -z "$CADDY_ERRORS" ]; then
    echo "   ✓ No recent errors in Caddy logs"
else
    echo "   ⚠ Recent errors found:"
    echo "$CADDY_ERRORS" | sed 's/^/     /'
fi
echo ""

# Check listening ports
echo "8. Checking exposed ports..."
if docker-compose exec -T wireguard netstat -tuln 2>/dev/null | grep -q ":443"; then
    echo "   ✓ Port 443 (HTTPS) is listening"
else
    echo "   ⚠ Port 443 (HTTPS) is not listening"
fi

if docker-compose exec -T wireguard netstat -tuln 2>/dev/null | grep -q ":80"; then
    echo "   ✓ Port 80 (HTTP) is listening"
else
    echo "   ⚠ Port 80 (HTTP) is not listening"
fi
echo ""

# Final summary
echo "================================================"
echo "Health Check Complete"
echo "================================================"
echo ""
echo "To view live logs: docker-compose logs -f"
echo "To restart services: docker-compose restart"
echo "To view WireGuard details: docker-compose exec wireguard wg show"
