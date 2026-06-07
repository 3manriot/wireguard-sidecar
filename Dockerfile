FROM alpine:3.21

RUN apk add --no-cache wireguard-tools nftables libnatpmp iproute2

COPY scripts/ /scripts/
RUN chmod +x /scripts/*.sh

ENTRYPOINT ["/scripts/wg-up.sh"]
