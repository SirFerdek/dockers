# vpn_nat_router

Container that routes traffic from isolated docker network (without direct internet access) through VPN gateway.

## Principle of operation

Let's say you have a bunch of containers that you want to connect with each other and to the Internet, but due to *reasons* the Internet access must be routed through your VPN provider. There exist solutions for that exact problem that force you to modify configuration and possibly contents of every container to make them use a *gateway* container exposing SOCKS proxy. This is not ideal and we can do better - here's how.

Ask yourself a question - if you had a bunch of devices in your LAN that you would like to isolate and route their traffic differently from others, with no reconfiguration of the clients required, how would you do that? VLANs. We can emulate this in Docker, however, we will be using just plain simple `bridge` driver with some tricks. 

### Create isolated docker network

```
docker network create -d bridge \
  --com.docker.network.bridge.name="underbridge" \
  --internal \
  --subnet=172.22.0.0/24 \
  --gateway=172.22.0.254 \
  --aux-address="DefaultGatewayIPv4=172.22.0.1" \
  underbridge
```

* `-d` selects network driver - we use `bridge`
* `--com.docker.network.bridge.name="underbridge"` sets created Linux bridge name to underbridge, just for clarity
* `--internal` creates isolated network - no external access is possible to the outside world, containers in the same network can communicate with each other
* `--subnet` configures address space for this network, and since we do not provide `--ip-range` option, whole subnet is available for containers (with some exceptions that follow)
* `--gateway` is not really a required argument when creating *internal* network, but when not provided, a default value of `172.22.0.1` would be used in case of this network. This gateway option specifies which IP address should be reserved for the host inside the network to work as a gateway to the external world. No other container can have this IP address, even when specified manually (Docker will not allow you to do this). All of this is done by Docker just to be sure that everything works correctly when you change your mind sometime in the future and switch this network from *internal* to *non-internal*. Since in our case this gateway will not be used, this option effectively frees first address in the subnet by moving the gateway to the last address.
* `--aux-address="DefaultGatewayIPv4=172.22.0.1` this is where the magic starts to happen - `--aux-address` reserves specified IP addresses so they will not by automatically assigned by Docker to running containers in this subnet. The additional option `DefaultGatewayIPv4` has a side-effect that forces it to be configured as a default gateway for all containers in this network.

Now just go and create containers in `underbridge` network like usual. They will not have internet access yet - every external connection would try to reach default gateway which is configured as `172.22.0.1`, but there is nothing with such IP address, yet.

### Cherry on top - running the VPN router

Ok, not yet, I lied. Docker manages host's iptables rules. When we created *internal* network, it locked it down so no data could escape it and no data could be forwarded inside it. We effectively want to create a router (packet forwarder) inside this isolated network, so we need to loosen those rules a little bit.

Without disabling Docker's iptables rules management, we can achieve our goal by making sure following rules are added to iptables after each reboot and iptables reloaded (if I remember correctly Docker's handling of iptables will not override them):

`/etc/iptables/iptables_noflush.rules`

```
*filter
:DOCKER-USER - [0:0]

-A DOCKER-USER ! -s 172.22.0.0/24 -d 172.22.0.0/24 -o underbr -i underbr -j ACCEPT
-A DOCKER-USER -s 172.22.0.0/24 ! -d 172.22.0.0/24 -o underbr -i underbr -j ACCEPT

-A DOCKER-USER -j RETURN
COMMIT
```

For example on Void Linux, create such service:

`/etc/sv/iptables_noflush/run`

```
#!/bin/sh
[ ! -e /etc/iptables/iptables_noflush.rules ] && exit 0
iptables-restore -n -w 3 /etc/iptables/iptables_noflush.rules || exit 1
exec chpst -b iptables pause
```

Docker-compose for running `vpn_nat_router`

```
version: '2.4'
services:
  app:
    image: "sirferdek/vpn_nat_router:latest"
    container_name: vpn
    restart: unless-stopped
    networks:
      underbridge:
        priority: 50 #eth1
      web:
        priority: 100 #eth0
    volumes:
      - /srv/appdata/vpn:/config #volume with your openvpn configuration
      - /srv/appdata/vpn/openvpn_credentials:/run/secrets/openvpn_credentials #file with "username\npassword\n" is mounted separately as secret
      - /etc/localtime:/etc/localtime:ro
    environment:
      CONFIG: "openvpn_config_filename.ovpn"
      IP_ADDR: "172.22.0.1/24"
      DNS: "1.1.1.1"
      PORT_FWD: "172.22.0.128:4666"
      TZ: "UTC"
    cap_add:
      - NET_ADMIN
    sysctls:
      net.ipv4.ip_forward: 1
    devices:
      - "/dev/net/tun"
networks:
  underbridge:
    external: true
  web:
    external: true
 ```
 
 * network priorities help in predicting order of ethX inside container
 * `web` network is non-isolated network with direct internet access (only this container should have it)
 * `IP_ADDR: "172.22.0.1/24"` the secret sauce is right here - every other container has 172.22.0.1 default gateway setup by Docker and our container will give itself this exact IP address when started.


For more details and how port forwarding is done, enforcing DNS and other crazy stuff, please take a look inside entrypoint script.
