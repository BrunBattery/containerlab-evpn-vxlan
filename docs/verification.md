# Phase 1 verification

Run `make verify` in the Ubuntu VM after EOS has booted. The script exits nonzero
at the first failed check and prints the node or command involved.
It requires Bash, Docker, sudo, awk, grep, and GNU timeout.

## Recorded environment

Versions recorded on 2026-10-07, separately from the earlier successful full
`make verify` run:

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

## Acceptance matrix

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

A successful `make verify` run in Ubuntu confirmed all six containers, eight
BGP sessions, 28 directed pings, and 12 ECMP route checks.

The parser expects `Estab`, ping loss/success text, and `via <address>,` routes. Update the
verifier's fixed addresses when extending the topology.

## Manual inspection

From the VM, enter leaf01:

```bash
sudo docker exec -it clab-evpn-leaf01 Cli
```

Then in EOS:

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

## Optional first failure experiment

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
leaf-to-leaf reachability. The full baseline verifier should fail during this
experiment because it requires both peers and next hops. Restore the link:

```text
configure terminal
interface Ethernet1
no shutdown
end
```

Rerun `make verify` after convergence. Do not save the temporary shutdown to
the startup config. Record the observed failover behavior.
