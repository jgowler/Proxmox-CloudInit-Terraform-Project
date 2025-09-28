variable "pm_api_url" {
  description = "URL of Proxmox"
  type        = string
}
variable "pm_user" {
  description = "Terraform user acocunt for Proxmox"
  type        = string
}
variable "pm_api_token_id" {
  description = "API Token used by Terraform user"
  type        = string
  sensitive   = true
}
variable "pm_api_token_secret" {
  description = "API Token secret"
  type        = string
  sensitive   = true
}
variable "ssh_pub_key" {
  description = "SSH pub key"
  type        = string
  sensitive   = true
}
variable "ssh_private_key" {
  description = "Private key"
  type        = string
  sensitive   = true
}
variable "master_count" {
  description = "The number of Master nodes to deploy"
  type        = number
  default     = 1
}
variable "worker_count" {
  description = "The number of Worker nodes to deploy"
  type        = number
  default     = 2
}
variable "base_ip" {
  description = "Base IP address to use to deploy VMs"
  type        = string
  default     = "192.168.0.170"
}
variable "gateway_address" {
  description = "Network gateway address"
  type        = string
  default     = "192.168.0.1"
}
variable "ansible_private_key" {
  description = "SSH private key for Ansible to connect to VMs"
  type        = string
  sensitive   = true
}
variable "ansible_public_key" {
  description = "SSH public key for Ansible"
  type        = string
  sensitive   = true
}
