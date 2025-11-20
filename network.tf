
resource "oci_core_vcn" "elasticsearch_vcn" {
  compartment_id = var.compartment_ocid
  cidr_blocks    = [var.vcn_cidr]
  display_name   = "elasticsearch-vcn"
  dns_label      = "esvcn"

  freeform_tags = local.common_tags
}


resource "oci_core_internet_gateway" "igw" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.elasticsearch_vcn.id
  display_name   = "elasticsearch-igw"
  enabled        = true

  freeform_tags = local.common_tags
}


resource "oci_core_nat_gateway" "natgw" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.elasticsearch_vcn.id
  display_name   = "elasticsearch-natgw"

  freeform_tags = local.common_tags
}


resource "oci_core_service_gateway" "service_gateway" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.elasticsearch_vcn.id
  display_name   = "elasticsearch-sgw"

  services {
    service_id = data.oci_core_services.all_services.services[0].id
  }

  freeform_tags = local.common_tags
}


data "oci_core_services" "all_services" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}


resource "oci_core_route_table" "public_rt" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.elasticsearch_vcn.id
  display_name   = "public-route-table"

  route_rules {
    network_entity_id = oci_core_internet_gateway.igw.id
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
  }

  freeform_tags = local.common_tags
}


resource "oci_core_route_table" "private_rt" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.elasticsearch_vcn.id
  display_name   = "private-route-table"

  route_rules {
    network_entity_id = oci_core_nat_gateway.natgw.id
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
  }

  route_rules {
    network_entity_id = oci_core_service_gateway.service_gateway.id
    destination       = data.oci_core_services.all_services.services[0].cidr_block
    destination_type  = "SERVICE_CIDR_BLOCK"
  }

  freeform_tags = local.common_tags
}


resource "oci_core_subnet" "bastion" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.elasticsearch_vcn.id
  cidr_block                 = var.bastion_subnet_cidr
  display_name               = "bastion-subnet"
  dns_label                  = "bastion"
  route_table_id             = oci_core_route_table.public_rt.id
  prohibit_public_ip_on_vnic = false
  availability_domain        = data.oci_identity_availability_domains.ads.availability_domains[0].name

  freeform_tags = local.common_tags
}


resource "oci_core_subnet" "lb" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.elasticsearch_vcn.id
  cidr_block                 = var.lb_subnet_cidr
  display_name               = "lb-subnet"
  dns_label                  = "lb"
  route_table_id             = oci_core_route_table.public_rt.id
  prohibit_public_ip_on_vnic = false

  freeform_tags = local.common_tags
}


resource "oci_core_subnet" "private" {
  count = min(length(var.private_subnet_cidrs), length(data.oci_identity_availability_domains.ads.availability_domains))

  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.elasticsearch_vcn.id
  cidr_block                 = var.private_subnet_cidrs[count.index]
  display_name               = "private-subnet-ad${count.index + 1}"
  dns_label                  = "privad${count.index + 1}"
  route_table_id             = oci_core_route_table.private_rt.id
  prohibit_public_ip_on_vnic = true
  availability_domain        = data.oci_identity_availability_domains.ads.availability_domains[count.index].name

  freeform_tags = local.common_tags
}

