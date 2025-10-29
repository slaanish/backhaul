# Dockerfile for Caddy with DNS providers
# Use this if you need specific DNS modules not included in the official Caddy image

FROM caddy:builder AS builder

# Add DNS provider modules as needed
# Uncomment the ones you need:

# Cloudflare
RUN xcaddy build \
    --with github.com/caddy-dns/cloudflare

FROM caddy:latest

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
