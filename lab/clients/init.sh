#!/bin/sh
# Containerlab runs this after connecting eth1. eth0 remains management-only.
set -eu
: "${CLIENT_IP:?CLIENT_IP is required}"
: "${CLIENT_MAC:?CLIENT_MAC is required}"
ip link set dev eth1 down
ip link set dev eth1 address "$CLIENT_MAC"
ip link set dev eth1 mtu 1500
ip address replace "$CLIENT_IP" dev eth1
ip link set dev eth1 up
