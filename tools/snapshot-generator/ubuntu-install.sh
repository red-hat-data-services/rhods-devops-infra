#!/bin/bash
set -e

# Update package list
sudo apt-get update -y

# Install required dependencies
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release software-properties-common

# Add the Kubernetes repository
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.32/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-archive-keyring.gpg
sudo chmod 644 /etc/apt/keyrings/kubernetes-archive-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.32/deb/ /" \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list

# Update package list again after adding the repo
sudo apt-get update -y

# Install required packages
sudo apt-get install -y git passwd findutils python3.12 python3.12-venv kubectl jq skopeo curl

# Install yq
sudo curl -L https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o /usr/bin/yq
sudo chmod +x /usr/bin/yq

# Set up Python virtual environment
python3.12 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
