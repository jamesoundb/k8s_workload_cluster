#!/bin/bash
#
# Cleanup Worker Cluster Resources
# Removes worker VMs, templates, and Terraform state
# Use with caution - this will destroy all worker resources

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration
TEMPLATE_ID=9001
TEST_VM_ID=9101
WORKER_VM_IDS=(304 305 306)
PROXMOX_HOST="pve"
SSH_KEY_PATH="$HOME/.ssh/proxmox"

echo -e "${RED}===== WARNING: Worker Cluster Cleanup =====${NC}"
echo -e "${YELLOW}This will remove:${NC}"
echo -e "  - Worker template (ID: $TEMPLATE_ID)"
echo -e "  - Test VM (ID: $TEST_VM_ID)"
echo -e "  - Production worker VMs (IDs: ${WORKER_VM_IDS[*]})"
echo -e "  - Terraform state files"
echo ""

if [ "$1" != "--force" ]; then
    read -p "Are you sure you want to continue? This cannot be undone! (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cleanup cancelled."
        exit 0
    fi
fi

# Function to safely remove VM
remove_vm() {
    local vm_id=$1
    local vm_name=$2
    
    if ssh -i "$SSH_KEY_PATH" -o IdentitiesOnly=yes root@$PROXMOX_HOST "qm status $vm_id" &>/dev/null; then
        echo -e "${YELLOW}Removing $vm_name (ID: $vm_id)...${NC}"
        ssh -i "$SSH_KEY_PATH" -o IdentitiesOnly=yes root@$PROXMOX_HOST "qm stop $vm_id || true"
        sleep 5
        ssh -i "$SSH_KEY_PATH" -o IdentitiesOnly=yes root@$PROXMOX_HOST "qm destroy $vm_id --purge" || true
        echo -e "${GREEN}✅ $vm_name removed${NC}"
    else
        echo -e "${YELLOW}$vm_name (ID: $vm_id) not found, skipping${NC}"
    fi
}

# Remove production worker VMs
echo -e "${YELLOW}Cleaning up production worker VMs...${NC}"
for i in "${!WORKER_VM_IDS[@]}"; do
    worker_id=${WORKER_VM_IDS[$i]}
    worker_name="k8s-worker-$((i + 1))"
    remove_vm $worker_id $worker_name
done

# Remove test VM
echo -e "${YELLOW}Cleaning up test VM...${NC}"
remove_vm $TEST_VM_ID "k8s-worker-test"

# Remove template
echo -e "${YELLOW}Cleaning up worker template...${NC}"
remove_vm $TEMPLATE_ID "k8s-worker-template"

# Clean up Terraform state
echo -e "${YELLOW}Cleaning up Terraform state...${NC}"
if [ -d "../terraform" ]; then
    cd ../terraform
    if [ -f "terraform.tfstate" ]; then
        echo -e "${YELLOW}Removing Terraform state files...${NC}"
        rm -f terraform.tfstate terraform.tfstate.backup
        echo -e "${GREEN}✅ Terraform state files removed${NC}"
    fi
    
    if [ -d ".terraform" ]; then
        echo -e "${YELLOW}Removing Terraform cache...${NC}"
        rm -rf .terraform .terraform.lock.hcl
        echo -e "${GREEN}✅ Terraform cache removed${NC}"
    fi
    cd - > /dev/null
fi

# Clean up Ansible generated files
echo -e "${YELLOW}Cleaning up Ansible generated files...${NC}"
if [ -d "../ansible" ]; then
    cd ../ansible
    if [ -f "worker_ips.txt" ]; then
        rm -f worker_ips.txt
        echo -e "${GREEN}✅ Ansible worker IPs file removed${NC}"
    fi
    cd - > /dev/null
fi

echo -e "${GREEN}===== Worker Cluster Cleanup Complete =====${NC}"
echo -e "${YELLOW}Summary:${NC}"
echo -e "  ✅ All worker VMs removed"
echo -e "  ✅ Worker template removed"
echo -e "  ✅ Test VM removed"
echo -e "  ✅ Terraform state cleaned"
echo -e "  ✅ Ansible files cleaned"
echo ""
echo -e "${YELLOW}To rebuild the worker cluster:${NC}"
echo -e "1. Create template: ./create_worker_template.sh"
echo -e "2. Deploy workers: cd ../terraform && terraform apply"
echo -e "3. Join cluster: cd ../ansible && ansible-playbook join-workers.yml"