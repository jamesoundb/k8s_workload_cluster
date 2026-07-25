#!/bin/bash
#
# Validate Worker Cluster Project Configuration
# Checks prerequisites and configuration files before deployment

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

echo -e "${YELLOW}===== Worker Cluster Project Validation =====${NC}"

# Check file structure
echo -e "${YELLOW}Checking project structure...${NC}"

REQUIRED_FILES=(
    "scripts/create_worker_template.sh"
    "scripts/test_worker_template.sh"
    "scripts/cleanup_workers.sh"
    "terraform/main.tf"
    "terraform/variables.tf"
    "terraform/terraform.tfvars"
    "terraform/inventory.tpl"
    "ansible/join-workers.yml"
    "ansible/reset-workers.yml"
    "ansible/roles/common/tasks/main.yml"
    "ansible/roles/containerd/tasks/main.yml"
    "ansible/roles/kubernetes/tasks/main.yml"
    "ansible/roles/worker/tasks/main.yml"
    "ansible/roles/worker/templates/kubelet-config.yaml.j2"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$PROJECT_ROOT/$file" ]; then
        echo -e "  ✅ $file"
    else
        echo -e "  ❌ $file - MISSING"
        VALIDATION_FAILED=true
    fi
done

# Check script permissions
echo -e "${YELLOW}Checking script permissions...${NC}"
SCRIPTS=(
    "scripts/create_worker_template.sh"
    "scripts/test_worker_template.sh"
    "scripts/cleanup_workers.sh"
    "deploy.sh"
)

for script in "${SCRIPTS[@]}"; do
    if [ -x "$PROJECT_ROOT/$script" ]; then
        echo -e "  ✅ $script - executable"
    else
        echo -e "  ❌ $script - not executable"
        VALIDATION_FAILED=true
    fi
done

# Check SSH key
echo -e "${YELLOW}Checking SSH key...${NC}"
if [ -f "$HOME/.ssh/proxmox" ]; then
    echo -e "  ✅ SSH key exists at ~/.ssh/proxmox"
else
    echo -e "  ❌ SSH key missing at ~/.ssh/proxmox"
    VALIDATION_FAILED=true
fi

# Check control plane connectivity
echo -e "${YELLOW}Checking control plane connectivity...${NC}"
if ping -c 1 192.168.1.100 &>/dev/null; then
    echo -e "  ✅ Control plane VIP (192.168.1.100) reachable"
else
    echo -e "  ❌ Control plane VIP (192.168.1.100) not reachable"
    VALIDATION_FAILED=true
fi

# Check Proxmox connectivity
echo -e "${YELLOW}Checking Proxmox connectivity...${NC}"
if ping -c 1 192.168.1.99 &>/dev/null; then
    echo -e "  ✅ Proxmox host (192.168.1.99) reachable"
else
    echo -e "  ❌ Proxmox host (192.168.1.99) not reachable"
    VALIDATION_FAILED=true
fi

# Check tools
echo -e "${YELLOW}Checking required tools...${NC}"
TOOLS=("terraform" "ansible-playbook" "ssh" "kubectl")

for tool in "${TOOLS[@]}"; do
    if command -v "$tool" &>/dev/null; then
        echo -e "  ✅ $tool - installed"
    else
        echo -e "  ❌ $tool - not installed"
        VALIDATION_FAILED=true
    fi
done

# Check Terraform configuration
echo -e "${YELLOW}Checking Terraform configuration...${NC}"
cd "$PROJECT_ROOT/terraform"
if terraform validate &>/dev/null; then
    echo -e "  ✅ Terraform configuration valid"
else
    echo -e "  ❌ Terraform configuration invalid"
    VALIDATION_FAILED=true
fi
cd - > /dev/null

# Check Ansible syntax
echo -e "${YELLOW}Checking Ansible syntax...${NC}"
cd "$PROJECT_ROOT/ansible"
if ansible-playbook --syntax-check join-workers.yml &>/dev/null && \
   ansible-playbook --syntax-check reset-workers.yml &>/dev/null; then
    echo -e "  ✅ Ansible playbook syntax valid"
else
    echo -e "  ❌ Ansible playbook syntax invalid"
    VALIDATION_FAILED=true
fi
cd - > /dev/null

# Summary
echo ""
if [ "${VALIDATION_FAILED:-false}" = "true" ]; then
    echo -e "${RED}===== Validation FAILED =====${NC}"
    echo -e "${YELLOW}Please fix the issues above before deploying.${NC}"
    exit 1
else
    echo -e "${GREEN}===== Validation PASSED =====${NC}"
    echo -e "${YELLOW}Project is ready for deployment!${NC}"
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo -e "  1. Create template: ./scripts/create_worker_template.sh"
    echo -e "  2. Deploy cluster: ./deploy.sh"
    echo -e "  3. Or run full deployment: ./deploy.sh"
fi