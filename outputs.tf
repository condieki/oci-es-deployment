output "bastion_public_ip" {
  description = "Public IP address of the bastion host"
  value       = oci_core_instance.bastion.public_ip
}

output "load_balancer_public_ip" {
  description = "Public IP address of the load balancer"
  value       = oci_load_balancer_load_balancer.elasticsearch_lb.ip_address_details[0].ip_address
}

output "elasticsearch_url" {
  description = "URL to access Elasticsearch"
  value       = "http://${oci_load_balancer_load_balancer.elasticsearch_lb.ip_address_details[0].ip_address}:${var.elasticsearch_port}"
}

output "kibana_url" {
  description = "URL to access Kibana"
  value       = "http://${oci_load_balancer_load_balancer.elasticsearch_lb.ip_address_details[0].ip_address}:${var.kibana_port}"
}

output "master_node_private_ips" {
  description = "Private IP addresses of master nodes"
  value       = [for instance in oci_core_instance.master : instance.private_ip]
}

output "data_node_private_ips" {
  description = "Private IP addresses of data nodes"
  value       = [for instance in oci_core_instance.data : instance.private_ip]
}

output "ssh_to_bastion" {
  description = "Command to SSH to bastion host"
  value       = "ssh -i ${local.ssh_private_key_path} opc@${oci_core_instance.bastion.public_ip}"
}

output "ssh_to_master_node" {
  description = "Example command to SSH to a master node via bastion"
  value       = length(oci_core_instance.master) > 0 ? "ssh -i ${local.ssh_private_key_path} -o StrictHostKeyChecking=no -o ProxyCommand='ssh -i ${local.ssh_private_key_path} -o StrictHostKeyChecking=no -W %h:%p opc@${oci_core_instance.bastion.public_ip}' opc@${oci_core_instance.master[0].private_ip}" : "No master nodes"
}

output "ssh_to_data_node" {
  description = "Example command to SSH to a data node via bastion"
  value       = length(oci_core_instance.data) > 0 ? "ssh -i ${local.ssh_private_key_path} -o StrictHostKeyChecking=no -o ProxyCommand='ssh -i ${local.ssh_private_key_path} -o StrictHostKeyChecking=no -W %h:%p opc@${oci_core_instance.bastion.public_ip}' opc@${oci_core_instance.data[0].private_ip}" : "No data nodes"
}

output "cluster_health_check" {
  description = "Command to check cluster health (with authentication)"
  value       = "curl -u elastic:<password> http://${oci_load_balancer_load_balancer.elasticsearch_lb.ip_address_details[0].ip_address}:${var.elasticsearch_port}/_cluster/health?pretty"
}

output "get_elasticsearch_password" {
  description = "Command to retrieve the Elasticsearch 'elastic' user password"
  value       = "ssh -i ${local.ssh_private_key_path} -o StrictHostKeyChecking=no -o ProxyCommand='ssh -i ${local.ssh_private_key_path} -o StrictHostKeyChecking=no -W %h:%p opc@${oci_core_instance.bastion.public_ip}' opc@${oci_core_instance.master[0].private_ip} 'sudo cat /tmp/elastic_password.txt'"
}

output "kibana_login" {
  description = "Kibana login instructions"
  value       = "Username: elastic | Password: Run the command from 'terraform output get_elasticsearch_password'"
}

output "elasticsearch_version" {
  description = "Elasticsearch version deployed"
  value       = var.elasticsearch_version
}

output "cluster_name" {
  description = "Elasticsearch cluster name"
  value       = var.elasticsearch_cluster_name
}

output "ssh_private_key_path" {
  description = "Path to SSH private key (generated or provided)"
  value       = local.ssh_private_key_path
}

output "next_steps" {
  description = "Next steps after deployment"
  value       = <<-EOT

    ========================================
    Elasticsearch Cluster Deployed!
    ========================================

    Elasticsearch URL: http://${oci_load_balancer_load_balancer.elasticsearch_lb.ip_address_details[0].ip_address}:${var.elasticsearch_port}
    Kibana URL:        http://${oci_load_balancer_load_balancer.elasticsearch_lb.ip_address_details[0].ip_address}:${var.kibana_port}

    Bastion Host:      ${oci_core_instance.bastion.public_ip}

    AUTH ENABLED:
    - Username: elastic
    - Password: Run 'terraform output get_elasticsearch_password' to get the retrieval command
    - Use these credentials to log into Kibana and access Elasticsearch API

    Next Steps:
    1. Get the elastic user password:
       $(terraform output -raw get_elasticsearch_password)

    2. Check cluster health (with authentication):
       curl -u elastic:<password> http://${oci_load_balancer_load_balancer.elasticsearch_lb.ip_address_details[0].ip_address}:${var.elasticsearch_port}/_cluster/health?pretty

    3. Access Kibana in your browser:
       http://${oci_load_balancer_load_balancer.elasticsearch_lb.ip_address_details[0].ip_address}:${var.kibana_port}
       Login with username 'elastic' and the password from step 1

    4. SSH to bastion:
       ssh -i ${local.ssh_private_key_path} opc@${oci_core_instance.bastion.public_ip}

    5. From bastion, SSH to any node:
       ssh opc@<node-private-ip>

    Master Nodes: ${join(", ", [for instance in oci_core_instance.master : instance.private_ip])}
    Data Nodes:   ${join(", ", [for instance in oci_core_instance.data : instance.private_ip])}

    ========================================
  EOT
}

