# Global instructions
- Please refer to me as James, and let me know that you have read your instructions located at .github/copilot_instructions.md
- When using git be sure to adhere to best practices regarding concise commit messages.
- When I use /architect in my prompt, know that I would like to have an architectural
discussion, and no code or changes to files should occur.
- When I use /code in my prompt, know that I would like to write code.
- When I use /change in my prompt, know that I would like to only have the last code 
change to be made, and I need no additional explainations about the change.
- For git commits: Always run git status first, then group related files into logical
commits. Use concise commit messages without prefixes like feat:, fix:, etc. Group
by functionality (e.g. playbook changes, documentation updates, new features).

# Project Specific instructions
This project creates Kubernetes worker node VMs on Proxmox using Terraform and Ansible to join an existing HA control plane cluster.

## Key Components
- **Template Creation**: Ubuntu 24.04 LTS VM template optimized for Kubernetes workers
- **Multi-VM Deployment**: 3x worker nodes (k8s-worker-1, k8s-worker-2, k8s-worker-3)
- **Network Integration**: Static IPs 192.168.1.83-85, joining control plane at 192.168.1.100
- **SSH Authentication**: Using SSH key at ~/.ssh/proxmox

## Architecture Integration
- **Control Plane**: Existing HA cluster (192.168.1.80-82) with VIP 192.168.1.100
- **Worker Nodes**: New cluster (192.168.1.83-85) joining via kubeadm
- **Container Runtime**: containerd (matching control plane)
- **CNI Plugin**: Flannel (extending existing network)

## Script Guidelines
1. **Template Strategy**: 
   - create_worker_template.sh - Creates optimized worker template (ID 9001)
   - test_worker_template.sh - Tests template deployment
   - cleanup_workers.sh - Removes worker VMs and templates

2. **SSH Key Configuration**: 
   - Use ~/.ssh/proxmox key with -o IdentitiesOnly=yes option
   - Consistent with control plane SSH setup

3. **Worker Node Parameters**:
   - VM User: k8s_83, k8s_84, k8s_85
   - VM Password: set via VM_PASSWORD env var (SSH-key based access)
   - Hostnames: k8s-worker-1, k8s-worker-2, k8s-worker-3
   - Template ID: 9001
   - VM IDs: 304-306

## Deployment Philosophy
- **Infrastructure as Code**: All operations via Terraform/Ansible
- **Idempotent Operations**: Safe to run multiple times
- **End-to-End Automation**: No manual interventions
- **Integration with Existing**: Extend control plane, don't rebuild

## Resource Specifications
- **CPU**: 6 cores per worker (18 total, leaves 2 cores overhead)
- **Memory**: 18GB per worker (54GB total, leaves 2GB overhead + 8GB pihole)
- **Storage**: 100GB per worker (container images + data)
- **Network**: Static IP assignment with MAC consistency