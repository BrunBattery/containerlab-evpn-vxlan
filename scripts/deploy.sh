#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

command -v containerlab >/dev/null || { echo "Install Containerlab in the Ubuntu VM first." >&2; exit 1; }
command -v docker >/dev/null || { echo "Install Docker Engine in the Ubuntu VM first." >&2; exit 1; }
sudo docker info >/dev/null
# The topology uses image-pull-policy: Never; import the image before deploying.
sudo containerlab deploy --topo lab/evpn.clab.yml
