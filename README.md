# wireguard-sidecar

A Kubernetes sidecar that routes all pod traffic through a WireGuard VPN tunnel with an nftables kill-switch — if the tunnel drops, traffic is blocked rather than leaking.

## Image

```bash
ghcr.io/3manriot/wireguard-sidecars:latest
```

## How it works

A single script (`wg-up.sh`) runs as a native sidecar init container (`restartPolicy: Always`). It brings up the WireGuard interface, configures routing, applies the kill-switch, then sleeps. The network state persists in the shared pod network namespace for all other containers.

The default route is set via the VPN gateway IP (`VPN_GATEWAY`), which makes the gateway discoverable through the system routing table. This allows other containers in the pod to use standard NAT-PMP clients (e.g. qBittorrent's built-in port forwarding) to request port mappings directly from the VPN provider without any coupling to this sidecar.

**Requires:** `NET_ADMIN`, `NET_RAW` capabilities and a WireGuard config mounted at `/etc/wireguard/wg0.conf`.

## Configuration

| Env var | Default | Description |
| --- | --- | --- |
| `VPN_LAN_NETWORK` | `192.168.0.0/16,10.43.0.0/16` | Comma-separated CIDRs that bypass the VPN and route via eth0 |
| `VPN_GATEWAY` | `10.2.0.1` | Internal IP of the VPN peer. Used as the default route next-hop so NAT-PMP clients in other containers can discover it. ProtonVPN: `10.2.0.1`, Mullvad: `10.64.0.1` |

## Usage

```yaml
initContainers:
  - name: wg
    image: ghcr.io/3manriot/wireguard-sidecars:latest
    command: ["/scripts/wg-up.sh"]
    restartPolicy: Always
    securityContext:
      capabilities:
        add: [NET_ADMIN, NET_RAW]
        drop: [ALL]
      allowPrivilegeEscalation: false
    env:
      - name: VPN_LAN_NETWORK
        value: "192.168.0.0/16,10.42.0.0/16,10.43.0.0/16"
      - name: VPN_GATEWAY
        value: "10.2.0.1"
    volumeMounts:
      - name: wireguard-config
        mountPath: /etc/wireguard/wg0.conf
        subPath: wg0.conf
        readOnly: true

volumes:
  - name: wireguard-config
    secret:
      secretName: wireguard-config
      defaultMode: 0400
```

The `wg0.conf` should be a standard WireGuard config file with `[Interface]` and `[Peer]` sections. Store it as a Kubernetes Secret.

## Validating the tunnel

```bash
kubectl exec -it <pod> -c <your-container> -- curl -s https://ipinfo.io
```

The returned IP should be your VPN exit node, not your host IP. Verify the default route goes through `wg0` via the VPN gateway:

```bash
kubectl exec -it <pod> -c <your-container> -- ip route show
# expect: default via 10.2.0.1 dev wg0
```
