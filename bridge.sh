#!/bin/bash

display_usage() {
    echo -e "\nUsage: $0 [up down]\n"
}

if [[ "$EUID" -ne 0 ]]; then
    echo "This script must be run as root!"
    display_usage
    exit 1
fi

if [ $# -le 0 ]; then
    echo "This script must be run with at least one argument."
    display_usage
    exit 1
fi

set -x

if [ "$1" == "up" ]; then
    
    if [ "$(dpkg -l | awk '/bridge-utils/ {print }' | wc -l)" -lt 1 ]; then
        apt install bridge-utils
    fi
    
    # Control Plane Bridge
    sudo brctl addbr br0
    sudo ip link set br0 up
    ip addr add 10.10.0.1/24 dev br0
    
    sudo ip link set vm1.cp up
    ip addr add 10.10.0.11/24 dev vm1.cp
    sudo brctl addif br0 vm1.cp
    
    sudo ip link set vm2.cp up
    ip addr add 10.10.0.12/24 dev vm2.cp
    sudo brctl addif br0 vm2.cp

    # We need to configure your firewall to allow these packets to flow back and forth over the bridge
    sudo iptables -A INPUT -i br0 -j ACCEPT
    sudo iptables -A INPUT -i vm1.cp -j ACCEPT
    sudo iptables -A FORWARD -i br0 -j ACCEPT
    
    brctl show
fi

if [ "$1" == "down" ]; then
    sudo ip link set br0 down
    sudo brctl delbr br0
fi
