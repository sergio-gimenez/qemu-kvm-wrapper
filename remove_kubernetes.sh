#!/bin/bash

set -x

# Remove kubernetes
kubeadm reset
sudo apt-get -y purge kubeadm kubectl kubelet kubernetes-cni kube*
sudo apt-get -y autoremove
sudo rm -rf ~/.kube
