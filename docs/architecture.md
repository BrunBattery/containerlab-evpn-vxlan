# Architecture

## Physical fabric

Two spines and four leaves form an eight-link fabric. Each leaf uses Ethernet1
to spine01 and Ethernet2 to spine02. Each spine uses EthernetN to leaf0N.
Each leaf connects Ethernet3 to its matching Linux client. There are no
spine-to-spine links or leaf peer links.

Containerlab creates containers and virtual links - EOS handles routing.
Each switch has a startup config containing its interface addresses and BGP settings.

## IPv4 underlay

- Loopback0 is a unique /32, the BGP router ID, and the EVPN peering address.
- Every fabric link is a routed /31.
- Spines originate Loopback0. Leaves originate Loopback0 and Loopback1 (VTEP).
- Connected uplinks and management addresses are not redistributed into BGP.
- `ip routing` enables forwarding - `no switchport` makes each uplink Layer 3.

`no bgp default ipv4-unicast` requires explicit neighbor activation under
`address-family ipv4`.

## ASNs and ECMP

Both spines use ASN 65000. Leaves use 65101–65104. A leaf01 route to
leaf02's `10.255.0.12/32` has AS path `65000 65102` through either spine.
`maximum-paths 2 ecmp 2` permits two paths in BGP and the routing table.
Equal path attributes give each remote leaf loopback both spine next hops.
Each spine has one direct path to each leaf loopback.
See [EOS BGP documentation](https://www.arista.com/en/um-eos/eos-border-gateway-protocol-bgp)
for the multipath command.

Separate leaf ASNs preserve AS-loop protection without `allowas-in` or AS overrides.
The shared spine ASN gives leaves identical AS paths through either spine.
It also prevents spines from learning each other's loopbacks through leaves:
they reject paths containing their own ASN 65000. Leaves can reach both spines,
and both spines can reach all leaves. Revisit the ASN plan if spine-to-spine
loopback reachability is needed later.

The verifier checks installed ECMP next hops. Traffic distribution and failover
require separate tests.

## Management and access

`eth0` is the management interface - `eth1` maps to EOS Ethernet1, and so on.
Docker network `evpn-mgmt` uses `172.30.100.0/24`, separate from the fabric.
Use Loopback0-sourced pings to test fabric reachability.

See [switch and client access](../README.md#switch-and-client-access) for CLI
and shell commands. Source configs define no remote credentials, management VRF, or
remote API service. Check the
running config before enabling remote access. Keep credentials out of Git.

## eBGP EVPN overlay

Leaves peer with both spines using Loopback0 addresses. These eight sessions
activate only `address-family evpn`. The physical-link peers activate
only IPv4. Peer groups collect the overlay's shared settings.

`update-source Loopback0` fixes the session source. `ebgp-multihop 3` permits
loopback-based sessions. `send-community extended` carries route targets and
encapsulation information. On spines, `next-hop-unchanged` preserves the leaf's
VTEP next hop - replacing it with a spine would direct VXLAN at a non-VTEP.
These spines are eBGP transit peers, not iBGP route reflectors.
See [Arista's eBGP examples](https://www.arista.com/en/um-eos/eos-sample-configurations).

Loopback peering does not guarantee alternate reachability to a spine. If a
leaf's direct uplink fails, the shared spine ASN prevents an indirect route to
that spine's loopback. The other spine's EVPN session remains available.

## L2 VXLAN service

Each leaf maps VLAN 10 to VNI 10010 on Vxlan1, sourced from Loopback1.
RD `<Loopback0>:10` identifies each leaf's route uniquely. RT `65000:10010`
matches across all four leaves so they import the same service.
`redistribute learned` advertises local MACs as EVPN Type 2 routes.
Type 3 (IMET) routes populate the head-end replication list for broadcast,
unknown-unicast, and multicast traffic. No static flood list is configured.
See [Arista's L2 EVPN lab](https://labguides.testdrive.arista.com/2024.3/data_center/l2_evpn/).

Client01 reaches client02 as follows:

1. Leaf02 learns client02's MAC and advertises it with VTEP `10.255.1.12`.
2. Leaf01 imports the route and encapsulates frames using VNI 10010.
3. A spine routes the outer IP packet to leaf02 using the IPv4 underlay.
4. Leaf02 decapsulates and bridges to client02 on Ethernet3.

Clients use 1500-byte IP MTU. Fabric veth links and EOS routed ports use 9000,
allowing the extra VXLAN headers. IPv4 VXLAN needs 1550 bytes of transport IP
MTU for a 1500-byte untagged inner IP packet. Verification uses 1472-byte ICMP
payloads with fragmentation disabled. [VXLAN format](https://www.rfc-editor.org/rfc/rfc7348.html)

Clients have management on eth0 and service traffic on eth1. The verifier binds
pings to eth1 to prove fabric forwarding. No service gateway, tenant VRF, L3 VNI,
or IRB is configured - the service provides same-subnet bridging only.
