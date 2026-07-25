#!/bin/bash
#
# Create Kubernetes Worker Template with SSH Authentication
# Creates Ubuntu 24.04 LTS VM template optimized for Kubernetes workers
# Parameters:
# - VM User: pi
# - VM Password: set via VM_PASSWORD env var (SSH-key based access)
# - Hostname: k8s-worker-template
# - Template ID: 9001
# - SSH Key: ~/.ssh/proxmox

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration
TEMPLATE_ID=9001
TEMPLATE_NAME="k8s-worker-template-ubuntu-2404"
PROXMOX_HOST="pve"
STORAGE_POOL="local-lvm"
ISO_STORAGE="local"
VM_USER="ubuntu"  # Template will use ubuntu, then cloud-init creates k8s_XX users
VM_PASSWORD="${VM_PASSWORD:-changeme}"  # Override via env var; template is SSH-key based
VM_HOSTNAME="k8s-worker-template"
SSH_KEY_PATH="$HOME/.ssh/proxmox"

echo -e "${YELLOW}===== Creating Kubernetes Worker Template VM (ID: ${TEMPLATE_ID}) =====${NC}"

# Check SSH key exists
if [ ! -f "$SSH_KEY_PATH" ]; then
    echo -e "${RED}SSH key not found at $SSH_KEY_PATH${NC}"
    echo -e "${YELLOW}Generating new SSH key...${NC}"
    ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_PATH" -N "" -C "Proxmox Worker VM Access"
fi

# Extract public key for cloud-init (pihole approach)
SSH_PUB_KEY=$(cat "${SSH_KEY_PATH}.pub")
# SSH public key (embedded content from terraform.tfvars)
SSH_PUB_KEY="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDL1pv8IHBg3H0Bun4PDfgmSl4jtcVSMttH4zXPlRSY909AdWnx99CvqO+9+ddF2zEvxe1ce0kfWv/Pra0538Jp6ZnfSmKxC4ZP7RoaIheZWUWOsBJuWkLEsqoG6lXgYb1uDA1nuYTLWAhavku4pZu3i6cjwL351B5oKC7+xCcdJSocXp0ofib5tht5BkRwi85yiZxY6XWZss7q01RVKIceRkdyFyUygV+lwKPJAbLdzUwTwp6Al34NMTuxbB8otRjLnughj8oZyySpJgEIM6g/UkIkEieChzn6JIkgLNmiE4l5Q/5v/0HVqTf264EjMd1iV07Mr2RJuE37t1+U8ieXJ0GElnycl54XSG7bxnMHKpGFOvTPKUMcq0hDI1nlVMRlIiMQI1pA6okGFTuQFmcLWC0L0xOzUN+TVxBFP4PKmhhYpvisnJJYPKOW+7UI9STvsBvnjcJf2+HZGj80lofKDbj7t8ug2yJfO4G11b2SVJigNsMnPLuMHRppUAKBdiQrvlVg7VXMPrYPhstx6hrxg1kvM0NLCM1PsMzUNZ79m+Zy8prRhdVICqcKeGFHptx1ibzLpTjYjEXLiSZ67V6SGJZNB2Qh4QzIDNXCLjo7ngn55ZryLMuKcftGVYNrusKfNiLV2V5MoOJNU3nmrHOmprSEgcu+0YnGxv7/ImV15w== james@james-ThinkPad-X1-Carbon-Gen-9"

# Check if template already exists
if ssh -i "$SSH_KEY_PATH" -o IdentitiesOnly=yes root@$PROXMOX_HOST "qm status $TEMPLATE_ID" &>/dev/null; then
    echo -e "${RED}VM with ID $TEMPLATE_ID already exists${NC}"
    read -p "Do you want to remove it and create a new one? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Removing existing VM..."
        ssh -i "$SSH_KEY_PATH" -o IdentitiesOnly=yes root@$PROXMOX_HOST "qm destroy $TEMPLATE_ID --purge" || true
    else
        echo "Aborting template creation."
        exit 1
    fi
fi

# Download Ubuntu 24.04 cloud image if needed
echo -e "${YELLOW}Checking for Ubuntu 24.04 LTS cloud image...${NC}"
CLOUD_IMG_EXISTS=$(ssh -i "$SSH_KEY_PATH" -o IdentitiesOnly=yes root@$PROXMOX_HOST "ls /var/lib/vz/template/iso/ubuntu-24.04-server-cloudimg-amd64.img 2>/dev/null || echo 'not_found'")

if [ "$CLOUD_IMG_EXISTS" == "not_found" ]; then
    echo -e "${YELLOW}Downloading Ubuntu 24.04 LTS cloud image...${NC}"
    ssh -i "$SSH_KEY_PATH" -o IdentitiesOnly=yes root@$PROXMOX_HOST "cd /var/lib/vz/template/iso && wget -q --show-progress https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img -O ubuntu-24.04-server-cloudimg-amd64.img"
