#!/bin/bash
# Script to ping all hosts in inventory
set -e

# Load environment variables
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

INVENTORY_PATH=${INVENTORY_PATH:-inventory/cluster}
SSH_KEY_PATH=${SSH_KEY_PATH:-~/.ssh/id_ed25519}
DOCKER_IMAGE=${DOCKER_IMAGE:-quay.io/kubespray/kubespray:v2.29.1}

# Expand tilde in paths
SSH_KEY_PATH=$(eval echo "$SSH_KEY_PATH")
INVENTORY_PATH=$(eval echo "$INVENTORY_PATH")

if [ ! -d "$INVENTORY_PATH" ]; then
    echo "Error: Inventory directory not found: $INVENTORY_PATH"
    exit 1
fi

if [ ! -f "$SSH_KEY_PATH" ]; then
    echo "Error: SSH key not found: $SSH_KEY_PATH"
    exit 1
fi

echo "Pinging all hosts in inventory..."

docker run --rm -it \
    --network host \
    -v $(pwd)/$INVENTORY_PATH:/inventory:ro \
    -v $SSH_KEY_PATH:/root/.ssh/id_rsa:ro \
    -e ANSIBLE_HOST_KEY_CHECKING=False \
    -w /kubespray \
    "$DOCKER_IMAGE" \
    ansible all \
        -i /inventory/hosts.yaml \
        -e ansible_user=${SSH_USER:-root} \
        -e ansible_ssh_private_key_file=/root/.ssh/id_rsa \
        -m ping
