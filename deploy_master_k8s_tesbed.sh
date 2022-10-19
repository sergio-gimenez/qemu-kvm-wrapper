#!/bin/bash

display_usage() {
    echo -e "\nUsage: $0 [vm1 vm2 vm3] [tap ptnet]\n"
}

# check whether user had supplied -h or --help . If yes display usage
if [[ ($# == "--help") || $# == "-h" ]]; then
    display_usage
    exit 0
fi

set -x

# if hostname is not "master"
if [ "$(hostname)" != "master" ]; then
    echo "Changing hostname to master, please start again the VM and run this script again"
    echo "That way we avoid k8s nodes to have the same name"
    sudo sed -i "s/ubuntu/master/g" /etc/hostname
    sudo shutdown -P now
fi

# Install ifconfig and c compiler
sudo apt-get install net-tools build-essential -y

# Set up the interface
sudo ifconfig ens4 up
sudo ifconfig ens4


# Install ifconfig and c compiler
sudo apt-get install net-tools build-essential -y

# Set up the interface
sudo ifconfig ens4 up
sudo ifconfig ens4 10.10.0.11/24

# Compile and load netmap module
git clone https://github.com/luigirizzo/netmap.git
cd netmap || exit
./configure --no-drivers
make
sudo make install
sudo depmod -a
sudo modprobe netmap
cd ..

###########################
# Containerd Installation #
###########################

# Load overlay & br_netfilter modules
sudo modprobe overlay
sudo modprobe br_netfilter
cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

# Configure systctl to persist
cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

# Apply sysctl parameters
sudo sysctl --system

# Install containerd
sudo apt-get update
sudo apt-get install -y containerd

## Set the cgroup driver for runc to systemd

# Create the containerd configuration file (containerd by default takes the config looking
# at /etc/containerd/config.toml)
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml

# Set the cgroup driver for runc to systemd

# Modify the configuration file, setting SystemCgroup from false to true under
# [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
# section (around line 112) :
# TODO sudo vi  /etc/containerd/config.toml

# Restart containerd with the new configuration
sudo systemctl restart containerd

###########################
# Kubernetes installation #
###########################

# Update the apt package index and install packages needed to use the Kubernetes apt repository
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl

# Download the Google Cloud public signing key
sudo curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
# Add the Kubernetes apt repository
echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list

# install kubelet, kubeadm and kubectl, and pin their version
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# Initialize the master node with kubeadm, specifiying apiserver in ens4
sudo kubeadm init --apiserver-advertise-address=10.10.0.11 --pod-network-cidr=10.240.0.0/16

# Once kubeadm has bootstraped the K8s cluster, set proper access to the cluster from the CP/master node
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# This is in order to be able to create pods in the control-plane node
kubectl taint nodes --all node-role.kubernetes.io/control-plane-







