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
K8S_VERSION=1.25.0-00

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
sudo apt-get install net-tools build-essential jq bridge-utils -y

# Set up the interface
sudo ifconfig ens4 up
node_ip="10.10.0.1$one_digit_id"
sudo ifconfig ens4 "$node_ip/24"

# # Compile and load netmap module

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

# # Install containerd
# sudo apt-get update && sudo apt-get install -y containerd
wget https://github.com/containerd/containerd/releases/download/v1.6.15/containerd-1.6.15-linux-amd64.tar.gz
tar xvf containerd-1.6.15-linux-amd64.tar.gz
sudo systemctl stop containerd
sudo cp bin/* /usr/local/bin/
sudo systemctl start containerd
## Set the cgroup driver for runc to systemd

# Create the containerd configuration file (containerd by default takes the config looking
# at /etc/containerd/config.toml)
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml
# sudo sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/' /etc/containerd/config.toml
# sudo rm /etc/containerd/config.toml

# Restart containerd with the new configuration
sudo systemctl restart containerd

# disable swap
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab



###########################
# Kubernetes installation #
###########################

# Update the apt package index and install packages needed to use the Kubernetes apt repository
sudo apt-get update && sudo apt-get install -y apt-transport-https curl

# Download the Google Cloud public signing key
sudo curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
# Add the Kubernetes apt repository
echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list

# install kubelet, kubeadm and kubectl, and pin their version
sudo apt-get update
sudo apt-get install -y kubelet=$K8S_VERSION kubeadm=$K8S_VERSION kubectl=$K8S_VERSION
sudo apt-mark hold kubelet kubeadm kubectl

if [ "$node_name" == "master" ]; then
    # Initialize the cluster
    # Initialize the master node with kubeadm, specifiying apiserver in ens4
    sudo kubeadm init --apiserver-advertise-address="$node_ip" --pod-network-cidr=10.240.0.0/16

    # Once kubeadm has bootstraped the K8s cluster, set proper access to the cluster from the CP/master node
    mkdir -p "$HOME"/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config
    # This is in order to be able to create pods in the control-plane node
    kubectl taint nodes --all node-role.kubernetes.io/control-plane-
fi

####################
# CNI installation #
####################

# Install RINA CNI
git clone https://github.com/sergio-gimenez/rina-cni-plugin.git

while true; do
    read -p "Do you wish to install The python version or the bash version [bash/python]? " bp
    case $bp in
    [bash]*)
        rina_cni="rina-cni"
        # Copy the custom configuration file
        sudo cp rina-cni-plugin/demo/my-cni-demo_$node_name.conf /etc/cni/net.d/
        break
        ;;
    [python]*)
        sudo apt install python3-pip -y
        sudo pip install colorlog pyroute2
        rina_cni="rina-cni.py"
        sudo cp rina-cni-plugin/demo/my-cni-demo_$node_name.conf /etc/cni/net.d/
        sudo sed -i 's/rina-cni/rina-cni.py/' /etc/cni/net.d/my-cni-demo_$node_name.conf
        break
        ;;
    *) echo "Please answer 'bash' or 'python'." ;;
    esac
done

# Copy the RINA plugin into CNI plugins directory
sudo cp rina-cni-plugin/$rina_cni /opt/cni/bin

# Set few Iptables rules to enable propper connectivity
sudo rina-cni-plugin/demo/init_$node_name.sh
