#!/bin/bash
# Script to check qBittorrent tracker status via local WebUI API

# 1. Get credentials from qBittorrent.conf if customized
QBIT_CONFIG_FILE="/config/qBittorrent/config/qBittorrent.conf"
USER="admin"
# Accept password as first argument, or default to adminadmin
PASS=${1:-"adminadmin"}

if [ -f "$QBIT_CONFIG_FILE" ]; then
    CONF_USER=$(grep -E "^WebUI\\\\Username=" "$QBIT_CONFIG_FILE" | cut -d'=' -f2 | tr -d '\r')
    if [ -n "$CONF_USER" ]; then
        USER="$CONF_USER"
    fi
fi

echo "[INFO] Logging in to qBittorrent WebUI as '$USER'..."

# Login and save session cookie (adding Referer header to satisfy CSRF protection)
LOGIN_RES=$(curl -s -i -H "Referer: http://localhost:8080/" -X POST -d "username=$USER&password=$PASS" http://localhost:8080/api/v2/auth/login)

# Robust cookie extraction using grep/regex
COOKIE=$(echo "$LOGIN_RES" | grep -oE 'SID=[^;]+' | head -n 1)

if [ -n "$COOKIE" ]; then
    echo "[INFO] Login successful. Session cookie acquired."
else
    echo -e "\033[0;31m[ERROR] WebUI login failed! If you changed your WebUI password from the default 'adminadmin', you must pass it to this script:\033[0m"
    echo -e "  \033[0;33mpodman exec -it qbitvpn /check_trackers.sh [your_password]\033[0m"
    exit 1
fi

echo "[INFO] Fetching torrents info..."
# Get torrents list (passing the cookie string directly via -b)
TORRENTS_JSON=$(curl -s -H "Referer: http://localhost:8080/" -b "$COOKIE" http://localhost:8080/api/v2/torrents/info)

if [ -z "$TORRENTS_JSON" ] || echo "$TORRENTS_JSON" | grep -qi -E "Unauthorized|Forbidden|Fails"; then
    echo "[ERROR] Failed to fetch torrents. Response was:"
    echo "$TORRENTS_JSON"
    exit 1
fi

if [ "$TORRENTS_JSON" = "[]" ]; then
    echo "[INFO] No active torrents found in qBittorrent."
    exit 0
fi

# Parse torrent hashes and names using jq
echo "$TORRENTS_JSON" | jq -c '.[]' | while read -r torrent; do
    HASH=$(echo "$torrent" | jq -r '.hash')
    NAME=$(echo "$torrent" | jq -r '.name')
    STATE=$(echo "$torrent" | jq -r '.state')
    PROGRESS=$(echo "$torrent" | jq -r '.progress')
    UPLOADED=$(echo "$torrent" | jq -r '.uploaded')
    UPSPEED=$(echo "$torrent" | jq -r '.upspeed')
    PEERS=$(echo "$torrent" | jq -r '.num_leechs')
    SEEDS=$(echo "$torrent" | jq -r '.num_seeds')
    
    # Calculate progress percentage
    PROG_PCT=$(echo "$PROGRESS * 100" | bc 2>/dev/null || awk -v p="$PROGRESS" 'BEGIN {print p*100}')
    
    echo "--------------------------------------------------"
    echo -e "\033[1;36mTorrent:\033[0m $NAME"
    echo -e "\033[1;30mHash:\033[0m $HASH"
    echo -e "\033[1;30mState:\033[0m $STATE | \033[1;30mProgress:\033[0m ${PROG_PCT}%"
    echo -e "\033[1;30mSession Upload:\033[0m $(echo "$torrent" | jq -r '.uploaded_session') bytes | \033[1;30mSpeed:\033[0m $UPSPEED B/s"
    echo -e "\033[1;30mActive Seeds/Peers:\033[0m $SEEDS / $PEERS"
    
    # Get trackers for this torrent (passing the cookie string directly via -b)
    TRACKERS_JSON=$(curl -s -H "Referer: http://localhost:8080/" -b "$COOKIE" "http://localhost:8080/api/v2/torrents/trackers?hash=$HASH")
    
    # Parse tracker URLs, status, and message using jq
    echo "$TRACKERS_JSON" | jq -c '.[]' | while read -r tracker; do
        T_URL=$(echo "$tracker" | jq -r '.url')
        T_STATUS=$(echo "$tracker" | jq -r '.status')
        T_MSG=$(echo "$tracker" | jq -r '.msg')
        
        # Status code meanings in qBittorrent API v2:
        # 0 = Tracker is disabled
        # 1 = Tracker has not been contacted yet
        # 2 = Tracker has been contacted and is working
        # 3 = Tracker is updating
        # 4 = Tracker has been contacted, but it is not working
        STATUS_TXT="Unknown"
        case "$T_STATUS" in
            0) STATUS_TXT="Disabled" ;;
            1) STATUS_TXT="Not Contacted" ;;
            2) STATUS_TXT="Working" ;;
            3) STATUS_TXT="Updating" ;;
            4) STATUS_TXT="Not Working" ;;
        esac
        
        echo -e "  - Tracker: $T_URL"
        if [ "$T_STATUS" -eq 2 ] || [ "$T_STATUS" -eq 3 ]; then
            echo -e "    Status: \033[0;32m$STATUS_TXT\033[0m"
        else
            echo -e "    Status: \033[0;31m$STATUS_TXT\033[0m"
        fi
        if [ -n "$T_MSG" ] && [ "$T_MSG" != "null" ]; then
            echo -e "    Message: \033[0;33m$T_MSG\033[0m"
        fi
    done
done
echo "--------------------------------------------------"
