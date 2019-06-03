FROM alpine:edge

# RUN echo "@testing http://nl.alpinelinux.org/alpine/edge/testing" >> /etc/apk/repositories
RUN apk add --no-cache ca-certificates iptables openvpn

COPY entrypoint.sh /entrypoint.sh
VOLUME ["/config"]
ENTRYPOINT ["/entrypoint.sh"]