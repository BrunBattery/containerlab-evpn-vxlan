#!/usr/bin/env bash
# EVPN/VXLAN acceptance checks. Run after EOS and EVPN have converged.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/verify.sh"

for client in client01 client02 client03 client04; do
    state=$(sudo docker inspect --format '{{.State.Running}}' "clab-evpn-$client") || fail "$client is missing."
    [[ "$state" == true ]] || fail "$client is not running."
done

for node in "${nodes[@]}"; do
    summary=$(cli "$node" 'show bgp evpn summary')
    printf '\n%s EVPN\n%s\n' "$node" "$summary"
    if [[ "$node" == spine* ]]; then
        for leaf in 1 2 3 4; do
            check_peer "10.255.0.$((10 + leaf))" "$((65100 + leaf))"
        done
    else
        check_peer 10.255.0.1 65000
        check_peer 10.255.0.2 65000
    fi
done
echo "PASS: all eight EVPN sessions established."

for leaf in 1 2 3 4; do
    node="leaf0$leaf"
    vxlan=$(cli "$node" 'show interfaces Vxlan1')
    grep -Fq 'Vxlan1 is up, line protocol is up' <<< "$vxlan" || fail "$node: Vxlan1 is not up."
    grep -Fq "Source interface is Loopback1 and is active with 10.255.1.$((10 + leaf))" <<< "$vxlan" || fail "$node: wrong VTEP source."
    grep -Fq 'Flood List Source: EVPN' <<< "$vxlan" || fail "$node: flood list is not learned through EVPN."
    grep -Fq 'Remote MAC learning via EVPN' <<< "$vxlan" || fail "$node: remote MAC learning is not EVPN."
    mappings=$(cli "$node" 'show vxlan vni')
    awk '$1 == 10010 && $2 == 10 { found=1 } END { exit !found }' <<< "$mappings" || fail "$node: missing VLAN 10 / VNI 10010 mapping."
    imet=$(cli "$node" 'show bgp evpn route-type imet')
    flood=$(cli "$node" 'show vxlan flood vtep vlan 10')
    for remote in 1 2 3 4; do
        [[ "$leaf" == "$remote" ]] && continue
        vtep="10.255.1.$((10 + remote))"
        route=$(cli "$node" "show ip route $vtep/32")
        awk -v prefix="$vtep/32" '$1 == "B" && $2 == "E" && $3 == prefix { found=1 } END { exit !found }' <<< "$route" || fail "$node: no installed eBGP route to $vtep."
        for host in 0 2; do
            awk -v hop="10.0.$leaf.$host," '
                { for (i=1; i<NF; i++) if ($i == "via" && $(i+1) == hop) found=1 }
                END { exit !found }
            ' <<< "$route" || fail "$node: $vtep is missing a spine next hop."
        done
        output=$(cli "$node" "ping $vtep source 10.255.1.$((10 + leaf)) repeat 3")
        grep -Eq '(^|[[:space:]])0% packet loss|Success rate is 100 percent' <<< "$output" || fail "$node: VTEP-sourced ping to $vtep."
        awk -v vtep="$vtep" '
            $1 == "*" { for (i=1; i<NF; i++) if ($i == "imet" && $(i+1) == vtep) found=1 }
            END { exit !found }
        ' <<< "$imet" || fail "$node: no valid IMET route for $vtep."
        # Command is restricted to VLAN 10. Continuation lines can contain VTEPs.
        awk -v vtep="$vtep" '
            { for (i=1; i<=NF; i++) if ($i == vtep) found=1 }
            END { exit !found }
        ' <<< "$flood" || fail "$node: $vtep missing from VLAN 10 flood list."
    done
done
echo "PASS: VTEP reachability, ECMP, VNI mapping, and remote IMET/flood membership on all leaves."

client_command() {
    local output
    output=$(timeout 30s sudo -n docker exec "clab-evpn-$1" "${@:2}" 2>&1) || {
        printf '%s\n' "$output" >&2
        fail "$1: client command failed: ${*:2}"
    }
    printf '%s\n' "$output"
}

# Warm up ARP/MAC learning before requiring zero loss on full-size packets.
for local_id in 1 2 3 4; do
    client="client0$local_id"
    for remote in 1 2 3 4; do
        [[ "$local_id" == "$remote" ]] && continue
        client_command "$client" ping -I eth1 -c 3 -W 2 "10.10.10.$((10 + remote))" >/dev/null
    done
done

for local_id in 1 2 3 4; do
    node="leaf0$local_id"
    routes=$(cli "$node" 'show bgp evpn route-type mac-ip')
    macs=$(cli "$node" 'show vxlan address-table')
    for remote in 1 2 3 4; do
        [[ "$local_id" == "$remote" ]] && continue
        mac="0200.0000.000$remote"
        vtep="10.255.1.$((10 + remote))"
        awk -v mac="$mac" '$1 == "*" && index($0, mac) { found=1 } END { exit !found }' <<< "$routes" || fail "$node: missing valid Type 2 route for $mac."
        awk -v mac="$mac" -v vtep="$vtep" '
            $1 == 10 && $2 == mac { for (i=3; i<=NF; i++) if ($i == vtep) found=1 }
            END { exit !found }
        ' <<< "$macs" || fail "$node: $mac is not installed through VTEP $vtep."
        output=$(client_command "client0$local_id" ping -I eth1 -M do -s 1472 -c 3 -W 2 "10.10.10.$((10 + remote))")
        grep -Eq '(^|[[:space:]])0% packet loss' <<< "$output" || {
            printf '%s\n' "$output" >&2
            fail "client0$local_id: full-size ping to client0$remote lost packets."
        }
    done
done
echo "PASS: remote Type 2 MAC installation and all 12 directed full-size client pings."
echo "EVPN/VXLAN checks passed. This does not measure traffic distribution or convergence time."
