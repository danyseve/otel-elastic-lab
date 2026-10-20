output "node_ips" {
  description = "IP address of each k3s node"
  value       = { for name, vm in var.vms : name => vm.ip }
}
