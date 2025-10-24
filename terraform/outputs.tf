output "controlplane_ip" {
  value       = libvirt_domain.controlplane.network_interface[0].addresses[0]
  description = "IP do Control Plane"
}

output "worker_ips" {
  value       = [for w in libvirt_domain.worker : w.network_interface[0].addresses[0]]
  description = "IPs dos Workers"
}

output "ssh_command" {
  value = "ssh ubuntu@${libvirt_domain.controlplane.network_interface[0].addresses[0]}"
}
