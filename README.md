# Arista EVPN/VXLAN lab

A six-switch Containerlab fabric with explicit Arista EOS configurations.
IPv4 eBGP and leaf ECMP are configured - EVPN/VXLAN is not yet implemented.

**Phase 1 - fabric foundation complete.** A successful `make verify` run in
Ubuntu confirmed BGP, forwarding, and installed ECMP. No Arista software is included.

## Architecture

![Lab topology](docs/images/topology.svg)

Every leaf connects to both spines over routed /31 links. Each switch advertises
its Loopback0 /32.

| Component | Current implementation |
| --- | --- |
| Network devices | Two spines and four leaves, Containerlab kind `arista_ceos` |
| Addressing | /31 uplinks in `10.0.0.0/16` - /32 loopbacks in `10.255.0.0/24` |
| Routing | Eight eBGP sessions - two next hops per remote leaf loopback |
| Management | Docker network `172.30.100.0/24` - CLI access via Docker |
| Image | Locally imported `ceos:4.36.2F` - automatic pulls disabled |
| Verification | Container state, BGP peers, loopback-sourced pings, installed ECMP |

Both spines use ASN 65000, so they do not learn each other's loopbacks through
leaves. See [architecture](docs/architecture.md) and [addressing](docs/addressing.md).

## Running the lab

The documented environment is Windows → VMware Workstation → Ubuntu VM →
Docker Engine → Containerlab → cEOS.

Follow [setup and daily operation](docs/setup.md) to prepare the VM and tools.

Once setup is complete, run from the repository root **inside Ubuntu**:

```bash
make deploy
make inspect
# Wait for EOS to boot and BGP to converge.
make verify
```

Access a switch CLI from Ubuntu - replace `<node>` with `spine01`, `spine02`, or `leaf01`–`leaf04`:

```bash
sudo docker exec -it clab-evpn-<node> Cli
```

[Verification](docs/verification.md) describes expected results and manual checks.
`make destroy` removes the deployed lab while retaining saved configuration
files. Read [configuration persistence](docs/setup.md#configuration-persistence)
before changing or resetting a lab.

## Repository layout

```text
lab/evpn.clab.yml       Nodes, image tag, management network, and links
lab/configs/*.cfg      Six explicit EOS startup configurations
docs/architecture.md   Routing design and limitations
docs/addressing.md     Interface, loopback, and ASN tables
docs/setup.md          Installation, access, and lab lifecycle
docs/verification.md   Acceptance checks and troubleshooting
scripts/              Deployment, teardown, and verification scripts
Makefile              deploy, destroy, inspect, verify shortcuts
```

## Scope and limitations

This baseline carries IPv4 loopback traffic. It has no EVPN address family,
VXLAN interfaces, tenant VRFs, attached clients, or leaf redundancy configuration.
Verification covers reachability and installed routes. It does not measure
performance, traffic distribution, or failover. Other EOS releases may require
changes to CLI output parsing.

## License

[MIT](LICENSE) covers this repository's original configurations, scripts, and
documentation. Arista EOS/cEOS remains separately licensed by Arista and is not
distributed here.
