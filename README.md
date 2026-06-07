# wireguard-sidecar

A Kubernetes sidecar that routes all pod traffic through a WireGuard VPN tunnel with an nftables kill-switch — if the tunnel drops, traffic is blocked rather than leaking.

## Image

```bash
ghcr.io/3manriot/wireguard-sidecars:latest
```

## How it works

A single script (`wg-up.sh`) runs as a native sidecar init container (`restartPolicy: Always`). It brings up the WireGuard interface, configures routing, applies the kill-switch, then enters a NAT-PMP renewal loop to keep the forwarded port lease alive. The network state persists in the shared pod network namespace for all other containers.

**Requires:** `NET_ADMIN`, `NET_RAW` capabilities and a WireGuard config mounted at `/etc/wireguard/wg0.conf`.

## Configuration

| Env var | Default | Description |
| --- | --- | --- |
| `VPN_LAN_NETWORK` | `192.168.0.0/16,10.43.0.0/16` | Comma-separated CIDRs that bypass the VPN and route via eth0 |
| `NATPMP_GATEWAY` | `10.2.0.1` | NAT-PMP gateway IP (ProtonVPN: `10.2.0.1`, Mullvad: `10.64.0.1`) |
| `NATPMP_INTERVAL` | `45` | Seconds between lease renewals |

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
      runAsNonRoot: true
    env:
      - name: VPN_LAN_NETWORK
        value: "192.168.0.0/16,10.42.0.0/16,10.43.0.0/16"
      - name: NATPMP_GATEWAY
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

The returned IP should be your VPN exit node, not your host IP. Verify the default route goes through `wg0`:

```bash
kubectl exec -it <pod> -c <your-container> -- ip route show
# expect: default dev wg0
```
