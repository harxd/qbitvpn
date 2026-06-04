FROM alpine:latest

# Install dependencies
RUN apk add --no-cache \
    qbittorrent-nox \
    openvpn \
    nftables \
    bash \
    curl \
    tini \
    jq

# Copy your configuration and scripts
COPY entrypoint.sh /entrypoint.sh
COPY getvpnport.sh /getvpnport.sh
COPY check_trackers.sh /check_trackers.sh
COPY rules.nft /etc/nftables.conf

RUN sed -i 's/\r$//' /entrypoint.sh /getvpnport.sh /check_trackers.sh /etc/nftables.conf && \
    chmod +x /entrypoint.sh /getvpnport.sh /check_trackers.sh

# qBittorrent WebUI port
EXPOSE 8080

ENTRYPOINT ["/sbin/tini", "-g", "--", "/entrypoint.sh"]