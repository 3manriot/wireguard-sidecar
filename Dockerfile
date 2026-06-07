FROM alpine:3.21

RUN apk add --no-cache wireguard-tools nftables libnatpmp iproute2 libcap
RUN addgroup -g 1000 -S wireguard && adduser -u 1000 -S wireguard -G wireguard
RUN chown root:wireguard /etc/wireguard && chmod 750 /etc/wireguard

# Grant NET_ADMIN+NET_RAW to network utilities via file capabilities so they
# work when exec'd by a non-root process that already has these in its
# permitted set (set by Kubernetes via securityContext.capabilities.add).
RUN setcap cap_net_admin,cap_net_raw+ep /sbin/ip \
 && setcap cap_net_admin+ep /usr/bin/wg \
 && setcap cap_net_admin,cap_net_raw+ep /usr/sbin/nft

COPY scripts/ /scripts/
RUN chmod +x /scripts/*.sh

USER wireguard:wireguard

ENTRYPOINT ["/scripts/wg-up.sh"]
