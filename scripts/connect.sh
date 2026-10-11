#!/usr/bin/env bash
# Read names and kinds from this repo's block-style topology, including defaults.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

fail() { echo "ERROR: $*" >&2; exit 1; }
for tool in awk sudo docker; do
    command -v "$tool" >/dev/null || fail "Missing command: $tool (run inside Ubuntu)."
done

inventory=$(awk '
    /^name:/ { lab=$2 }
    /^  defaults:/ { section="defaults"; next }
    /^  nodes:/ { section="nodes"; next }
    /^  [[:alnum:]_-]+:/ { section="" }
    section == "defaults" && /^    kind:/ { default_kind=$2 }
    section == "nodes" && /^    [[:alnum:]_-]+:[[:space:]]*$/ {
        node=$1; sub(/:$/, "", node); order[++count]=node
    }
    section == "nodes" && /^      kind:/ { kinds[node]=$2 }
    END {
        if (!lab || !count) exit 1
        for (i=1; i<=count; i++) {
            node=order[i]
            kind=(kinds[node] ? kinds[node] : default_kind)
            if (!kind) exit 1
            print lab, node, kind
        }
    }
' lab/evpn.clab.yml) || fail "Cannot read nodes/kinds from lab/evpn.clab.yml."

names=()
kinds=()
while read -r row_lab node kind; do
    lab_name=$row_lab
    names+=("$node")
    kinds+=("$kind")
done <<< "$inventory"

choice=${1:-}
menu=false
if [[ -z "$choice" ]]; then
    menu=true
    printf 'Nodes in %s:\n' "$lab_name"
    for i in "${!names[@]}"; do
        printf '  %2d) %-12s %s\n' "$((i + 1))" "${names[i]}" "${kinds[i]}"
    done
fi

while true; do
    if [[ "$menu" == true ]]; then
        read -r -p 'Select number or node name (q to quit): ' choice || exit 0
        [[ "$choice" == q ]] && exit 0
    fi
    selected=-1
    for i in "${!names[@]}"; do
        if [[ "$choice" == "${names[i]}" ]] ||
           { [[ "$menu" == true ]] && [[ "$choice" == "$((i + 1))" ]]; }; then
            selected=$i
            break
        fi
    done
    (( selected >= 0 )) && break
    [[ "$menu" == true ]] || fail "Unknown node '$choice'. Run make connect to list nodes."
    echo "Unknown selection '$choice'. Choose a listed number or node name." >&2
done

node=${names[selected]}
case "${kinds[selected]}" in
    arista_ceos|ceos) shell=Cli ;;
    linux) shell=sh ;;
    *) fail "Unsupported node kind '${kinds[selected]}' for $node." ;;
esac

container="clab-$lab_name-$node"
state=$(sudo docker inspect --format '{{.State.Status}}' "$container") ||
    fail "Cannot inspect $container. Check Docker and run make inspect."
[[ "$state" == running ]] || fail "$node is $state. Deploy the lab with make deploy."

printf 'Connecting to %s (%s). Use exit to disconnect.\n' "$node" "$shell"
exec sudo docker exec -it "$container" "$shell"
