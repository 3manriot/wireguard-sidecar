#!/bin/sh
set -eu

WG_CONF=/etc/wireguard/wg0.conf
VPN_GW="${VPN_GATEWAY:-10.2.0.1}"
HEALTH_INTERVAL="${HEALTH_INTERVAL:-60}"

log() { echo "[wg] $(date -u +%H:%M:%SZ) $*"; }

field() { grep -E "^\s*${1}\s*=" "$WG_CONF" | head -1 | cut -d= -f2- | sed 's/^ //; s/[[:space:]]*$//'; }

log "--- WireGuard sidecar starting ---"
log "Config:      $WG_CONF"

PRIVATE_KEY=$(field PrivateKey)
VPN_ADDR=$(field Address | cut -d/ -f1)
PUBLIC_KEY=$(field PublicKey)
ENDPOINT=$(field Endpoint)
ENDPOINT_IP=$(echo "$ENDPOINT" | cut -d: -f1)

log "Endpoint:    $ENDPOINT"
log "VPN address: $VPN_ADDR"
log "Public key:  ${PUBLIC_KEY}"

ETH=$(ip route show default | awk '/default/{print $5; exit}')
GW=$(ip route show default  | awk '/default/{print $3; exit}')
log "Gateway: $GW via $ETH"

ip link del wg0 2>/dev/null && log "Removed stale wg0" || true

log "Creating wg0 interface..."
ip link add wg0 type wireguard
ip addr add "${VPN_ADDR}/32" dev wg0

log "Configuring WireGuard peer..."
KEYFILE=$(mktemp)
printf '%s' "$PRIVATE_KEY" > "$KEYFILE"
wg set wg0 \
  private-key "$KEYFILE" \
  peer "$PUBLIC_KEY" \
  endpoint "$ENDPOINT" \
  allowed-ips "0.0.0.0/0" \
  persistent-keepalive 25
rm -f "$KEYFILE"

ip link set wg0 up
log "wg0 up"

log "Configuring routes..."
ip route add "${ENDPOINT_IP}/32" via "$GW" dev "$ETH" 2>/dev/null || true
ip route del default 2>/dev/null || true
# Add a direct host route to the VPN gateway so it can be used as a next-hop.
# This makes the default gateway discoverable by NAT-PMP clients (e.g. qBittorrent)
# via /proc/net/route, allowing them to request port forwarding without wg knowing
# anything about the application using the tunnel.
ip route add "${VPN_GW}" dev wg0
ip route add default via "${VPN_GW}" dev wg0
log "Default route -> ${VPN_GW} via wg0"

LAN="${VPN_LAN_NETWORK:-192.168.0.0/16,10.43.0.0/16}"
for net in $(echo "$LAN" | tr ',' ' '); do
  ip route add "$net" via "$GW" dev "$ETH" 2>/dev/null || true
  log "LAN route: $net -> $GW"
done

LAN_RULES=""
for net in $(echo "$LAN" | tr ',' ' '); do
  LAN_RULES="${LAN_RULES}    ip daddr ${net} oif ${ETH} accept\n"
done

nft -f - << NFTEOF
table inet wg_killswitch {
  chain output {
    type filter hook output priority filter; policy drop;
    oif lo accept
    oif wg0 accept
    ip daddr ${ENDPOINT_IP}/32 oif ${ETH} accept
$(printf '%b' "$LAN_RULES")
  }
  chain input {
    type filter hook input priority filter; policy accept;
  }
}
NFTEOF

log "Killswitch active"

sleep 1
if ip route get 1.1.1.1 2>/dev/null | grep -q wg0; then
  log "Routing verified: external traffic via wg0"
else
  log "WARNING: External traffic not routing through wg0"
fi

log "VPN gateway: ${VPN_GW} — NAT-PMP port forwarding delegated to the application"
log "--- Startup complete, health checks every ${HEALTH_INTERVAL}s ---"

human_bytes() {
  awk -v b="$1" 'BEGIN {
    if (b >= 1073741824)      printf "%.2f GiB", b/1073741824
    else if (b >= 1048576)    printf "%.2f MiB", b/1048576
    else if (b >= 1024)       printf "%.2f KiB", b/1024
    else                      printf "%d B", b
  }'
}

while true; do
  sleep "$HEALTH_INTERVAL"
  HANDSHAKE=$(wg show wg0 latest-handshakes 2>/dev/null | awk '{print $2}')
  if [ -n "$HANDSHAKE" ] && [ "$HANDSHAKE" -gt 0 ] 2>/dev/null; then
    AGO=$(( $(date +%s) - HANDSHAKE ))
    TRANSFER=$(wg show wg0 transfer 2>/dev/null)
    RX=$(echo "$TRANSFER" | awk '{print $2}')
    TX=$(echo "$TRANSFER" | awk '{print $3}')
    log "Healthy — last handshake ${AGO}s ago, rx $(human_bytes "$RX") / tx $(human_bytes "$TX") (cumulative)"
  else
    log "WARNING: no WireGuard handshake recorded yet"
  fi
done
