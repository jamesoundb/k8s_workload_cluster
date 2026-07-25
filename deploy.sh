#!/bin/bash
#
# Deploy Kubernetes Worker Node Cluster
# Complete end-to-end deployment from template to cluster joining

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo -e "${BLUE}===== Kubernetes Worker Cluster Deployment =====${NC}"
echo -e "${YELLOW}This will deploy 3 worker nodes to join the existing control plane${NC}"
echo ""

# Function to check prerequisites
check_prerequisites() {
    echo -e "${YELLOW}Checking prerequisites...${NC}"
    
    # Check if SSH key exists
    if [ ! -f "$HOME/.ssh/proxmox" ]; then
        echo -e "${RED}SSH key not found at ~/.ssh/proxmox${NC}"
        echo -e "${YELLOW}Run the create_worker_template.sh script first${NC}"
        exit 1
    fi
    
    # Check if control plane is accessible
    if ! ping -c 1 192.168.1.100 &>/dev/null; then
        echo -e "${RED}Control plane VIP (192.168.1.100) is not accessible${NC}"
        exit 1
    fi
    
    # Check if Terraform is installed
    if ! command -v terraform &>/dev/null; then
        echo -e "${RED}Terraform is not installed${NC}"
        exit 1
    fi
    
    # Check if Ansible is installed
    if ! command -v ansible-playbook &>/dev/null; then
        echo -e "${RED}Ansible is not installed${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Prerequisites check passed${NC}"
}

# Function to create template if needed
create_template() {
    echo -e "${YELLOW}Checking if worker template exists...${NC}"
    
    if ! ssh -i ~/.ssh/proxmox -o IdentitiesOnly=yes root@192.168.1.99 "qm config 9001 | grep -q template" 2>/dev/null; then
        echo -e "${YELLOW}Worker template not found. Creating template...${NC}"
        cd "$SCRIPT_DIR"
        ./create_worker_template.sh
        cd - > /dev/null
    else
        echo -e "${GREEN}✅ Worker template already exists${NC}"
    fi
}

# Function to deploy VMs with Terraform
deploy_vms() {
    echo -e "${YELLOW}Deploying worker VMs with Terraform...${NC}"
    
    cd "$PROJECT_ROOT/terraform"
    
    # Initialize Terraform if needed
    if [ ! -d ".terraform" ]; then
        echo -e "${YELLOW}Initializing Terraform...${NC}"
        terraform init
    fi
    
    # Deploy VMs
    echo -e "${YELLOW}Applying Terraform configuration...${NC}"
    terraform apply -auto-approve
    
    # Wait for VMs to be ready
    echo -e "${YELLOW}Waiting for VMs to be fully ready...${NC}"
    sleep 120
    
    cd - > /dev/null
    echo -e "${GREEN}✅ Worker VMs deployed successfully${NC}"
}

# Function to join workers to cluster
join_workers() {
    echo -e "${YELLOW}Joining worker nodes to control plane cluster...${NC}"
    
    cd "$PROJECT_ROOT/ansible"
    
    # Use generated inventory if it exists, otherwise use manual inventory
    INVENTORY_FILE="generated_inventory.yml"
    if [ ! -f "$INVENTORY_FILE" ]; then
        INVENTORY_FILE="inventory.yml"
    fi
    
    # Run Ansible playbook to join workers
    ansible-playbook -i "$INVENTORY_FILE" join-workers.yml
    
    cd - > /dev/null
    echo -e "${GREEN}✅ Workers joined to cluster successfully${NC}"
}

# Function to verify deployment
verify_deployment() {
    echo -e "${YELLOW}Verifying cluster deployment...${NC}"
    
    echo -e "${YELLOW}Getting cluster node status...${NC}"
    ssh -i ~/.ssh/k8s_pi -o IdentitiesOnly=yes k8s@192.168.1.80 "kubectl get nodes -o wide" || true
    
    echo ""
    echo -e "${YELLOW}Getting cluster pod distribution...${NC}"
    ssh -i ~/.ssh/k8s_pi -o IdentitiesOnly=yes k8s@192.168.1.80 "kubectl get pods -A -o wide | grep -E '(worker|Running)'" || true
    
    echo -e "${GREEN}✅ Deployment verification complete${NC}"
}

# Main deployment flow
main() {
    case "${1:-}" in
        "--template-only")
            check_prerequisites
            create_template
            echo -e "${GREEN}Template creation complete. Run without --template-only to deploy VMs.${NC}"
            ;;
        "--vms-only")
            check_prerequisites
            deploy_vms
            echo -e "${GREEN}VM deployment complete. Run ansible manually to join cluster.${NC}"
            ;;
        "--join-only")
            check_prerequisites
            join_workers
            verify_deployment
            ;;
        "--verify")
            verify_deployment
            ;;
        *)
            # Full end-to-end deployment
            check_prerequisites
            create_template
            deploy_vms
            join_workers
            verify_deployment
            
            echo ""
            echo -e "${GREEN}===== Worker Cluster Deployment Complete =====${NC}"
            echo -e "${YELLOW}Summary:${NC}"
            echo -e "  ✅ Worker template created/verified"
            echo -e "  ✅ 3 worker VMs deployed (IDs: 304-306)"
            echo -e "  ✅ Workers joined control plane cluster"
            echo -e "  ✅ Cluster verification complete"
            echo ""
            echo -e "${YELLOW}Worker Node Access:${NC}"
            echo -e "  k8s-worker-1: ssh -i ~/.ssh/proxmox k8s_83@192.168.1.83"
            echo -e "  k8s-worker-2: ssh -i ~/.ssh/proxmox k8s_84@192.168.1.84"
            echo -e "  k8s-worker-3: ssh -i ~/.ssh/proxmox k8s_85@192.168.1.85"
            echo ""
            echo -e "${YELLOW}Cluster Management:${NC}"
            echo -e "  kubectl get nodes -o wide"
            echo -e "  kubectl get pods -A -o wide"
            ;;
    esac
}

# Run main function with all arguments
main "$@"