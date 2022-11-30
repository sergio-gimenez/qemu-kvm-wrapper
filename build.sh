#!/bin/bash

display_usage() {
    echo -e "\nUsage: $0 [vm1 vm2 vm3] [tap ptnet]\n"
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

# if less than one arguments supplied, display usage
if [ $# -le 1 ]; then
    echo "This script must be run with at least one argument."
    display_usage
    exit 1
fi

CLOUD_BASE_IMG="ubuntu-20.04-server-cloudimg-amd64.img"
CUR_PATH=$(pwd)
MISSING=""
FOUND=""
VM_NAME="$1"
NUM="${VM_NAME: -1}"
BACK_IFNAME="$3"

checkdep() {
    local exe="$1" package="$2" upstream="$3"
    if command -v "$1" >/dev/null 2>&1; then
        FOUND="${FOUND:+${FOUND} }$exe"
        return "0"
    fi
    MISSING=${MISSING:+${MISSING}$package}
    echo "missing $exe."
    echo "  It can be installed in package: $package"
    [ -n "$upstream" ] &&
    echo "  Upstream project url: $upstream"
    return 1
}

checkdep cloud-localds cloud-image-utils http://launchpad.net/cloud-utils
checkdep qemu-img qemu-utils http://qemu.org/
checkdep qemu-system-x86_64 qemu-system-x86 http://qemu.org/
checkdep wget wget

if [ -n "$MISSING" ]; then
    echo
    [ -n "${FOUND}" ] && echo "found: ${FOUND}"
    echo "install missing deps with:"
    echo "  apt-get update && apt-get install ${MISSING}"
else
    echo "All needed dependencies properly installed. (${FOUND})"
fi

# Check if base image exists
if [ ! -f "${CUR_PATH}/${CLOUD_BASE_IMG}" ]; then
    echo "Base image ${CLOUD_BASE_IMG} not found in ${CUR_PATH}, donwloading..."
    
    wget -O "${CUR_PATH}/${CLOUD_BASE_IMG}" \
    "https://cloud-images.ubuntu.com/releases/focal/release/ubuntu-20.04-server-cloudimg-amd64.img"
fi

# Create an overlay image
qemu-img create -f qcow2 -b "$CLOUD_BASE_IMG" "$VM_NAME".img

qemu-img resize "$VM_NAME".img +22G

# Build seed image with the user data and the networking config
# TODO This net conf is not working
# cloud-localds -v --network-config="$CUR_PATH"/net_conf_vm2.yaml \
#     "$CUR_PATH"/seed_"$VM_NAME".img "$CUR_PATH"/user-data.yaml
cloud-localds "$CUR_PATH"/seed_"$VM_NAME".img "$CUR_PATH"/user-data.yaml

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
        BACK_IFNAME="vale2:1}2"
        echo "Backend interface name not specified, using default: $BACK_IFNAME"
    fi
    IFUP_SCRIPTS=",passthrough=on" # The comma here is on purpose and mandatory
    
else
    
    echo "Unknown network type"
    display_usage
    exit 1
fi

# Boot the vm
sudo qemu-system-x86_64 \
-hda "$CUR_PATH"/"$VM_NAME".img \
-hdb "$CUR_PATH"/seed_"$VM_NAME".img \
-m 8G --enable-kvm -pidfile $VM_NAME.pid \
-cpu host -smp 4 \
-serial file:"$VM_NAME".log \
-device e1000,netdev=mgmt,mac=00:AA:BB:CC:01:99 -netdev user,id=mgmt,hostfwd=tcp::202"$NUM"-:22,hostfwd=tcp::300"$NUM"-:3000 \
-device "$NET_FRONTEND",netdev=data1,mac=00:0a:0a:0a:0"$NUM":01, -netdev $NET_BACKEND,ifname="$BACK_IFNAME",id=data1"$IFUP_SCRIPTS" &

echo "Waiting the VM to boot..."
sleep 35


echo "VM $VM_NAME has been properly built"
echo "You can connect to it with: ssh ubuntu@localhost -p 202$NUM"


