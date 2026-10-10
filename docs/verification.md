# Verification

Run `make verify` in the Ubuntu VM after EOS has booted. The script exits nonzero
at the first failed check and prints the node or command involved.
It requires Bash, Docker, sudo, awk, grep, and GNU timeout.

`make verify` checks the underlay, EVPN overlay, and client forwarding.
Use `make verify-underlay` to check only Loopback0 peers, reachability, and ECMP.

For manual checks, use [switch and client access](../README.md#switch-and-client-access)
to open the leaf01 CLI or client01 shell.

## Recorded validation

Live `make verify` passed in Ubuntu, recorded on 2026-10-09.
All ten containers, eight IPv4 BGP sessions, eight EVPN sessions, VTEP routes,
remote MAC installation, and all 12 directed full-size client pings passed.

```text
PASS: all eight EVPN sessions established.
PASS: VTEP reachability, ECMP, VNI mapping, and remote IMET/flood membership on all leaves.
PASS: remote Type 2 MAC installation and all 12 directed full-size client pings.
```

Environment versions recorded on 2026-10-07:

| Component | Version |
| --- | --- |
| Ubuntu | 24.04.5 LTS |
| Docker Engine | 29.8.1 |
| Containerlab | 0.79.0 |
| cEOS (leaf01) | 4.36.2F-49692818.4362F (engineering build) |

Leaf01's route to leaf02's Loopback0 shows both installed spine next hops:

```text
 B E      10.255.0.12/32 [200/0]
           via 10.0.1.0, Ethernet1
           via 10.0.1.2, Ethernet2
```

### EVPN sample - leaf01

Captured after `make verify` generated client traffic. Selected entries:

```text
show bgp evpn summary
  Neighbor   V AS           MsgRcvd   MsgSent  InQ OutQ  Up/Down State   PfxRcd PfxAcc PfxAdv
  10.255.0.1 4 65000            180       182    0    0 02:12:18 Estab   6      6      6
  10.255.0.2 4 65000            179       183    0    0 02:12:18 Estab   6      6      4

show bgp evpn route-type mac-ip
            Network                Next Hop              Metric  LocPref Weight  Path
 * >Ec      RD: 10.255.0.12:10 mac-ip 0200.0000.0002
                                   10.255.1.12           -       100     0       65000 65102 i
 *  ec      RD: 10.255.0.12:10 mac-ip 0200.0000.0002
                                   10.255.1.12           -       100     0       65000 65102 i

show vxlan address-table
VLAN  Mac Address     Type      Prt  VTEP             Moves   Last Move
  10  0200.0000.0002  EVPN      Vx1  10.255.1.12      1       0:01:59 ago
```

Both BGP paths retain leaf02's VTEP next hop `10.255.1.12`. The same VTEP is
installed for client02's MAC in VLAN 10.

## Underlay checks

| Check | Expected result |
| --- | --- |
| Containers | All six `clab-evpn-<node>` containers running |
| BGP on each spine | Four expected neighbors, ASNs 65101–65104, state `Estab` |
| BGP on each leaf | Two expected neighbors in ASN 65000, state `Estab` |
| Sessions overall | Eight sessions, represented by 16 peer entries |
| Leaf to other leaf Loopback0 | Reachable with a Loopback0 source |
| Leaf to each spine Loopback0 | Reachable with a Loopback0 source |
| Spine to each leaf Loopback0 | Reachable with a Loopback0 source |
| Spine to other spine Loopback0 | Not expected - shared-AS loop prevention |
| Each leaf's routes to three remote leaves | Both directly attached spine next hops installed |

The underlay checks cover 28 directed Loopback0 pings and 12 ECMP routes.

The parser expects `Estab`, ping loss/success text, and `via <address>,` routes. Update the
verifier's fixed addresses when extending the topology.

## EVPN and VXLAN checks

| Check | Expected result |
| --- | --- |
| Clients | All four running, eth1 configured by topology startup commands |
| EVPN peers | Two per leaf, four per spine - eight loopback-based eBGP sessions |
| VTEP underlay routes | Each leaf installs two spine next hops to all three remote Loopback1 /32s |
| VTEP pings | All 12 directed Loopback1-sourced checks pass |
| Vxlan1 | Up, correct Loopback1 source, remote MAC/flood learning through EVPN |
| Service mapping | VLAN 10 / VNI 10010 on all leaves |
| Type 3 / flood list | All three remote VTEPs present per leaf |
| Type 2 / remote MACs | All three remote client MACs valid in BGP and installed through their VTEPs |
| Client forwarding / MTU | All 12 directed eth1 pings pass with 1472-byte payload and no fragmentation |

The verifier warms up ARP/MAC learning before checking zero-loss client pings.
Idle clients' learned MACs and Type 2 routes can age out while EVPN sessions
remain established. Generate client traffic before capturing MAC tables.
Binding to eth1 avoids the Docker management path. With IPv4 and ICMP headers,
1472 bytes of payload tests a 1500-byte host IP packet inside VXLAN.
These checks do not measure traffic distribution or convergence time.

## EVPN and VXLAN manual inspection

Use the EOS CLI on leaf01 after client traffic has populated MACs:

```text
show ip route 10.255.1.12/32
show bgp evpn summary
show bgp evpn route-type imet
show bgp evpn route-type mac-ip
show interfaces Vxlan1
show vxlan flood vtep vlan 10
show vxlan address-table
```

EVPN peers are `10.255.0.1` and `10.255.0.2`. Expect client02 MAC
`0200.0000.0002` through VTEP `10.255.1.12`. RT `65000:10010` must be carried
and imported by the shared service.
In client01's shell, inspect networking and test full-size traffic to client02:

```sh
ip -br address
ip route
ip neigh
ping -I eth1 -M do -s 1472 -c 3 10.10.10.12
```

The scripts parse EOS text output. If output differs, review raw CLI results
before treating a parser failure as a network failure.

## Underlay manual inspection

In leaf01's EOS CLI:

```text
enable
show interfaces status
show ip interface brief
show ip bgp summary
show ip bgp 10.255.0.12/32
show ip route 10.255.0.12/32
ping 10.255.0.12 source 10.255.0.11 repeat 5
```

Ethernet1 and Ethernet2 should be routed and up with `10.0.1.1/31` and
`10.0.1.3/31`. Peers `10.0.1.0` and `10.0.1.2` should be established in AS 65000.
Both BGP paths to `10.255.0.12/32` should carry AS path `65000 65102`.
The IP route should have next hops `10.0.1.0` through Ethernet1 and `10.0.1.2`
through Ethernet2.

On spine01, expect four leaf neighbors and a direct route to each leaf loopback
via its odd-numbered link address. Remote transit-link networks are not advertised.

## Optional uplink failure test

Once the baseline passes, disable leaf01 Ethernet1 in its CLI:

```text
enable
configure terminal
interface Ethernet1
shutdown
end
show ip route 10.255.0.12/32
ping 10.255.0.12 source 10.255.0.11 repeat 5
```

After convergence, expect only `10.0.1.2` through spine02 and continued
leaf-to-leaf reachability. Also test client01-to-client02 traffic using the
command above. Leaf01 loses EVPN reachability to spine01's loopback, while
the spine02 session and VXLAN forwarding should remain available after
convergence. Record packet loss and recovery behavior.

The full verifier should fail during this test because it requires both peers
and next hops. Restore the link:

```text
configure terminal
interface Ethernet1
no shutdown
end
```

Rerun `make verify` after convergence. Do not save the temporary shutdown to
the startup config. Record the observed failover behavior.
