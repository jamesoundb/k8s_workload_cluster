variable "proxmox_api_url" {
  description = "Proxmox API URL"
  type        = string
}

variable "proxmox_api_token_id" {
  description = "Proxmox API token ID"
  type        = string
}

variable "proxmox_api_token_secret" {
  description = "Proxmox API token secret"
  type        = string
  sensitive   = true
}

variable "proxmox_tls_insecure" {
  description = "Allow insecure TLS connections to Proxmox API"
  type        = bool
  default     = false
}

variable "proxmox_node" {
  description = "Proxmox node to create the VMs on"
  type        = string
}

variable "proxmox_host" {
  description = "Proxmox host IP address for SSH commands"
  type        = string
}

variable "template_name" {
  description = "Name of the worker template to clone"
  type        = string
}

variable "worker_count" {
  description = "Number of worker nodes to create"
  type        = number
  default     = 3
}

variable "worker_cores" {
  description = "Number of CPU cores per worker node"
  type        = number
  default     = 8
}

variable "worker_memory" {
  description = "Memory per worker node in MB"
  type        = number
  default     = 32768
}

variable "storage_pool" {
  description = "Storage pool for worker VM disks"
  type        = string
}

variable "worker_disk_size" {
  description = "Disk size per worker node (in GB)"
  type        = string
  default     = "100"
}

variable "worker_ips" {
  description = "Static IP addresses for worker nodes"
  type        = list(string)
  default     = ["192.168.1.83", "192.168.1.84", "192.168.1.85"]
}

variable "worker_mac_addresses" {
  description = "Static MAC addresses for worker nodes"
  type        = list(string)
  default     = [
    "52:54:00:83:00:01",  # k8s-worker-1
    "52:54:00:84:00:02",  # k8s-worker-2
    "52:54:00:85:00:03"   # k8s-worker-3
  ]
}

variable "gateway_ip" {
  description = "Gateway IP address for worker nodes"
  type        = string
  default     = "192.168.1.1"
}

variable "ssh_user" {
  description = "SSH user for worker node provisioning"
  type        = string
  default     = "k8s_user"  # Will be set per-VM in cloud-init
}

variable "ssh_public_key" {
  description = "SSH public key for worker node access"
  type        = string
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key file"
  type        = string
  default     = "~/.ssh/proxmox"
}