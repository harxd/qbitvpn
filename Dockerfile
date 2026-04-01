FROM alpine:latest

# Install dependencies
RUN apk add --no-cache \
    qbittorrent-nox \
    openvpn \
    nftables \
    bash \
    curl

# Copy your configuration and scripts
COPY entrypoint.sh /entrypoint.sh
COPY getvpnport.sh /getvpnport.sh
COPY rules.nft /etc/nftables.conf

RUN sed -i 's/\r$//' /entrypoint.sh /getvpnport.sh && \
    chmod +x /entrypoint.sh /getvpnport.sh

# qBittorrent WebUI port
EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]