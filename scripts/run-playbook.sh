#!/bin/bash
# Script to run ansible-playbook inside kubespray container
# Usage: ./scripts/run-playbook.sh <playbook> [extra-args]

set -e

# Load environment variables
if [ -f .env ]; then
    # shellcheck disable=SC2046,SC1091
    set -a
    . .env
    set +a
fi

PLAYBOOK=${1:-cluster.yml}
EXTRA_ARGS=${@:2}

# Default values
INVENTORY_PATH=${INVENTORY_PATH:-inventory/cluster}
SSH_KEY_PATH=${SSH_KEY_PATH:-~/.ssh/id_ed25519}
DOCKER_IMAGE=${DOCKER_IMAGE:-quay.io/kubespray/kubespray:v2.29.1}
ARTIFACTS_DIR=${ARTIFACTS_DIR:-artifacts}

# Expand tilde in paths
SSH_KEY_PATH=$(eval echo "$SSH_KEY_PATH")
INVENTORY_PATH=$(eval echo "$INVENTORY_PATH")

# Check if inventory exists
if [ ! -d "$INVENTORY_PATH" ]; then
    echo "Error: Inventory directory not found: $INVENTORY_PATH"
    echo "Please copy inventory.example to $INVENTORY_PATH and configure it."
    exit 1
fi

# Check if SSH key exists
if [ ! -f "$SSH_KEY_PATH" ]; then
    echo "Error: SSH key not found: $SSH_KEY_PATH"
    exit 1
fi

# Create artifacts directory
mkdir -p "$ARTIFACTS_DIR"

# Prepare volume mounts (no local kubespray repo, use one inside the image)
VOLUME_ARGS="-v $(pwd)/$INVENTORY_PATH:/inventory:ro"
VOLUME_ARGS="$VOLUME_ARGS -v $SSH_KEY_PATH:/root/.ssh/id_rsa:ro"
VOLUME_ARGS="$VOLUME_ARGS -v $(pwd)/$ARTIFACTS_DIR:/artifacts"

# Add known_hosts if provided
if [ -n "$SSH_KNOWN_HOSTS_PATH" ] && [ -f "$SSH_KNOWN_HOSTS_PATH" ]; then
    SSH_KNOWN_HOSTS_PATH=$(eval echo "$SSH_KNOWN_HOSTS_PATH")
    VOLUME_ARGS="$VOLUME_ARGS -v $SSH_KNOWN_HOSTS_PATH:/root/.ssh/known_hosts:ro"
fi

# Run playbook
echo "Running playbook: $PLAYBOOK"
echo "Inventory: $INVENTORY_PATH"
echo "SSH Key: $SSH_KEY_PATH"

docker run --rm -it \
    --network host \
    $VOLUME_ARGS \
    -e ANSIBLE_HOST_KEY_CHECKING=False \
    -e USER_ID=$(id -u) \
    -e GROUP_ID=$(id -g) \
    -w /kubespray \
    "$DOCKER_IMAGE" \
    ansible-playbook \
        -i /inventory/hosts.yaml \
        --become \
        --become-user=root \
        -e ansible_user=${SSH_USER:-root} \
        -e ansible_ssh_private_key_file=/root/.ssh/id_rsa \
        $EXTRA_ARGS \
        "$PLAYBOOK"

# Copy kubeconfig if it exists in artifacts
if [ -f "$ARTIFACTS_DIR/admin.conf" ]; then
    cp "$ARTIFACTS_DIR/admin.conf" "$ARTIFACTS_DIR/kubeconfig"
    echo "Kubeconfig saved to: $ARTIFACTS_DIR/kubeconfig"
fi
