#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

command -v containerlab >/dev/null || { echo "Containerlab is not installed." >&2; exit 1; }
# Preserve generated flash/startup-config files for the next deployment.
sudo containerlab destroy --topo lab/evpn.clab.yml
