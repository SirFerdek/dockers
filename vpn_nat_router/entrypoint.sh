#!/usr/bin/env sh

if [ -z "$CONFIG" ]; then
    echo "CONFIG is not set"
    exit 1
else
    echo "Using '$CONFIG' configuration file"
fi
if [ ! -f /run/secrets/openvpn_credentials ]; then
    echo "openvpn_credentials secret not found!"
    exit 1
fi
if [ -z "$IP_ADDR" ]; then
    echo "IP_ADDR is not set"
    exit 1
else
    echo "Using '$IP_ADDR' as ip address"
fi

echo "Setting up firewall..."
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -m conntrack --ctstate INVALID -j DROP
echo "Locked-down"

echo "Allowing outgoing traffic on tun0"
iptables -A OUTPUT -o tun0 -j ACCEPT
# iptables -A INPUT -i tun0 -j ACCEPT
echo "Setting IP address to $IP_ADDR on eth1"
ip addr add $IP_ADDR dev eth1
# echo "$( echo $IP_ADDR | cut -d'/' -f1 ) localhost" >> /etc/hosts
echo "Allowing bi-directional traffic on eth1"
iptables -A OUTPUT -o eth1 -j ACCEPT
iptables -A INPUT -i eth1 -j ACCEPT

echo "Setting up NAT on tun0"
iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE
echo "Allowing forwarding from eth1 to tun0"
iptables -A FORWARD -i eth1 -o tun0 -j ACCEPT
echo "Allowing returning traffic from tun0 to eth1"
iptables -A FORWARD -i tun0 -o eth1 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

remote=$(grep '^remote ' /config/$CONFIG)
remote_ip=$(echo $remote | cut -d' ' -f 2)
remote_port=$(echo $remote | cut -d' ' -f 3)

echo "Allowing connections to $remote_ip:$remote_port on eth0"
iptables -A OUTPUT -o eth0 -d $remote_ip -p udp --dport $remote_port -j ACCEPT
iptables -A OUTPUT -o eth0 -d $remote_ip -p tcp --dport $remote_port -j ACCEPT

if [ -z "$DNS" ]; then
    echo "Not enforcing DNS using DNAT"
else
    echo "Enforce $DNS as DNS for everything"
    # this takes care of docker daemon sending dns requests from within isolated network namespaces of other containers
    # - we are theirs default gateway
    iptables -t nat -A PREROUTING -p udp ! -d $DNS --dport 53 -j DNAT --to-destination $DNS
    iptables -t nat -A PREROUTING -p tcp ! -d $DNS --dport 53 -j DNAT --to-destination $DNS
    # this enforces dns for local processes, local name resoluton by docker should still work by placing this rule
    # after docker's 127.0.0.11 rule
    iptables -t nat -A OUTPUT -p udp ! -d $DNS --dport 53 -j DNAT --to-destination $DNS
    iptables -t nat -A OUTPUT -p tcp ! -d $DNS --dport 53 -j DNAT --to-destination $DNS
fi

if [ -z "$PORT_FWD" ]; then
    echo "Not creatng IP forwarding entry"
else
    fwd_ip="$( echo $PORT_FWD | cut -d':' -f1 )"
    fwd_port="$( echo $PORT_FWD | cut -d':' -f2 )"
    echo "Forwarding port $fwd_port incoming on tun0 to IP $fwd_ip"
    iptables -t nat -A PREROUTING -i tun0 -p tcp --dport $fwd_port -j DNAT --to $PORT_FWD
    iptables -t nat -A PREROUTING -i tun0 -p udp --dport $fwd_port -j DNAT --to $PORT_FWD
    # so far we allow only internally-initiated connections to be forwarded from tun0 to eth1
    # make traffic associated with forwarded port to also be allowed in FORWARDing
    iptables -A FORWARD -i tun0 -p tcp --dport $fwd_port -d $fwd_ip -j ACCEPT
    iptables -A FORWARD -i tun0 -p udp --dport $fwd_port -d $fwd_ip -j ACCEPT
fi

exec openvpn --status /config/status 30 --status-version 2 --config /config/$CONFIG --auth-user-pass /run/secrets/openvpn_credentials --auth-nocache --script-security 2 --up /etc/openvpn/up.sh --down /etc/openvpn/down.sh $@
