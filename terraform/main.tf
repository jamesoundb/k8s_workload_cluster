terraform {
  required_providers {
    proxmox = {
      source  = "Telmate/proxmox"
      version = "3.0.1-rc1"
    }
  }
}

provider "proxmox" {
  pm_api_url          = var.proxmox_api_url
  pm_api_token_id     = var.proxmox_api_token_id
  pm_api_token_secret = var.proxmox_api_token_secret
  pm_tls_insecure     = var.proxmox_tls_insecure
}

resource "proxmox_vm_qemu" "worker_nodes" {
  count       = var.worker_count
  name        = "k8s-worker-${count.index + 1}"
  target_node = var.proxmox_node
  clone       = var.template_name
  full_clone  = true
  vmid        = 304 + count.index  # VM IDs: 304, 305, 306
  onboot      = true
  
  # Reduce timeouts for faster deployment
  clone_wait = 10
  additional_wait = 10
  
  # Activate QEMU agent for better VM management
  agent = 1
  os_type = "cloud-init"
  
  # Boot configuration optimized for Kubernetes
  bios = "seabios"
  boot = "order=scsi0"
  bootdisk = "scsi0"
  
  # Disable SSH connectivity check during provisioning
  define_connection_info = false
  
  # CPU configuration optimized for worker workloads
  cores = var.worker_cores
  sockets = 1
  cpu = "host"
  memory = var.worker_memory
  scsihw = "virtio-scsi-pci"
  
  # Performance optimizations for Kubernetes
  numa = true
  balloon = 0  # Disable memory ballooning for stable workloads
  
  # Disk configuration for worker nodes
  disks {
    scsi {
      scsi0 {
        disk {
          storage = var.storage_pool
          size = var.worker_disk_size
          format = "raw"
          iothread = true
        }
      }
    }
  }
  
  # Network configuration with static IPs
  network {
    model   = "virtio"
    bridge  = "vmbr0"
    macaddr = var.worker_mac_addresses[count.index]
  }
  
  # Cloud-init configuration for Kubernetes workers
  ipconfig0 = "ip=${var.worker_ips[count.index]}/24,gw=${var.gateway_ip}"
  ciuser = "k8s_${83 + count.index}"  # Creates k8s_83, k8s_84, k8s_85
  sshkeys = var.ssh_public_key
  searchdomain = "homelab.io"
  nameserver = "192.168.1.100"  # Use control plane VIP for DNS
  
  # Display configuration
  vga {
    type = "std"
  }
  
  serial {
    id   = 0
    type = "socket"
  }

  # Generate worker IPs file for Ansible
  provisioner "local-exec" {
    command = "echo '${var.worker_ips[count.index]}' >> ../ansible/worker_ips.txt"
  }

  # Ensure cloud-init configuration is applied
  provisioner "local-exec" {
    command = "sleep 30 && ssh -i ~/.ssh/proxmox -o IdentitiesOnly=yes root@192.168.1.99 'qm set ${self.vmid} --ide2 ${var.storage_pool}:cloudinit && qm reboot ${self.vmid}'"
  }

  # Wait for VM to be ready for Ansible configuration
  provisioner "local-exec" {
    command = "sleep 60"
  }

  tags = "kubernetes,worker,${count.index + 1}"
}

# Generate Ansible inventory file
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.tpl", {
    vms = [
      for i in range(length(var.worker_ips)) : {
        name        = "k8s-worker-${i + 1}"
        ip_address  = var.worker_ips[i]
        ssh_user    = "k8s_${split(".", var.worker_ips[i])[3]}"
      }
    ]
  })
  filename = "../ansible/generated_inventory.yml"
  
  depends_on = [proxmox_vm_qemu.worker_nodes]
}

output "worker_node_ips" {
  value       = var.worker_ips
  description = "IP addresses of the worker nodes"
}

output "worker_node_names" {
  value       = [for i in range(var.worker_count) : "k8s-worker-${i + 1}"]
  description = "Names of the worker nodes"
}

output "worker_ssh_command" {
  value       = [for i, ip in var.worker_ips : "ssh -i ~/.ssh/proxmox -o IdentitiesOnly=yes k8s_${83 + i}@${ip}"]
  description = "SSH commands to connect to worker nodes"
}

output "cluster_join_info" {
  value = {
    control_plane_vip = "192.168.1.100"
    worker_ips        = var.worker_ips
    next_steps        = [
      "cd ../ansible",
      "ansible-playbook -i generated_inventory.yml join-workers.yml"
    ]
  }
  description = "Information for joining workers to the control plane cluster"
}