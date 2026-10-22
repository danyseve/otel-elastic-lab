variable "proxmox_endpoint" {
  description = "Proxmox API URL, e.g. https://pve.example.internal:8006/"
  type        = string
}

variable "proxmox_api_token" {
  description = "API token in the form user@realm!tokenid=secret"
  type        = string
  sensitive   = true
}

variable "proxmox_insecure" {
  description = "Skip TLS verification of the Proxmox API (self-signed certs)"
  type        = bool
  default     = false
}

variable "debian_image_url" {
  description = "Debian 13 generic cloud image"
  type        = string
  default     = "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2"
}

variable "image_datastore" {
  description = "Datastore that holds the imported cloud image (must be readable from every hypervisor that hosts a VM)"
  type        = string
  default     = "local"
}

variable "image_node" {
  description = "Hypervisor that imports the cloud image. Empty = the node of the first VM in alphabetical order."
  type        = string
  default     = ""
}

variable "vm_datastore" {
  description = "Datastore for VM disks and cloud-init drives"
  type        = string
  default     = "local-lvm"
}

variable "pool_id" {
  description = "Resource pool the VMs are created in (keeps the API token scoped)"
  type        = string
  default     = "otel-lab"
}

variable "network_bridge" {
  type    = string
  default = "vmbr0"
}

variable "network_vlan" {
  description = "VLAN tag for the lab network. Null = untagged (the bridge must be VLAN-aware for a tag)"
  type        = number
  default     = null
}

variable "network_prefix" {
  description = "CIDR prefix length of the lab network"
  type        = number
  default     = 24
}

variable "network_gateway" {
  type = string
}

variable "dns_servers" {
  type = list(string)
}

variable "domain" {
  description = "DNS domain of the lab"
  type        = string
  default     = "lab.example"
}

variable "ssh_user" {
  description = "Admin user created by cloud-init (and used by Ansible)"
  type        = string
  default     = "debian"
}

variable "ssh_public_keys" {
  description = "SSH public keys installed for the admin user (one entry per key)"
  type        = list(string)

  validation {
    condition     = length(var.ssh_public_keys) > 0
    error_message = "ssh_public_keys must contain at least one public key."
  }
}

variable "vms" {
  description = "Kubernetes (k3s) nodes. Put each one on a different hypervisor host."
  type = map(object({
    node      = string
    vm_id     = number
    ip        = string
    cores     = number
    memory_mb = number
    disk_gb   = number
  }))

  validation {
    condition     = length(var.vms) == 3
    error_message = "This lab expects exactly 3 nodes (etcd and Elasticsearch quorum)."
  }

  validation {
    condition     = length(distinct([for vm in values(var.vms) : vm.node])) == 3
    error_message = "Each node must run on a different hypervisor host."
  }
}
