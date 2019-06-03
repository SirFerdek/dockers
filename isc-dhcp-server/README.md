# ISC DHCP server
Simple to the bone isc-dhcp-server on ubuntu:latest

Running container
-----------------

Automatic restart (also on-boot), binding dhcpd.conf and dhcpd.leases from host, dhcpd listening on *eno1* only:

```
docker run -d -v /var/lib/dhcp:/var/lib/dhcp -v /etc/dhcp/dhcpd.conf:/etc/dhcp/dhcpd.conf --net=host --name=dhcp --restart=always sirferdek/isc-dhcp-server eno1
```
(see also run script)

Configuration
-------------

You must provide _dhcpd.conf_, which will reside on volume binded to container. If you don't have template dhcpd.conf, you can find one in this repo.

Logs
----

Nothing spectacular...

```
docker logs dhcp
```

Known issues
------------

Container does not respond to [CTRL]+[C]...
