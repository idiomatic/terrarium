# Named networks

Every VM has a NAT network card that reaches the internet but not other VMs. A named network adds a second card on a private network that every VM naming it joins, so servers and clients can be tested against each other. VMs on it reach each other and the Mac; nothing leaves the Mac through it, and the NAT card stays, so each VM keeps its internet access.

```
terrarium network lab --subnet 192.168.200.0/24 \
    --reserve server=192.168.200.10 --reserve client1=192.168.200.11 --reserve client2=192.168.200.12
terrarium start nfs-server --ephemeral --network lab:server
terrarium start linux-client --ephemeral --network lab:client1
terrarium start linux-client --ephemeral --network lab:client2
server=$(terrarium addr $server_vm lab)
```

## Roles and addresses

The part after the colon is the VM's role on the network, its KEY. The network card's MAC address comes from the network's name and the KEY, and a reservation gives that KEY the same address at every start, however many VMs start from the same layer and in whatever order. Without a KEY, the role is the name of the layer or image the VM started from; a second running VM with the same role on a network is refused, so two VMs from one layer need two KEYs.

A reservation needs the network's subnet. Give one with `--subnet`, or let the first VM on the network start it, and terrarium records the subnet vmnet picked, so the network keeps it. A change to a network that is up takes effect once no VM is on it and it starts again.

`terrarium addr VM [NETWORK]` prints one address, for scripts: on the named network, or without one, on the NAT network. It asks the guest through its helper, and without one reads the Mac's DHCP leases. A guest that only gave itself a `169.254.x` address is reported as having no lease, which usually means the Mac's `bootpd` is not answering.

`terrarium network` lists the networks and which VMs are on each; `terrarium network NAME` shows one, with the MAC address each reservation is for. `ps` shows each VM's networks.

## Guests

macOS and Windows take an address on the new card by themselves. Linux images set up only their first card, so terrarium runs the `linux/network-dhcp` tweak at every start of a Linux VM with a named network, which starts DHCP on the others.

Windows puts the new network in its Public firewall profile, which drops pings and most connections from other VMs. Mark it Private, and allow what you need:

```
terrarium exec $vm powershell -Command "Set-NetConnectionProfile -InterfaceAlias 'Ethernet 2' -NetworkCategory Private"
```

Each VM also has an IPv6 ULA address on the network beside its link-local one.

## While it runs

The network lives while a small terrarium process holds it: the first VM to join starts it, and it ends once no VM is on the network. Killing that process cuts the VMs on the network off from each other (each VM notes it in its log). Worse, a hard kill (`kill -9`) while VMs are on it leaves vmnet holding the subnet even after they stop, as long as tested; the network then cannot start on that subnet, and terrarium says so. Choose another subnet with `terrarium network NAME --subnet CIDR`; a restart of the Mac likely frees the old one.

`terrarium network NAME --remove` removes a network that no VM is on, with everything it left.

## Apple containers

Containers made with Apple's `container` tool cannot join a named network yet (see [DEVELOPMENT.md](../DEVELOPMENT.md)). Those on its default network are reachable from terrarium VMs at their addresses there.
