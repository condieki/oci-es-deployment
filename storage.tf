
resource "oci_core_volume" "data_volume" {
  count = var.data_node_count

  compartment_id      = var.compartment_ocid
  availability_domain = local.data_node_ads[count.index]
  display_name        = "es-data-volume-${count.index + 1}"
  size_in_gbs         = var.data_volume_size_gb

  freeform_tags = merge(local.common_tags, {
    AttachedTo = "es-data-${count.index + 1}"
  })
}


resource "oci_core_volume_attachment" "data_volume_attachment" {
  count = var.data_node_count

  attachment_type = "paravirtualized"
  instance_id     = oci_core_instance.data[count.index].id
  volume_id       = oci_core_volume.data_volume[count.index].id
  display_name    = "es-data-volume-attachment-${count.index + 1}"


  device = "/dev/oracleoci/oraclevdb"
}

