FROM alpine:3.21

RUN apk add --no-cache wireguard-tools nftables libnatpmp iproute2 \
    && adduser -D -u 1000 wg

COPY scripts/ /scripts/
RUN chmod +x /scripts/*.sh

USER wg
