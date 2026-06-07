FROM alpine:3.21

RUN apk add --no-cache wireguard-tools nftables libnatpmp iproute2
RUN addgroup -g 1000 -S wireguard && adduser -u 1000 -S wireguard -G wireguard
RUN chown root:wireguard /etc/wireguard && chmod 750 /etc/wireguard

COPY scripts/ /scripts/
RUN chmod +x /scripts/*.sh

USER wireguard:wireguard

ENTRYPOINT ["/scripts/wg-up.sh"]
