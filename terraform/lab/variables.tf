variable "zone" {
  description = "Scaleway zone. STARDUST1-S is available in nl-ams-1 and pl-waw-2."
  default     = "nl-ams-1"
}

variable "name" {
  description = "Instance + security-group name and tailnet hostname."
  default     = "scw-vm-lab"
}

variable "instance_type" {
  description = "Cheapest is STARDUST1-S (~EUR 0.44/mo); DEV1-S if Stardust is out of stock."
  default     = "STARDUST1-S"
}

variable "image" {
  description = "Marketplace image label."
  default     = "ubuntu_jammy"
}

variable "ssh_allowed_cidr" {
  description = "CIDR allowed to SSH on the public IP (fallback; normal path is the tailnet)."
  default     = "0.0.0.0/0"
}

variable "tags" {
  description = "Scaleway resource tags."
  default     = ["scw-vm", "fleet-lab", "disposable"]
}

# Passed at apply time, never committed:
variable "ssh_pubkey" {
  description = "Public key authorized for the fhestvang user (TF_VAR_ssh_pubkey)."
  type        = string
}

variable "tailscale_authkey" {
  description = "Ephemeral, pre-authorized, tag:scw-vm auth key (TF_VAR_tailscale_authkey)."
  type        = string
  sensitive   = true
}

variable "dotfiles_repo" {
  description = "Dotfiles repo cloned + installed by cloud-init (current fleet definition)."
  default     = "https://github.com/fhestvang/dotfiles.git"
}
