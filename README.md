# qbitvpn
qBittorrent + OpenVPN, killswitched by nftables

### Make sure nf_tables module is loaded on host:
```bash
sudo modprobe nf_tables
sudo systemctl enable nftables
```

## Docker Compose Example

```yaml
services:
  qbitvpn:
    image: minutelight/qbitvpn:latest
    container_name: qbitvpn
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun
    environment:
      - VPN_USER=your_vpn_username
      - VPN_PASS=your_vpn_password
      - LAN_SUBNET=192.168.1.0/24
      - TZ=Europe/London
    volumes:
      - ./config:/config
      - ./data:/data
      - /etc/localtime:/etc/localtime:ro
    ports:
      - 8080:8080
    restart: unless-stopped
```

## Rootless Podman Quadlet Example

Save this file as `~/.config/containers/systemd/qbitvpn.container`  
Run `systemctl --user daemon-reload && systemctl --user start qbitvpn`

```systemd
[Unit]
Description=qBitVPN
After=network-online.target
Wants=network-online.target

[Container]
Image=minutelight/qbitvpn:latest
ContainerName=qbitvpn
AddCapability=NET_ADMIN
AddDevice=/dev/net/tun
SecurityLabelDisable=true
Environment=VPN_USER=your_vpn_username
Environment=VPN_PASS=your_vpn_password
Environment=LAN_SUBNET=192.168.1.0/24
Environment=TZ=Europe/London
Volume=%h/qbitvpn/config:/config:Z
Volume=%h/qbitvpn/data:/data:Z
Volume=/etc/localtime:/etc/localtime:ro
PublishPort=8080:8080

[Install]
WantedBy=default.target
```
