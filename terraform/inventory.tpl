---
all:
  children:
    k8s_nodes:
      children:
        workers:
          hosts:
%{ for index, vm in vms ~}
            ${vm.name}:
              ansible_host: ${vm.ip_address}
              ansible_user: ${vm.ssh_user}
              ansible_ssh_private_key_file: /home/james/.ssh/proxmox
              ansible_ssh_common_args: '-o IdentitiesOnly=yes'
              worker_index: ${index + 1}
%{ endfor ~}
  vars:
    # Control plane connection details
    control_plane_vip: "192.168.1.100"
    control_plane_port: "6443"
    control_plane_delegate_host: "192.168.1.80"
    control_plane_remote_user: "k8s"
    control_plane_ssh_key: "/home/james/.ssh/k8s_pi"
    
    # Container runtime configuration  
    container_runtime: "containerd"
    
    # CNI configuration (extending existing Flannel network)
    cni_plugin: "flannel"
    pod_network_cidr: "10.244.0.0/16"
    
    # Worker node labels and taints
    worker_labels:
      - "node-role.kubernetes.io/worker="
      - "cluster.local/workload-node=true"
    
    # Resource quotas for worker nodes
    worker_max_pods: 250
    
    # Kubelet configuration
    kubelet_extra_args:
      - "--max-pods=250"
      - "--cluster-dns=10.245.0.10"
      - "--cluster-domain=cluster.local"