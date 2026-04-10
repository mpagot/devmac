variable "libvirt_uri" {
  description = "URI for the libvirt connection"
  type        = string
  default     = ""
}

variable "hostname" {
  description = "Hostname for the VM"
  type        = string
  default     = "opensuse-dev-vm"
}

variable "username" {
  description = "Username to be created in the VM"
  type        = string
  default     = "devenv"
}

variable "ssh_key" {
  description = "SSH key for the user"
  type        = string
  default     = ""
}

variable "ansible_private_key_path" {
  description = "Path to the SSH private key for Ansible to connect to the VM"
  type        = string
  default     = "~/.ssh/id_rsa"
}

variable "private_ssh_keys_to_upload" {
  description = "A list of local paths to private SSH keys to upload to the VM."
  type        = list(string)
  default     = []
}

variable "libvirt_pool" {
  description = "Libvirt storage pool to use"
  type        = string
  default     = "default"
}

variable "os_image_url" {
  description = "URL of the openSUSE Tumbleweed cloud image"
  type        = string
  default     = "http://download.opensuse.org/tumbleweed/appliances/openSUSE-Tumbleweed-Minimal-VM.x86_64-Cloud.qcow2"
}

variable "uefi_loader_path" {
  description = "Path to the UEFI loader binary for the VM"
  type        = string
  default     = "/usr/share/qemu/ovmf-x86_64-code.bin"
}

variable "uefi_nvram_template_path" {
  description = "Path to the UEFI NVRAM template file for the VM"
  type        = string
  default     = "/usr/share/qemu/ovmf-x86_64-vars.bin"
}

variable "disk_size" {
  description = "Disk size for the VM in bytes"
  type        = number
  default     = 21474836480 # 20GB
}

variable "memory" {
  description = "Memory for the VM in MB"
  type        = number
  default     = 4096
}

variable "vcpu" {
  description = "Number of vCPUs for the VM"
  type        = number
  default     = 2
}

variable "network_bridge" {
  description = "Name of the bridge to connect the VM to"
  type        = string
  default     = "br0"
}