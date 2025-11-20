
resource "oci_core_network_security_group" "bastion_nsg" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.elasticsearch_vcn.id
  display_name   = "bastion-nsg"

  freeform_tags = local.common_tags
}


resource "oci_core_network_security_group_security_rule" "bastion_ingress_ssh" {
  network_security_group_id = oci_core_network_security_group.bastion_nsg.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  stateless                 = false

  tcp_options {
    destination_port_range {
      min = 22
      max = 22
    }
  }
}


resource "oci_core_network_security_group_security_rule" "bastion_egress_all" {
  network_security_group_id = oci_core_network_security_group.bastion_nsg.id
  direction                 = "EGRESS"
  protocol                  = "all"
  destination               = "0.0.0.0/0"
  destination_type          = "CIDR_BLOCK"
  stateless                 = false
}


resource "oci_core_network_security_group" "lb_nsg" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.elasticsearch_vcn.id
  display_name   = "lb-nsg"

  freeform_tags = local.common_tags
}


resource "oci_core_network_security_group_security_rule" "lb_ingress_es" {
  network_security_group_id = oci_core_network_security_group.lb_nsg.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  stateless                 = false

  tcp_options {
    destination_port_range {
      min = var.elasticsearch_port
      max = var.elasticsearch_port
    }
  }
}


resource "oci_core_network_security_group_security_rule" "lb_ingress_kibana" {
  network_security_group_id = oci_core_network_security_group.lb_nsg.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"
  stateless                 = false

  tcp_options {
    destination_port_range {
      min = var.kibana_port
      max = var.kibana_port
    }
  }
}


resource "oci_core_network_security_group_security_rule" "lb_egress_all" {
  network_security_group_id = oci_core_network_security_group.lb_nsg.id
  direction                 = "EGRESS"
  protocol                  = "all"
  destination               = "0.0.0.0/0"
  destination_type          = "CIDR_BLOCK"
  stateless                 = false
}


resource "oci_core_network_security_group" "elasticsearch_nsg" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.elasticsearch_vcn.id
  display_name   = "elasticsearch-nsg"

  freeform_tags = local.common_tags
}


resource "oci_core_network_security_group_security_rule" "es_ingress_ssh" {
  network_security_group_id = oci_core_network_security_group.elasticsearch_nsg.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source                    = oci_core_network_security_group.bastion_nsg.id
  source_type               = "NETWORK_SECURITY_GROUP"
  stateless                 = false

  tcp_options {
    destination_port_range {
      min = 22
      max = 22
    }
  }
}


resource "oci_core_network_security_group_security_rule" "es_ingress_http_from_lb" {
  network_security_group_id = oci_core_network_security_group.elasticsearch_nsg.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source                    = oci_core_network_security_group.lb_nsg.id
  source_type               = "NETWORK_SECURITY_GROUP"
  stateless                 = false

  tcp_options {
    destination_port_range {
      min = var.elasticsearch_port
      max = var.elasticsearch_port
    }
  }
}


resource "oci_core_network_security_group_security_rule" "es_ingress_kibana_from_lb" {
  network_security_group_id = oci_core_network_security_group.elasticsearch_nsg.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source                    = oci_core_network_security_group.lb_nsg.id
  source_type               = "NETWORK_SECURITY_GROUP"
  stateless                 = false

  tcp_options {
    destination_port_range {
      min = var.kibana_port
      max = var.kibana_port
    }
  }
}


resource "oci_core_network_security_group_security_rule" "es_ingress_http_cluster" {
  network_security_group_id = oci_core_network_security_group.elasticsearch_nsg.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source                    = oci_core_network_security_group.elasticsearch_nsg.id
  source_type               = "NETWORK_SECURITY_GROUP"
  stateless                 = false

  tcp_options {
    destination_port_range {
      min = var.elasticsearch_port
      max = var.elasticsearch_port
    }
  }
}


resource "oci_core_network_security_group_security_rule" "es_ingress_transport_cluster" {
  network_security_group_id = oci_core_network_security_group.elasticsearch_nsg.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source                    = oci_core_network_security_group.elasticsearch_nsg.id
  source_type               = "NETWORK_SECURITY_GROUP"
  stateless                 = false

  tcp_options {
    destination_port_range {
      min = var.elasticsearch_transport_port
      max = var.elasticsearch_transport_port
    }
  }
}


resource "oci_core_network_security_group_security_rule" "es_egress_all" {
  network_security_group_id = oci_core_network_security_group.elasticsearch_nsg.id
  direction                 = "EGRESS"
  protocol                  = "all"
  destination               = "0.0.0.0/0"
  destination_type          = "CIDR_BLOCK"
  stateless                 = false
}

