#!/bin/bash
# Script to get forwarded port from PIA openvpn
# See: https://github.com/pia-foss/manual-connections

CRED_FILE="/config/openvpn/credentials.conf"
if [ ! -f "$CRED_FILE" ]; then
    echo "[ERROR] Credentials file not found at $CRED_FILE" >&2
    exit 1
fi

VPN_USER=$(sed -n '1p' "$CRED_FILE" | tr -d '\r' | xargs)
VPN_PASS=$(sed -n '2p' "$CRED_FILE" | tr -d '\r' | xargs)

# Generate auth token securely through tunnel
CURL_OUT=$(curl -X POST -k -sS --interface tun0 --data-urlencode "username=$VPN_USER" --data-urlencode "password=$VPN_PASS" "https://www.privateinternetaccess.com/api/client/v2/token" 2>&1)
TOKEN=$(echo "$CURL_OUT" | grep -o '"token":"[^"]*' | cut -d'"' -f4)

if [ -z "$TOKEN" ]; then
    echo "[ERROR] Failed to generate PIA API token. Check credentials." >&2
    echo "[DEBUG] Curl verbose output:" >&2
    echo "$CURL_OUT" >&2
    exit 1
fi

# In OpenVPN PIA connections, the port forward Gateway is always the .1 address 
# of the IP address assigned to the tun0 interface.
TUN0_IP=$(ip -4 addr show dev tun0 | grep -oE 'inet [0-9.]+' | grep -oE '[0-9.]+')
if [ -n "$TUN0_IP" ]; then
    GATEWAY=$(echo "$TUN0_IP" | awk -F. '{print $1"."$2"."$3".1"}')
else
    GATEWAY="10.0.0.252"
fi

if ! curl -k -s -m 3 "https://$GATEWAY:19999/getSignature" >/dev/null 2>&1; then
    GATEWAY="10.0.0.252"
fi

ip route add "$GATEWAY" dev tun0 2>/dev/null || true

PIAPort_URL="https://$GATEWAY:19999/getSignature"
BIND_URL="https://$GATEWAY:19999/bindPort"

# Wait for PIA local API to be ready
API_ONLINE=0
for i in {1..10}; do
    if curl --interface tun0 -k -G -s -m 5 --data-urlencode "token=$TOKEN" "$PIAPort_URL" > /dev/null; then
        API_ONLINE=1
        break
    fi
    sleep 2
done

if [ $API_ONLINE -eq 0 ]; then
    echo "[ERROR] PIA Port Forward API not reachable at $PIAPort_URL over tunnel. Verify region supports Port Forwarding." >&2
    exit 1
fi

PAYLOAD_JSON=$(curl --interface tun0 -k -G -s -m 5 --data-urlencode "token=$TOKEN" "$PIAPort_URL")
if ! echo "$PAYLOAD_JSON" | grep -q 'payload'; then
    echo "[ERROR] Failed to obtain payload from $PIAPort_URL: $PAYLOAD_JSON" >&2
    exit 1
fi

PAYLOAD=$(echo "$PAYLOAD_JSON" | grep -Eo '"payload"[[:space:]]*:[[:space:]]*"[^"]+"' | cut -d '"' -f 4)
SIGNATURE=$(echo "$PAYLOAD_JSON" | grep -Eo '"signature"[[:space:]]*:[[:space:]]*"[^"]+"' | cut -d '"' -f 4)

# Decode payload to get port
PORT=$(echo "$PAYLOAD" | base64 -d 2>/dev/null | grep -oEi '"port"\s*:\s*[0-9]+' | grep -oE '[0-9]+')

if [ -z "$PORT" ]; then
    echo "[ERROR] Could not parse port from payload." >&2
    echo "[DEBUG] RAW PAYLOAD_JSON: $PAYLOAD_JSON" >&2
    echo "[DEBUG] DECODED PAYLOAD: $(echo "$PAYLOAD" | base64 -d 2>/dev/null)" >&2
    exit 1
fi

# Bind Port
BIND_RES=$(curl --interface tun0 -k -G -s -m 5 --data-urlencode "payload=$PAYLOAD" --data-urlencode "signature=$SIGNATURE" "$BIND_URL" || true)
if ! echo "$BIND_RES" | grep -q 'OK'; then
    echo "[ERROR] Failed to bind port: $BIND_RES" >&2
    exit 1
fi

echo "$PORT"
exit 0
