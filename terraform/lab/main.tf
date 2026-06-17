resource "scaleway_instance_security_group" "lab" {
  name                    = "${var.name}-sg"
  zone                    = var.zone
  inbound_default_policy  = "drop"
  outbound_default_policy = "accept"
  tags                    = var.tags

  inbound_rule {
    action   = "accept"
    port     = "22"
    ip_range = var.ssh_allowed_cidr
  }
}

resource "scaleway_instance_server" "lab" {
  name              = var.name
  type              = var.instance_type
  image             = var.image
  zone              = var.zone
  tags              = var.tags
  enable_dynamic_ip = true
  security_group_id = scaleway_instance_security_group.lab.id

  cloud_init = templatefile("${path.module}/cloud-init.yaml.tftpl", {
    hostname          = var.name
    ssh_pubkey        = var.ssh_pubkey
    tailscale_authkey = var.tailscale_authkey
    dotfiles_repo     = var.dotfiles_repo
  })
}
