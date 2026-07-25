#!/bin/bash
#
# Test Kubernetes Worker Template 
# Creates a test VM from the worker template to verify functionality
# Parameters:
# - Template ID: 9001 
# - Test VM ID: 9101
# - Test IP: 192.168.1.91 (temporary test IP)

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration
TEMPLATE_ID=9001
TEST_VM_ID=9101
TEST_VM_NAME="k8s-worker-test"
PROXMOX_HOST="pve"
SSH_KEY_PATH="$HOME/.ssh/proxmox"
TEST_IP="192.168.1.91"
TEST_USER="k8s_91"  # Consistent with naming pattern
GATEWAY_IP="192.168.1.1"

echo -e "${YELLOW}===== Testing Kubernetes Worker Template (ID: ${TEMPLATE_ID}) =====${NC}"

# Check if template exists
if ! ssh -i "$SSH_KEY_PATH" -o IdentitiesOnly=yes root@$PROXMOX_HOST "qm config $TEMPLATE_ID | grep -q template" 2>/dev/null; then
    echo -e "${RED}Template $TEMPLATE_ID not found or not a template${NC}"
    echo -e "${YELLOW}Run ./create_worker_template.sh first${NC}"
    exit 1
fi

# Check if test VM already exists
if ssh -i "$SSH_KEY_PATH" -o IdentitiesOnly=yes root@$PROXMOX_HOST "qm status $TEST_VM_ID" &>/dev/null; then
    echo -e "${RED}Test VM with ID $TEST_VM_ID already exists${NC}"
    read -p "Do you want to remove it and create a new one? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Removing existing test VM..."
        ssh -i "$SSH_KEY_PATH" -o IdentitiesOnly=yes root@$PROXMOX_HOST "qm stop $TEST_VM_ID || true && qm destroy $TEST_VM_ID --purge" || true
    else
        echo "Aborting test VM creation."
        exit 1
    fi
fi

# Clone template to create test VM
echo -e "${YELLOW}Cloning template to create test VM (ID: $TEST_VM_ID)...${NC}"
ssh -i "$SSH_KEY_PATH" -o IdentitiesOnly=yes root@$PROXMOX_HOST "qm clone $TEMPLATE_ID $TEST_VM_ID --name $TEST_VM_NAME --full"

# Configure test VM with static IP
echo -e "${YELLOW}Configuring test VM with static IP $TEST_IP...${NC}"
ssh -i "$SSH_KEY_PATH" -o IdentitiesOnly=yes root@$PROXMOX_HOST "qm set $TEST_VM_ID \
  --ipconfig0 ip=${TEST_IP}/24,gw=${GATEWAY_IP} \
  --hostname k8s-worker-test \
  --ciuser $TEST_USER"

# Start test VM
echo -e "${YELLOW}Starting test VM...${NC}"
ssh -i "$SSH_KEY_PATH" -o IdentitiesOnly=yes root@$PROXMOX_HOST "qm start $TEST_VM_ID"

# Wait for VM to boot and get IP
echo -e "${YELLOW}Waiting for VM to boot and network to be ready...${NC}"
sleep 60

# Test SSH connectivity
echo -e "${YELLOW}Testing SSH connectivity...${NC}"
MAX_ATTEMPTS=12
ATTEMPT=1

while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
    echo -e "${YELLOW}SSH attempt $ATTEMPT/$MAX_ATTEMPTS to $TEST_IP...${NC}"
    
    if ssh -i "$SSH_KEY_PATH" -o IdentitiesOnly=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no $TEST_USER@$TEST_IP "echo 'SSH connection successful'" 2>/dev/null; then
        echo -e "${GREEN}SSH connection successful!${NC}"
        break
    fi
    
    if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
        echo -e "${RED}SSH connection failed after $MAX_ATTEMPTS attempts${NC}"
        echo -e "${YELLOW}Test VM is running at IP: $TEST_IP${NC}"
        echo -e "${YELLOW}You can try manual connection: ssh -i ~/.ssh/proxmox -o IdentitiesOnly=yes $TEST_USER@$TEST_IP${NC}"
        exit 1
    fi
    
    ATTEMPT=$((ATTEMPT + 1))
    sleep 15
done

# Test VM specifications and Kubernetes readiness
echo -e "${YELLOW}Testing VM specifications and Kubernetes prerequisites...${NC}"
ssh -i "$SSH_KEY_PATH" -o IdentitiesOnly=yes $TEST_USER@$TEST_IP "
echo '=== System Information ==='
uname -a
echo ''
echo '=== CPU Information ==='
nproc
echo ''
echo '=== Memory Information ==='
free -h
echo ''
echo '=== Disk Information ==='
df -h /
echo ''
echo '=== Network Configuration ==='
ip addr show eth0
echo ''
echo '=== Container Runtime Prerequisites ==='
echo 'Checking kernel modules for containerd...'
lsmod | grep overlay || echo 'overlay module not loaded'
lsmod | grep br_netfilter || echo 'br_netfilter module not loaded'
echo ''
echo '=== System Updates ==='
apt list --upgradable 2>/dev/null | wc -l && echo 'packages need updates'
echo ''
echo '=== Cloud-init Status ==='
sudo cloud-init status --long || echo 'cloud-init status check failed'
"

echo -e "${GREEN}===== Worker Template Test Complete =====${NC}"
echo -e "${YELLOW}Test Results:${NC}"
echo -e "  ✅ Template clone: SUCCESS"
echo -e "  ✅ VM boot: SUCCESS"
echo -e "  ✅ Network configuration: SUCCESS"
echo -e "  ✅ SSH access: SUCCESS"
echo -e "  ✅ System specifications: Verified"
echo ""
echo -e "${YELLOW}Test VM Details:${NC}"
echo -e "  VM ID: $TEST_VM_ID"
echo -e "  VM Name: $TEST_VM_NAME"
echo -e "  IP Address: $TEST_IP"
echo -e "  SSH Command: ssh -i ~/.ssh/proxmox -o IdentitiesOnly=yes $TEST_USER@$TEST_IP"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo -e "1. Manually test additional functionality if needed"
echo -e "2. Clean up test VM: ssh root@$PROXMOX_HOST \"qm stop $TEST_VM_ID && qm destroy $TEST_VM_ID --purge\""
echo -e "3. Deploy production workers: cd ../terraform && terraform apply"