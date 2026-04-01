### 1. Killswitch
1. Flush & Initialize: Clear any existing rules and set the default policy for INPUT and OUTPUT to DROP.
2. Allow Loopback: Enable lo traffic so internal processes can talk to each other.
3. LAN/Docker Access: Add a rule to allow local subnet (e.g., 192.168.1.0/24) so the WebUI can be accessed from the browser.
4. The VPN Exception: Parse VPN config to find the remote server IP and port. Add a specific nft rule allowing output to only that IP on eth0.

### 2. VPN
5. Launch VPN Client: Start openvpn in the background.
6. Interface Polling: The script enters a loop, checking every 1 second for the existence of tun0 (or wg0).
7. Route Verification: Once the interface exists, the script performs a "leak check" (e.g., curl --interface tun0 ifconfig.me). If this fails or returns the real ISP IP, the script kills the container immediately.

### 3. Port Forwarding
8. Request Port: The script sends a request to the PIA local API via the tunnel. It receives a port number (e.g., 49152).
9. NFT Hole Punch: Update nftables ruleset to allow incoming traffic on that specific port via tun0.
10. Config Injection: Use sed to update the qBittorrent.conf file, setting Session\Port=49152 and ensuring it is bound to the tun0 interface.

### 4. qBittorrent
11. Start qBittorrent: Launch qbittorrent-nox as a background process.
12. The Watchdog: The main script doesn't exit; it stays alive to monitor two things:
    - Is the VPN still up? If tun0 disappears, run nft flush ruleset and kill the container.
    - Is the port still valid? Every 15–60 minutes, re-check the PIA port lease. If it changes, repeat steps 9 and 10.

### Summary Table: The Initialization Order
| Step | Action              | Responsibility  | Why?                                   |
| ---- | ------------------- | --------------- | -------------------------------------- |
|  1   | nft -f rules.nft    | Firewall Script | Prevents leaks during boot.            |
|  2   | openvpn --config... | VPN Client      | Establishes the encrypted tunnel.      |
|  3   | while ! ip addr...  | Health Check    | Ensures we don't start apps too early. |
|  4   | curl [PIA API]      | Port Script     | Gets the "Active" port for seeding.    |
|  5   | sed -i "s/..."      | Config Script   | Tells qBittorrent which port to use.   |
|  6   | qbittorrent-nox     | Application     | Finally starts the torrenting process. |