
resource "oci_load_balancer_load_balancer" "elasticsearch_lb" {
  compartment_id = var.compartment_ocid
  display_name   = "elasticsearch-lb"
  shape          = var.lb_shape

  dynamic "shape_details" {
    for_each = local.is_flexible_lb_shape ? [1] : []
    content {
      minimum_bandwidth_in_mbps = var.lb_min_bandwidth_mbps
      maximum_bandwidth_in_mbps = var.lb_max_bandwidth_mbps
    }
  }

  subnet_ids = [oci_core_subnet.lb.id]
  is_private = false

  network_security_group_ids = [oci_core_network_security_group.lb_nsg.id]

  freeform_tags = local.common_tags

  depends_on = [
    oci_core_instance.master,
    oci_core_instance.data
  ]
}


resource "oci_load_balancer_backend_set" "elasticsearch" {
  load_balancer_id = oci_load_balancer_load_balancer.elasticsearch_lb.id
  name             = "elasticsearch-backend"
  policy           = "ROUND_ROBIN"

  health_checker {
    protocol          = "TCP"
    port              = var.elasticsearch_port
    interval_ms       = 10000
    timeout_in_millis = 3000
    retries           = 3
  }
}


resource "oci_load_balancer_backend_set" "kibana" {
  load_balancer_id = oci_load_balancer_load_balancer.elasticsearch_lb.id
  name             = "kibana-backend"
  policy           = "ROUND_ROBIN"

  health_checker {
    protocol          = "TCP"
    port              = var.kibana_port
    interval_ms       = 10000
    timeout_in_millis = 3000
    retries           = 3
  }
}


resource "oci_load_balancer_backend" "elasticsearch" {
  count = var.data_node_count

  load_balancer_id = oci_load_balancer_load_balancer.elasticsearch_lb.id
  backendset_name  = oci_load_balancer_backend_set.elasticsearch.name
  ip_address       = oci_core_instance.data[count.index].private_ip
  port             = var.elasticsearch_port
  backup           = false
  drain            = false
  offline          = false
  weight           = 1
}


resource "oci_load_balancer_backend" "kibana" {
  count = var.master_node_count

  load_balancer_id = oci_load_balancer_load_balancer.elasticsearch_lb.id
  backendset_name  = oci_load_balancer_backend_set.kibana.name
  ip_address       = oci_core_instance.master[count.index].private_ip
  port             = var.kibana_port
  backup           = false
  drain            = false
  offline          = false
  weight           = 1
}


resource "oci_load_balancer_listener" "elasticsearch" {
  load_balancer_id         = oci_load_balancer_load_balancer.elasticsearch_lb.id
  name                     = "elasticsearch-listener"
  default_backend_set_name = oci_load_balancer_backend_set.elasticsearch.name
  port                     = var.elasticsearch_port
  protocol                 = "HTTP"

  connection_configuration {
    idle_timeout_in_seconds = 300
  }
}


resource "oci_load_balancer_listener" "kibana" {
  load_balancer_id         = oci_load_balancer_load_balancer.elasticsearch_lb.id
  name                     = "kibana-listener"
  default_backend_set_name = oci_load_balancer_backend_set.kibana.name
  port                     = var.kibana_port
  protocol                 = "HTTP"

  connection_configuration {
    idle_timeout_in_seconds = 300
  }
}

