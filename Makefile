.PHONY: help bootstrap install scale reset kubeconfig ping shell clean

# Load environment variables
ifneq (,$(wildcard .env))
    include .env
    export
endif

# Default values
KUBESPRAY_VERSION ?= v2.29.1
KUBESPRAY_TAG ?= release-2.29
INVENTORY_PATH ?= inventory/cluster
SSH_KEY_PATH ?= ~/.ssh/id_ed25519
SSH_USER ?= root
DOCKER_IMAGE ?= quay.io/kubespray/kubespray:v2.29.1
ARTIFACTS_DIR ?= artifacts

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-15s %s\n", $$1, $$2}'

bootstrap: ## Prepare Kubespray Docker image (no local git repo)
	@echo "Bootstrapping kubespray (docker image only)..."
	@echo "Pulling image: $(DOCKER_IMAGE)"
	@docker pull $(DOCKER_IMAGE)
	@echo "Kubespray Docker image is ready."

ping: ## Ping all hosts in inventory to verify connectivity
	@./scripts/ping-hosts.sh

install: ## Install Kubernetes cluster (run cluster.yml)
	@echo "Installing Kubernetes cluster..."
	@./scripts/run-playbook.sh cluster.yml

scale: ## Add worker node (run scale.yml)
	@echo "Scaling cluster (adding worker node)..."
	@./scripts/run-playbook.sh scale.yml

reset: ## Reset/destroy cluster (run reset.yml)
	@echo "Resetting cluster..."
	@read -p "Are you sure you want to reset the cluster? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		./scripts/run-playbook.sh reset.yml; \
	else \
		echo "Reset cancelled."; \
	fi

kubeconfig: ## Copy kubeconfig from master node to artifacts
	@echo "Fetching kubeconfig..."
	@mkdir -p $(ARTIFACTS_DIR)
	@if [ -d "$(INVENTORY_PATH)" ]; then \
		MASTER=$$(grep -A 1 "kube_control_plane:" $(INVENTORY_PATH)/hosts.yaml | grep -E "^\s+\w+:" | head -1 | sed 's/://g' | xargs); \
		if [ -n "$$MASTER" ]; then \
			echo "Copying kubeconfig from $$MASTER..."; \
			docker run --rm \
				--network host \
				-v $(PWD)/$(INVENTORY_PATH):/inventory:ro \
				-v $(SSH_KEY_PATH):/root/.ssh/id_rsa:ro \
				-v $(PWD)/$(ARTIFACTS_DIR):/artifacts \
				-e ANSIBLE_HOST_KEY_CHECKING=False \
				-w /kubespray \
				$(DOCKER_IMAGE) \
				ansible $$MASTER \
					-i /inventory/hosts.yaml \
					-e ansible_user=$(SSH_USER) \
					-e ansible_ssh_private_key_file=/root/.ssh/id_rsa \
					-m fetch \
					-a "src=/etc/kubernetes/admin.conf dest=/artifacts/kubeconfig flat=yes" || \
			echo "Warning: Could not copy kubeconfig. It may be generated during installation."; \
		else \
			echo "Error: Could not determine master node from inventory."; \
		fi; \
	else \
		echo "Error: Inventory directory not found: $(INVENTORY_PATH)"; \
	fi

shell: ## Open shell in kubespray container
	@docker run --rm -it \
		--network host \
		-v $(PWD)/$(INVENTORY_PATH):/inventory:ro \
		-v $(SSH_KEY_PATH):/root/.ssh/id_rsa:ro \
		-e ANSIBLE_HOST_KEY_CHECKING=False \
		-w /kubespray \
		$(DOCKER_IMAGE) \
		/bin/bash

clean: ## Clean artifacts and temporary files
	@echo "Cleaning artifacts..."
	@rm -rf $(ARTIFACTS_DIR)/*.retry
	@rm -rf $(ARTIFACTS_DIR)/.ansible
	@find . -name "*.retry" -delete
	@find . -name ".ansible" -type d -exec rm -rf {} + 2>/dev/null || true