else
    echo -e "${GREEN}Ubuntu 24.04 cloud image already exists${NC}"
fi

# Create VM
echo -e "${YELLOW}Creating Worker VM template with ID $TEMPLATE_ID...${NC}"
ssh -i "$SSH_KEY_PATH" -o IdentitiesOnly=yes root@$PROXMOX_HOST "qm create $TEMPLATE_ID \
  --name $TEMPLATE_NAME \
  --memory 32768 \
  --cores 8 \
  --net0 virtio,bridge=vmbr0 \
  --ostype l26 \
  --cpu host \
  --scsihw virtio-scsi-pci \
  --agent 1 \
  --boot c \
  --bootdisk scsi0 \
  --serial0 socket"

# Import and attach the Ubuntu cloud image
echo -e "${YELLOW}Importing Ubuntu cloud image to VM...${NC}"
ssh -i "$SSH_KEY_PATH" -o IdentitiesOnly=yes root@$PROXMOX_HOST "qm importdisk $TEMPLATE_ID /var/lib/vz/template/iso/ubuntu-24.04-server-cloudimg-amd64.img ${STORAGE_POOL}"

# Configure the imported disk
echo -e "${YELLOW}Configuring imported disk...${NC}"
ssh -i "$SSH_KEY_PATH" -o IdentitiesOnly=yes root@$PROXMOX_HOST "qm set $TEMPLATE_ID --scsi0 ${STORAGE_POOL}:vm-${TEMPLATE_ID}-disk-0"

# Resize disk to 100GB for worker workloads
echo -e "${YELLOW}Resizing disk to 100GB for worker workloads...${NC}"
ssh -i "$SSH_KEY_PATH" -o IdentitiesOnly=yes root@$PROXMOX_HOST "qm resize $TEMPLATE_ID scsi0 100G"

# Add cloud-init drive
echo -e "${YELLOW}Adding cloud-init configuration...${NC}"
ssh -i "$SSH_KEY_PATH" -o IdentitiesOnly=yes root@$PROXMOX_HOST "qm set $TEMPLATE_ID --ide2 ${STORAGE_POOL}:cloudinit"

# Copy SSH key to Proxmox host temporarily
echo -e "${YELLOW}Copying SSH key to Proxmox host...${NC}"
scp -i "$SSH_KEY_PATH" -o IdentitiesOnly=yes "${SSH_KEY_PATH}.pub" root@$PROXMOX_HOST:/tmp/worker_ssh_key.pub

# Configure cloud-init for Kubernetes workers
echo -e "${YELLOW}Configuring cloud-init for Kubernetes worker: user=$VM_USER, hostname=$VM_HOSTNAME${NC}"
ssh -i "$SSH_KEY_PATH" -o IdentitiesOnly=yes root@$PROXMOX_HOST "qm set $TEMPLATE_ID \
  --ciuser $VM_USER \
  --cipassword $(openssl passwd -6 $VM_PASSWORD) \
  --searchdomain homelab.io \
  --nameserver 192.168.1.100 \
  --ipconfig0 ip=dhcp \
  --sshkeys /tmp/worker_ssh_key.pub"

# Clean up temporary SSH key file
ssh -i "$SSH_KEY_PATH" -o IdentitiesOnly=yes root@$PROXMOX_HOST "rm -f /tmp/worker_ssh_key.pub"

# Configure VM for Kubernetes workload optimization
echo -e "${YELLOW}Optimizing VM for Kubernetes workloads...${NC}"
ssh -i "$SSH_KEY_PATH" -o IdentitiesOnly=yes root@$PROXMOX_HOST "qm set $TEMPLATE_ID \
  --numa 1 \
  --balloon 0"

# Convert to template
echo -e "${YELLOW}Converting VM to template...${NC}"
ssh -i "$SSH_KEY_PATH" -o IdentitiesOnly=yes root@$PROXMOX_HOST "qm template $TEMPLATE_ID"

echo -e "${GREEN}===== Kubernetes Worker Template Creation Complete =====${NC}"
echo -e "${YELLOW}Template Details:${NC}"
echo -e "  Template ID: $TEMPLATE_ID"
echo -e "  Template Name: $TEMPLATE_NAME"
echo -e "  User: $VM_USER"
echo -e "  Password: $VM_PASSWORD"
echo -e "  SSH Key: $SSH_KEY_PATH"
echo -e "  Memory: 32GB (optimized for worker workloads)"
echo -e "  CPU: 8 cores"
echo -e "  Disk: 100GB (container image storage)"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo -e "1. Test the template: ./test_worker_template.sh"
echo -e "2. Deploy workers: cd ../terraform && terraform apply"
echo -e "3. Join cluster: cd ../ansible && ansible-playbook join-workers.yml"