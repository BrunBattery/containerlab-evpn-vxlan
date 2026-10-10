#!/usr/bin/env bash
# Loopback0 underlay checks. Also sourced by the EVPN/VXLAN verifier.
set -euo pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }
for tool in sudo docker timeout awk grep; do
    command -v "$tool" >/dev/null || fail "Missing command: $tool (run inside the Ubuntu VM)."
done
sudo -v
sudo docker info >/dev/null

nodes=(spine01 spine02 leaf01 leaf02 leaf03 leaf04)
for node in "${nodes[@]}"; do
    state=$(sudo docker inspect --format '{{.State.Running}}' "clab-evpn-$node") || fail "$node is missing."
    [[ "$state" == true ]] || fail "$node is not running."
done
echo "PASS: all six containers are running."

cli() {
    local output
    # Linux sudo and EOS privilege are separate; ping requires privileged EXEC.
    output=$(timeout 30s sudo -n docker exec "clab-evpn-$1" Cli -p 15 -c "$2" 2>&1) || {
        printf '%s\n' "$output" >&2
        fail "$1: command failed or timed out: $2"
    }
    printf '%s\n' "$output"
}

check_peer() {
    local peer=$1 asn=$2
    # EOS summary: Neighbor V AS MsgRcvd MsgSent InQ OutQ Up/Down State ...
    awk -v peer="$peer" -v asn="$asn" '
        $1 == peer && $3 == asn && $9 == "Estab" { found=1 }
        END { exit !found }
    ' <<< "$summary" || fail "$node: expected established peer $peer in AS $asn."
}

for node in "${nodes[@]}"; do
    summary=$(cli "$node" 'show ip bgp summary')
    printf '\n%s\n%s\n' "$node" "$summary"
    if [[ "$node" == spine* ]]; then
        host=1
        [[ "$node" == spine02 ]] && host=3
        for leaf in 1 2 3 4; do
            check_peer "10.0.$leaf.$host" "$((65100 + leaf))"
        done
    else
        leaf=$((10#${node: -2}))
        check_peer "10.0.$leaf.0" 65000
        check_peer "10.0.$leaf.2" 65000
    fi
done
echo "PASS: all 16 expected BGP peer entries are established (eight sessions)."

# Every leaf to all other loopbacks; each spine to all leaf loopbacks.
# Spine-to-spine loopbacks are intentionally excluded: both spines use AS 65000.
for node in "${nodes[@]}"; do
    targets=(11 12 13 14)
    if [[ "$node" == leaf* ]]; then
        local_id=$((10 + 10#${node: -2}))
        targets=(1 2 11 12 13 14)
    else
        local_id=$((10#${node: -2}))
    fi
    for target in "${targets[@]}"; do
        [[ "$target" == "$local_id" ]] && continue
        output=$(cli "$node" "ping 10.255.0.$target source 10.255.0.$local_id repeat 3")
        grep -Eq '(^|[[:space:]])0% packet loss|Success rate is 100 percent' <<< "$output" || {
            printf '%s\n' "$output" >&2
            fail "$node: loopback-sourced ping to 10.255.0.$target."
        }
    done
done
echo "PASS: all 28 expected directed loopback ping checks."

for leaf in 1 2 3 4; do
    node="leaf0$leaf"
    for remote in 1 2 3 4; do
        [[ "$leaf" == "$remote" ]] && continue
        prefix="10.255.0.$((10 + remote))/32"
        route=$(cli "$node" "show ip route $prefix")
        printf '\n%s -> %s\n%s\n' "$node" "$prefix" "$route"
        awk -v prefix="$prefix" '
            $1 == "B" && $2 == "E" && $3 == prefix { found=1 }
            END { exit !found }
        ' <<< "$route" || fail "$node: expected an installed eBGP route for $prefix."
        for host in 0 2; do
            next_hop="10.0.$leaf.$host,"
            awk -v hop="$next_hop" '
                { for (i=1; i<NF; i++) if ($i == "via" && $(i+1) == hop) found=1 }
                END { exit !found }
            ' <<< "$route" || fail "$node: $prefix is missing installed next hop ${next_hop%,}."
        done
    done
done
echo "PASS: two installed next hops for all 12 directed leaf-to-leaf routes."
echo "Loopback0 underlay checks passed."
