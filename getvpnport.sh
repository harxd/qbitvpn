#!/bin/bash
# Script to get forwarded port from PIA openvpn
# See: https://github.com/pia-foss/manual-connections

PIAPort_URL="http://10.0.0.252:19999/getSignature"
BIND_URL="http://10.0.0.252:19999/bindPort"

# Wait for PIA local API to be ready
API_ONLINE=0
for i in {1..10}; do
    if curl -s -m 5 "$PIAPort_URL" > /dev/null; then
        API_ONLINE=1
        break
    fi
    sleep 2
done

if [ $API_ONLINE -eq 0 ]; then
    echo "[ERROR] PIA Port Forward API not reachable over tunnel." >&2
    exit 1
fi

PAYLOAD_JSON=$(curl -s -m 5 "$PIAPort_URL")
if ! echo "$PAYLOAD_JSON" | grep -q 'payload'; then
    echo "[ERROR] Failed to obtain payload from $PIAPort_URL: $PAYLOAD_JSON" >&2
    exit 1
fi

PAYLOAD=$(echo "$PAYLOAD_JSON" | awk -F '"payload":"' '{print $2}' | awk -F '"' '{print $1}')
SIGNATURE=$(echo "$PAYLOAD_JSON" | awk -F '"signature":"' '{print $2}' | awk -F '"' '{print $1}')

# Decode payload to get port
# The payload is base64 encoded JSON
PORT=$(echo "$PAYLOAD" | base64 -d 2>/dev/null | grep -o '"port":[0-9]*' | cut -d: -f2)

if [ -z "$PORT" ]; then
    echo "[ERROR] Could not parse port from payload." >&2
    exit 1
fi

# Bind Port
BIND_RES=$(curl -G -s -m 5 --data-urlencode "payload=$PAYLOAD" --data-urlencode "signature=$SIGNATURE" "$BIND_URL" || true)
if ! echo "$BIND_RES" | grep -q 'OK'; then
    echo "[ERROR] Failed to bind port: $BIND_RES" >&2
    exit 1
fi

echo "$PORT"
exit 0
