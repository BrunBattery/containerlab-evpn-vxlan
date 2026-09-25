# Addressing plan

All allocated IPv4 ranges are RFC 1918 private space. Check the VM, Docker,
VMware NAT, and any VPN routes for conflicts before deployment. These tables
describe the fabric - the VM's NIC gets its address from the VMware network.

## Nodes

| Node | ASN | Loopback0 / router ID | Docker management IPv4 |
| --- | --- | --- | --- |
| spine01 | 65000 | 10.255.0.1/32 | 172.30.100.11/24 |
| spine02 | 65000 | 10.255.0.2/32 | 172.30.100.12/24 |
| leaf01 | 65101 | 10.255.0.11/32 | 172.30.100.21/24 |
| leaf02 | 65102 | 10.255.0.12/32 | 172.30.100.22/24 |
| leaf03 | 65103 | 10.255.0.13/32 | 172.30.100.23/24 |
| leaf04 | 65104 | 10.255.0.14/32 | 172.30.100.24/24 |

Management belongs to Docker network `evpn-mgmt`, subnet `172.30.100.0/24`.
Containerlab assigns the management gateway. Source EOS configs contain no
management IPs or default routes.

## Point-to-point links

For leaf N, use `10.0.N.0/31` to spine01 and `10.0.N.2/31` to spine02.
The spine gets the even address - the leaf gets the odd address.

| Subnet | Spine interface | Spine address | Leaf interface | Leaf address |
| --- | --- | --- | --- | --- |
| 10.0.1.0/31 | spine01 Ethernet1 | 10.0.1.0/31 | leaf01 Ethernet1 | 10.0.1.1/31 |
| 10.0.1.2/31 | spine02 Ethernet1 | 10.0.1.2/31 | leaf01 Ethernet2 | 10.0.1.3/31 |
| 10.0.2.0/31 | spine01 Ethernet2 | 10.0.2.0/31 | leaf02 Ethernet1 | 10.0.2.1/31 |
| 10.0.2.2/31 | spine02 Ethernet2 | 10.0.2.2/31 | leaf02 Ethernet2 | 10.0.2.3/31 |
| 10.0.3.0/31 | spine01 Ethernet3 | 10.0.3.0/31 | leaf03 Ethernet1 | 10.0.3.1/31 |
| 10.0.3.2/31 | spine02 Ethernet3 | 10.0.3.2/31 | leaf03 Ethernet2 | 10.0.3.3/31 |
| 10.0.4.0/31 | spine01 Ethernet4 | 10.0.4.0/31 | leaf04 Ethernet1 | 10.0.4.1/31 |
| 10.0.4.2/31 | spine02 Ethernet4 | 10.0.4.2/31 | leaf04 Ethernet2 | 10.0.4.3/31 |

Each BGP neighbor is the other endpoint in this table. The remote ASN is the
peer node's ASN in the node table.

## Reserved space: not configured

| Purpose | Reservation | Proposed convention |
| --- | --- | --- |
| Additional underlay links | Remaining 10.0.0.0/16 | Continue per-leaf /31 pairs |
| Router IDs | Remaining 10.255.0.0/24 | Unique Loopback0 /32s |
| VTEP loopbacks | 10.255.1.0/24 | leaf01–04: 10.255.1.11–14/32 on Loopback1 |
| Tenant subnets | 10.10.0.0/16 | Later: 10.10.10.0/24 and 10.10.20.0/24 for tenant 1 |
| Additional tenant subnets | 10.20.0.0/16 | Tenant 2 - assign with its VRF/VNI plan |

Reservations do not overlap with each other or management. Configure individual
subnets and addresses, not the full allocation blocks.
