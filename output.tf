output "vm_name" {
  description = "Domain name of the VM on the KVM host"
  value       = var.hostname
}

output "ansible_user" {
  description = "Username Ansible uses to connect to the VM"
  value       = var.username
}

output "ansible_private_key_path" {
  description = "Path to the SSH private key for Ansible"
  value       = var.ansible_private_key_path
}

output "private_ssh_keys_to_upload" {
  description = "Local SSH key paths to upload into the VM"
  value       = var.private_ssh_keys_to_upload
}

output "kvm_ssh_host" {
  description = "SSH destination for the KVM host (user@host from libvirt_uri)"
  value       = local.kvm_ssh_host
}
