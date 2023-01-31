#!/bin/bash

display_usage() {
    echo -e "\nUsage: $0 [master worker] [1 2]\n"
}

if [[ ("$1" == "master" || "$1" == "worker") ]]; then
    node_name=$1
else
    echo "Please specify the node name as master or worker"
    exit 1
fi

one_digit_id=$2

# check whether user had supplied -h or --help . If yes display usage
if [[ ($# == "--help") || $# == "-h" ]]; then
    display_usage
    exit 0
fi

# Change VM hostname according to either "master" or "worker"
sudo hostname -b "$node_name"

set -x
###########################
# Install Prerequisites   #
###########################

# Install ifconfig, a c compiler, jq, and bridge
sudo apt-get update
sudo apt-get install net-tools build-essential -y

# Compile and load netmap module
git clone https://github.com/luigirizzo/netmap.git
cd netmap || exit
./configure --no-drivers
make
sudo make install
sudo depmod -a
sudo modprobe netmap
cd ..

# Set up the interface
sudo ifconfig ens4 up
node_ip="10.10.0.1$one_digit_id"
sudo ifconfig ens4 "$node_ip/24"
