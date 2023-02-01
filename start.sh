#!/bin/bash

display_usage() {
    echo -e "\nUsage: $0 [vm1 vm2 vm3] [tap netmap]\n"
}

# check whether user had supplied -h or --help . If yes display usage
if [[ ($# == "--help") || $# == "-h" ]]; then
    display_usage
    exit 0
fi

# display usage if the script is not run as root user
if [[ "$EUID" -ne 0 ]]; then
    echo "This script must be run as root!"
    exit 1
fi

# if less than two arguments supplied, display usage
if [ $# -le 1 ]; then
    echo "This script must be run with at least two arguments."
    display_usage
    exit 1
fi

CUR_PATH=$(pwd)
VM_NAME="$1"
NUM="${VM_NAME: -1}"
BACK_IFNAME="$3"

if [ "$2" == "tap" ]; then
    NET_FRONTEND="virtio-net-pci"
    NET_BACKEND="tap"
    BACK_IFNAME=""$VM_NAME".cp"
    IFUP_SCRIPTS=",script=no,downscript=no"

elif [ "$2" == "netmap" ]; then
    # Make sure netmap module is loaded
    if ! lsmod | grep "netmap" &>/dev/null; then
        echo "netmap module is not loaded. Loading."
        if modprobe netmap; then
            echo "netmap module loaded."
        else
            echo "Failed to load netmap module, please compile and install it for your current kernel version: $(uname -r)."
            exit 1
        fi
    fi
    NET_FRONTEND="ptnet-pci"
    NET_BACKEND="netmap"
    if [ ! -n "$BACK_IFNAME" ]; then
        if [ "$NUM" == "1" ]; then
            BACK_IFNAME_1="vale1:1{1"
            BACK_IFNAME_2="vale1:2{1"
        elif [ "$NUM" == "2" ]; then
            BACK_IFNAME_1="vale1:}1"
            BACK_IFNAME_2="vale2:}1"
        fi
        echo "Backend interface name not specified, using default: $BACK_IFNAME"
    fi
    IFUP_SCRIPTS=",passthrough=on"
else

    echo "Unknown network type"
    display_usage
    exit 1
fi

# Boot the vm
set -x
sudo qemu-system-x86_64 \
    "$CUR_PATH"/"$VM_NAME".img \
    -m 8G --enable-kvm -pidfile $VM_NAME.pid \
    -cpu host -smp 4 \
    -serial file:"$VM_NAME".log \
    -device e1000,netdev=mgmt,mac=00:AA:BB:CC:01:99 -netdev user,id=mgmt,hostfwd=tcp::202"$NUM"-:22,hostfwd=tcp::300"$NUM"-:8000 \
    -device "$NET_FRONTEND",netdev=data1,mac=00:0a:0a:0a:0"$NUM":01, -netdev $NET_BACKEND,ifname="$BACK_IFNAME_1",id=data1"$IFUP_SCRIPTS" \
    -device "$NET_FRONTEND",netdev=data2,mac=00:0a:0a:0a:0"$NUM":02, -netdev $NET_BACKEND,ifname="$BACK_IFNAME_2",id=data2"$IFUP_SCRIPTS" &
