locals {
  is_flexible_bastion_shape = contains(["VM.Standard.E3.Flex", "VM.Standard.E4.Flex", "VM.Standard.E5.Flex", "VM.Standard.A1.Flex"], var.bastion_shape)
  is_flexible_master_shape  = contains(["VM.Standard.E3.Flex", "VM.Standard.E4.Flex", "VM.Standard.E5.Flex", "VM.Standard.A1.Flex"], var.master_node_shape)
  is_flexible_data_shape    = contains(["VM.Standard.E3.Flex", "VM.Standard.E4.Flex", "VM.Standard.E5.Flex", "VM.Standard.A1.Flex"], var.data_node_shape)
  is_flexible_lb_shape      = var.lb_shape == "flexible"

  elasticsearch_major_version = var.elasticsearch_version
  elastic_repo_version = startswith(var.elasticsearch_version, "8") ? "8.x" : "7.x"

  master_heap_size_gb = min(floor(var.master_node_memory_gb / 2), 31)
  data_heap_size_gb   = min(floor(var.data_node_memory_gb / 2), 31)

  ssh_public_key = var.ssh_public_key != "" ? var.ssh_public_key : (
    var.ssh_private_key_path != "" ? file("${var.ssh_private_key_path}.pub") : tls_private_key.ssh_key[0].public_key_openssh
  )

  ssh_private_key = var.ssh_private_key_path != "" ? file(var.ssh_private_key_path) : tls_private_key.ssh_key[0].private_key_pem

  ssh_private_key_path = var.ssh_private_key_path != "" ? var.ssh_private_key_path : (
    length(local_file.ssh_private_key) > 0 ? local_file.ssh_private_key[0].filename : ""
  )

  master_node_ads = [
    for i in range(var.master_node_count) :
    data.oci_identity_availability_domains.ads.availability_domains[i % length(data.oci_identity_availability_domains.ads.availability_domains)].name
  ]

  data_node_ads = [
    for i in range(var.data_node_count) :
    data.oci_identity_availability_domains.ads.availability_domains[i % length(data.oci_identity_availability_domains.ads.availability_domains)].name
  ]

  master_node_subnets = [
    for i in range(var.master_node_count) :
    oci_core_subnet.private[i % length(oci_core_subnet.private)].id
  ]

  data_node_subnets = [
    for i in range(var.data_node_count) :
    oci_core_subnet.private[i % length(oci_core_subnet.private)].id
  ]

  common_tags = {
    Project     = var.project_tag
    ManagedBy   = "Terraform"
    Environment = "Production"
  }
}

