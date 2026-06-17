output "name" {
  description = "Instance + tailnet hostname."
  value       = scaleway_instance_server.lab.name
}

output "public_ip" {
  description = "Public IPv4 (SSH fallback; prefer the tailnet name)."
  value       = scaleway_instance_server.lab.public_ip
}

output "ssh_tailnet" {
  description = "How to reach it once it has joined the tailnet."
  value       = "ssh fhestvang@${scaleway_instance_server.lab.name}.olm-hops.ts.net"
}
