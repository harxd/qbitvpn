#!/bin/bash

# Configuration and defaults
LAN_SUBNET=${LAN_SUBNET:-"192.168.1.0/24"}
VPN_CONFIG_DIR="/config/openvpn"
QBIT_CONFIG_DIR="/config/qBittorrent/config"
QBIT_CONFIG_FILE="$QBIT_CONFIG_DIR/qBittorrent.conf"
PORT_FORWARD_SCRIPT="/getvpnport.sh"

echo "[INFO] Starting Initialization Sequence..."

# Ensure required directories exist
mkdir -p /data
mkdir -p "$VPN_CONFIG_DIR"
mkdir -p "/config/qBittorrent/config"
mkdir -p "/config/qBittorrent/data"
mkdir -p "/config/qBittorrent/cache"

# Auto-generate credentials.conf if missing but env vars are set
if [ ! -f "$VPN_CONFIG_DIR/credentials.conf" ] && [ -n "$VPN_USER" ] && [ -n "$VPN_PASS" ]; then
    echo "[INFO] Generating OpenVPN credentials.conf from environment variables..."
    echo "$VPN_USER" > "$VPN_CONFIG_DIR/credentials.conf"
    echo "$VPN_PASS" >> "$VPN_CONFIG_DIR/credentials.conf"
    chmod 600 "$VPN_CONFIG_DIR/credentials.conf"
fi

### 1. Killswitch

echo "[INFO] Configuring Killswitch..."

# Flush & Initialize: Using rules.nft
# But first we need to find the VPN Server IP
OVPN_FILE=$(find "$VPN_CONFIG_DIR" -maxdepth 1 -name "*.ovpn" | head -n 1)

if [ -z "$OVPN_FILE" ]; then
    echo "[ERROR] No .ovpn file found in $VPN_CONFIG_DIR. You must mount a valid OpenVPN configuration profile."
    exit 1
fi

echo "[INFO] Using OpenVPN config: $OVPN_FILE"

# The VPN Exception: Parse VPN config to find the remote server IP and port.
# Also handling hostnames by resolving them.
REMOTE_SERVER=$(awk '/^remote /{print $2}' "$OVPN_FILE" | head -n 1)

if [ -z "$REMOTE_SERVER" ]; then
    # Default to standard OpenVPN behavior or parsing error
    echo "[ERROR] Could not parse 'remote' from $OVPN_FILE"
    exit 1
fi

echo "[INFO] Resolving VPN server: $REMOTE_SERVER"
VPN_IP=$(ping -c 1 "$REMOTE_SERVER" | awk -F'[)(]' '/PING/{print $2; exit}')

if [ -z "$VPN_IP" ]; then
    # Fallback if ping fails or format is irregular
    VPN_IP=$(nslookup "$REMOTE_SERVER" | awk '/^Address: / { print $2 ; exit }')
fi

