
resource "oci_core_instance" "bastion" {
  compartment_id      = var.compartment_ocid
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  display_name        = "elasticsearch-bastion"
  shape               = var.bastion_shape

  dynamic "shape_config" {
    for_each = local.is_flexible_bastion_shape ? [1] : []
    content {
      memory_in_gbs = var.bastion_memory_gb
      ocpus         = var.bastion_ocpus
    }
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.bastion.id
    assign_public_ip = true
    nsg_ids          = [oci_core_network_security_group.bastion_nsg.id]
  }

  metadata = {
    ssh_authorized_keys = local.ssh_public_key
  }

  source_details {
    source_id   = data.oci_core_images.oracle_linux.images[0].id
    source_type = "image"
  }

  freeform_tags = local.common_tags
}


resource "oci_core_instance" "master" {
  count = var.master_node_count

  compartment_id      = var.compartment_ocid
  availability_domain = local.master_node_ads[count.index]
  display_name        = "es-master-${count.index + 1}"
  shape               = var.master_node_shape

  dynamic "shape_config" {
    for_each = local.is_flexible_master_shape ? [1] : []
    content {
      memory_in_gbs = var.master_node_memory_gb
      ocpus         = var.master_node_ocpus
    }
  }

  create_vnic_details {
    subnet_id        = local.master_node_subnets[count.index]
    assign_public_ip = false
    nsg_ids          = [oci_core_network_security_group.elasticsearch_nsg.id]
    hostname_label   = "esmaster${count.index + 1}"
  }

  metadata = {
    ssh_authorized_keys = local.ssh_public_key
    user_data = base64encode(templatefile("${path.module}/scripts/master_node_init.sh", {
      elasticsearch_version        = var.elasticsearch_version
      elastic_repo_version         = local.elastic_repo_version
      cluster_name                 = var.elasticsearch_cluster_name
      node_name                    = "es-master-${count.index + 1}"
      heap_size_gb                 = local.master_heap_size_gb
      elasticsearch_port           = var.elasticsearch_port
      elasticsearch_transport_port = var.elasticsearch_transport_port
      kibana_port                  = var.kibana_port
    }))
  }

  source_details {
    source_id               = data.oci_core_images.master_node_image.images[0].id
    source_type             = "image"
    boot_volume_size_in_gbs = var.boot_volume_size_gb
  }

  freeform_tags = merge(local.common_tags, {
    NodeType = "master"
  })

  depends_on = [oci_core_subnet.private]
}


resource "oci_core_instance" "data" {
  count = var.data_node_count

  compartment_id      = var.compartment_ocid
  availability_domain = local.data_node_ads[count.index]
  display_name        = "es-data-${count.index + 1}"
  shape               = var.data_node_shape

  dynamic "shape_config" {
    for_each = local.is_flexible_data_shape ? [1] : []
    content {
      memory_in_gbs = var.data_node_memory_gb
      ocpus         = var.data_node_ocpus
    }
  }

  create_vnic_details {
    subnet_id        = local.data_node_subnets[count.index]
    assign_public_ip = false
    nsg_ids          = [oci_core_network_security_group.elasticsearch_nsg.id]
    hostname_label   = "esdata${count.index + 1}"
  }

  metadata = {
    ssh_authorized_keys = local.ssh_public_key
    user_data = base64encode(templatefile("${path.module}/scripts/data_node_init.sh", {
      elasticsearch_version        = var.elasticsearch_version
      elastic_repo_version         = local.elastic_repo_version
      cluster_name                 = var.elasticsearch_cluster_name
      node_name                    = "es-data-${count.index + 1}"
      heap_size_gb                 = local.data_heap_size_gb
      elasticsearch_port           = var.elasticsearch_port
      elasticsearch_transport_port = var.elasticsearch_transport_port
    }))
  }

  source_details {
    source_id               = data.oci_core_images.data_node_image.images[0].id
    source_type             = "image"
    boot_volume_size_in_gbs = var.boot_volume_size_gb
  }

  freeform_tags = merge(local.common_tags, {
    NodeType = "data"
  })

  depends_on = [oci_core_subnet.private]
}

