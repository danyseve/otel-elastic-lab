output "vm_ips" {
  description = "IP address of each VM"
  value       = { for name, vm in var.vms : name => vm.ip }
}

output "kibana_url" {
  description = "Kibana runs on the first Elasticsearch VM"
  value       = "https://${sort(keys(local.es_vms))[0]}.${var.domain}:5601"
}
