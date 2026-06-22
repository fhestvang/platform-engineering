variable "hostname" {
  description = "Scaleway instance hostname. Must start with scw- so chezmoi renders role=scw-agent."
  type        = string

  validation {
    condition     = startswith(var.hostname, "scw-")
    error_message = "hostname must start with scw-."
  }
}

variable "project_id" {
  description = "Scaleway project ID. Non-secret."
  type        = string
  default     = "d0be35ee-8579-4bd6-89e3-18d55aa5367a"
}

variable "region" {
  description = "Scaleway region."
  type        = string
  default     = "fr-par"
}

variable "zone" {
  description = "Scaleway zone."
  type        = string
  default     = "fr-par-1"
}

variable "instance_type" {
  description = "Scaleway Instance commercial type."
  type        = string
  default     = "DEV1-S"
}

variable "image" {
  description = "Scaleway image slug."
  type        = string
  default     = "ubuntu_noble"
}

variable "root_volume_size_gb" {
  description = "Root volume size in GB."
  type        = number
  default     = 50
}

variable "operator_user" {
  description = "Normal working user created by cloud-init."
  type        = string
  default     = "fhestvang"
}

variable "operator_ssh_public_key" {
  description = "SSH public key installed for the operator user."
  type        = string
}

variable "tailscale_auth_key" {
  description = "One-use, short-lived Tailscale auth key for tag:scw-agent."
  type        = string
  sensitive   = true
}

variable "bao_approle_content" {
  description = "Fleet AppRole material written to ~/.config/bao/approle on first boot."
  type        = string
  sensitive   = true
}

variable "extra_tags" {
  description = "Extra Scaleway tags for the instance."
  type        = list(string)
  default     = []
}
