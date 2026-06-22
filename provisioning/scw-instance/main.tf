locals {
  cloud_init = templatefile("${path.module}/templates/agent-host.cloud-init.yaml.tftpl", {
    hostname                = var.hostname
    operator_user           = var.operator_user
    operator_ssh_public_key = var.operator_ssh_public_key
    tailscale_auth_key      = var.tailscale_auth_key
    bao_approle_content     = var.bao_approle_content
  })
}

resource "scaleway_instance_ip" "instance" {
  zone = var.zone
}

resource "scaleway_instance_security_group" "instance" {
  name                    = "${var.hostname}-ssh"
  description             = "Public SSH break-glass for ${var.hostname}; normal access is over Tailscale."
  inbound_default_policy  = "drop"
  outbound_default_policy = "accept"
  zone                    = var.zone

  inbound_rule {
    action   = "accept"
    protocol = "TCP"
    port     = 22
  }
}

resource "scaleway_instance_server" "instance" {
  name              = var.hostname
  type              = var.instance_type
  image             = var.image
  ip_id             = scaleway_instance_ip.instance.id
  security_group_id = scaleway_instance_security_group.instance.id
  tags              = concat(["fleet", "agent", "scw-agent"], var.extra_tags)
  zone              = var.zone

  user_data = {
    "cloud-init" = local.cloud_init
  }

  root_volume {
    size_in_gb = var.root_volume_size_gb
  }
}
