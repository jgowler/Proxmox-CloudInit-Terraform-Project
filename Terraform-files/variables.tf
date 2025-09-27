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