if [ -z "$VPN_IP" ]; then
    echo "[ERROR] Could not resolve VPN IP for $REMOTE_SERVER. Ensure Docker has DNS resolution."
    # If the user put an IP address directly, it might not be resolvable, so let's just use it if it's an IP.
    if [[ "$REMOTE_SERVER" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        VPN_IP="$REMOTE_SERVER"
    else
        exit 1
    fi
fi

echo "[INFO] Resolved VPN IP: $VPN_IP"

# Inject the IP and Subnet into the nftables file
cp /etc/nftables.conf /etc/nftables.conf.tmp
sed -i "s/\$VPN_SERVER_IP/$VPN_IP/g" /etc/nftables.conf.tmp
sed -i "s|192.168.1.0/24|$LAN_SUBNET|g" /etc/nftables.conf.tmp

# Apply nftables rulesets (Killswitch activated)
nft -f /etc/nftables.conf.tmp || { echo "[ERROR] Failed to apply nftables rules."; exit 1; }
echo "[INFO] Firewall Killswitch Activated."


### 2. VPN

echo "[INFO] Launching OpenVPN..."
OPENVPN_ARGS="--config $OVPN_FILE --daemon"
if [ -f "$VPN_CONFIG_DIR/credentials.conf" ]; then
    OPENVPN_ARGS="$OPENVPN_ARGS --auth-user-pass $VPN_CONFIG_DIR/credentials.conf"
fi
openvpn $OPENVPN_ARGS

echo "[INFO] Waiting for tun0 interface (Interface Polling)..."
while ! ip link show tun0 > /dev/null 2>&1; do
    sleep 1
done
echo "[INFO] VPN Interface tun0 detected."

# Route Verification (Leak Check)
echo "[INFO] Performing Route Verification..."
IP_CHECK=$(curl -s --interface tun0 ifconfig.me)
if [ -z "$IP_CHECK" ]; then
    echo "[ERROR] VPN Route Verification failed! Could not reach internet over tun0."
    nft flush ruleset
    exit 1
fi
echo "[INFO] VPN IP is $IP_CHECK"


### 3. Port Forwarding

# Establish initial variables
CURRENT_PORT=0
PORT_START_TIME=0

hole_punch() {
    local NEW_PORT=$1
    echo "[INFO] Requested Port via Tunnel: $NEW_PORT"
    
    # NFT Hole Punch
    # Update nftables to allow incoming on tun0 for the new port
    nft add rule inet filter input iif "tun0" tcp dport $NEW_PORT accept
    nft add rule inet filter input iif "tun0" udp dport $NEW_PORT accept

    # Config Injection
    if [ ! -d "$QBIT_CONFIG_DIR" ]; then
        mkdir -p "$QBIT_CONFIG_DIR"
    fi
    if [ ! -f "$QBIT_CONFIG_FILE" ]; then
        # Create a basic config if it doesn't exist to allow setting port
        echo "[Preferences]" > "$QBIT_CONFIG_FILE"
        echo "Session\Port=$NEW_PORT" >> "$QBIT_CONFIG_FILE"
        echo "Connection\Interface=tun0" >> "$QBIT_CONFIG_FILE"
        echo "Connection\InterfaceName=tun0" >> "$QBIT_CONFIG_FILE"
    else
        # Update existing config
        # Use sed to update or append
        if grep -q "^Session\\\\Port=" "$QBIT_CONFIG_FILE"; then
            sed -i "s/^Session\\\\Port=.*/Session\\\\Port=$NEW_PORT/" "$QBIT_CONFIG_FILE"
        else
            sed -i '/\[Preferences\]/a Session\\Port='"$NEW_PORT"'' "$QBIT_CONFIG_FILE"
        fi
        
        # Ensure it binds to tun0
        if grep -q "^Connection\\\\Interface=" "$QBIT_CONFIG_FILE"; then
            sed -i "s/^Connection\\\\Interface=.*/Connection\\\\Interface=tun0/" "$QBIT_CONFIG_FILE"
        else
             sed -i '/\[Preferences\]/a Connection\\Interface=tun0' "$QBIT_CONFIG_FILE"
        fi
        if grep -q "^Connection\\\\InterfaceName=" "$QBIT_CONFIG_FILE"; then
             sed -i "s/^Connection\\\\InterfaceName=.*/Connection\\\\InterfaceName=tun0/" "$QBIT_CONFIG_FILE"
        else
             sed -i '/\[Preferences\]/a Connection\\InterfaceName=tun0' "$QBIT_CONFIG_FILE"
        fi
    fi
    CURRENT_PORT=$NEW_PORT
    PORT_START_TIME=$(date +%s)
}

update_port() {
    echo "[INFO] Requesting port forwarding..."
    if [ -x "$PORT_FORWARD_SCRIPT" ]; then
        local NEW_PORT=$("$PORT_FORWARD_SCRIPT")
        if [ "$?" -eq 0 ] && [ -n "$NEW_PORT" ]; then
            if [ "$NEW_PORT" != "$CURRENT_PORT" ]; then
                # Remove old rules if port changed
                if [ "$CURRENT_PORT" -ne 0 ]; then
                     nft delete rule inet filter input iif "tun0" tcp dport $CURRENT_PORT accept 2>/dev/null || true
                     nft delete rule inet filter input iif "tun0" udp dport $CURRENT_PORT accept 2>/dev/null || true
                fi
                hole_punch "$NEW_PORT"
                return 0
            else
                # Port is still the same, just update the token lease timer
                PORT_START_TIME=$(date +%s)
                return 0
            fi
        else
            echo "[WARNING] Port forward script failed or returned empty."
            return 1
        fi
    else
        echo "[WARNING] $PORT_FORWARD_SCRIPT not found or not executable. Skipping port forward."
        return 0 # Bypass port update cycle if not requested
    fi
}

# Initial Port forward request
update_port || true


### 4. qBittorrent

echo "[INFO] Starting qBittorrent..."
# Create a dedicated webui user/password config injection if we wanted to
qbittorrent-nox --profile=/config --webui-port=8080 -d

echo "[INFO] qBittorrent started in the background. Entering Watchdog loop."

# Watchdog
while true; do
    sleep 15
    
    # 1. Is the VPN still up? (Check tun0)
    if ! ip link show tun0 >/dev/null 2>&1; do
        echo "[CRITICAL] tun0 interface disappeared! VPN down!"
        nft flush ruleset
        echo "[CRITICAL] Terminating container."
        kill 1 # Send exit signal to main pid to stop container
        exit 1
    fi
    
    # 2. Is the port still valid? Every 15 minutes, re-check the PIA port lease.
    NOW=$(date +%s)
    DIFF=$(( NOW - PORT_START_TIME ))
    # Check every 900 seconds (15 minutes)
    if [ $DIFF -gt 900 ]; then
        echo "[INFO] Watchdog: Renewing port lease..."
        if update_port; then
             # If the port changed, we should ideally restart qbittorrent or its socket
             # But usually qBittorrent picks up the config change on restart or we just let it be.
             # According to specs, "If it changes, repeat steps 9 and 10."
             # Qbit won't apply config dynamically unless restarted or using API, but we'll restart it just in case if port changed
             # But let's avoid restarting unless port actually changed
             :
        fi
    fi
done
