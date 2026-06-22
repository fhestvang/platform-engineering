output "hostname" {
  value = scaleway_instance_server.instance.name
}

output "public_ip" {
  value = scaleway_instance_ip.instance.address
}

output "ssh" {
  value = "ssh ${var.operator_user}@${scaleway_instance_server.instance.name}.olm-hops.ts.net"
}

output "tailscale_ssh" {
  value = "tailscale ssh ${var.operator_user}@${scaleway_instance_server.instance.name}"
}
