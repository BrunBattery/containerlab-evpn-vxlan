# Architecture

## Physical fabric

Two spines and four leaves form an eight-link fabric. Each leaf uses Ethernet1
to spine01 and Ethernet2 to spine02. Each spine uses EthernetN to leaf0N.
There are no spine-to-spine links, leaf peer links, or clients in Phase 1.
Leaf ports from Ethernet3 onward are available for later use.

Containerlab creates containers and virtual links - EOS handles routing.
Each switch has a startup config containing its interface addresses and BGP settings.

## IPv4 underlay

- Loopback0 is a unique /32 and also the configured BGP router ID.
- Every fabric link is a routed /31.
- Each switch originates only its own Loopback0 with an explicit BGP `network`.
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

Use the [README's Bash example](../README.md#running-the-lab) to access switch CLIs
from Ubuntu. Source configs
define no remote credentials, management VRF, or remote API service. Check the
running config before enabling remote access. Keep credentials out of Git.

## Overlay boundary

Loopback1 is reserved for a future VTEP /32 per leaf. Spines will carry VXLAN
traffic as IP transit devices. No VLANs, VNIs, tenant VRFs, or Vxlan1 interfaces
are configured yet.

Choose EVPN peering, route targets, and next-hop behavior before adding the overlay.
Options include eBGP through the spines or iBGP with route reflectors. Account for
the shared spine ASN and limited loopback reachability when choosing.
