locals {
  master_node_ips = [for instance in oci_core_instance.master : instance.private_ip]
  data_node_ips   = [for instance in oci_core_instance.data : instance.private_ip]
  master_node_names = [for i in range(var.master_node_count) : "es-master-${i + 1}"]
}

locals {
  configure_cluster_script = <<-EOT
    #!/bin/bash
    set -e

    echo "Configuring Elasticsearch cluster discovery settings..."

    sudo sed -i 's/discovery.seed_hosts: \[\]/discovery.seed_hosts: [${join(",", formatlist("\"%s\"", local.master_node_ips))}]/' /etc/elasticsearch/elasticsearch.yml

    if grep -q "node.roles: \[master" /etc/elasticsearch/elasticsearch.yml; then
      sudo sed -i 's/cluster.initial_master_nodes: \[\]/cluster.initial_master_nodes: [${join(",", formatlist("\"%s\"", local.master_node_names))}]/' /etc/elasticsearch/elasticsearch.yml
      echo "Master node configuration applied"
    else
      echo "Data node - skipping cluster.initial_master_nodes"
    fi

    echo "Restarting Elasticsearch..."
    sudo systemctl restart elasticsearch

    echo "Cluster configuration complete!"
  EOT
}


resource "null_resource" "configure_master_nodes" {
  count = var.master_node_count

  depends_on = [
    oci_core_instance.master,
    oci_core_instance.data,
    oci_core_instance.bastion
  ]

  triggers = {
    master_ips = join(",", local.master_node_ips)
    data_ips   = join(",", local.data_node_ips)
  }

  provisioner "file" {
    connection {
      type                = "ssh"
      user                = "opc"
      host                = oci_core_instance.master[count.index].private_ip
      private_key         = local.ssh_private_key != "" ? local.ssh_private_key : file(var.private_key_path)
      bastion_host        = oci_core_instance.bastion.public_ip
      bastion_user        = "opc"
      bastion_private_key = local.ssh_private_key != "" ? local.ssh_private_key : file(var.private_key_path)
      timeout             = "10m"
    }

    content     = local.configure_cluster_script
    destination = "/home/opc/configure_cluster.sh"
  }

  provisioner "remote-exec" {
    connection {
      type                = "ssh"
      user                = "opc"
      host                = oci_core_instance.master[count.index].private_ip
      private_key         = local.ssh_private_key != "" ? local.ssh_private_key : file(var.private_key_path)
      bastion_host        = oci_core_instance.bastion.public_ip
      bastion_user        = "opc"
      bastion_private_key = local.ssh_private_key != "" ? local.ssh_private_key : file(var.private_key_path)
      timeout             = "10m"
    }

    inline = [
      "echo 'Waiting for cloud-init to complete...'",
      "sudo cloud-init status --wait || true",
      "echo 'Waiting for Elasticsearch to be installed...'",
      "timeout 600 bash -c 'until systemctl is-active elasticsearch >/dev/null 2>&1; do echo \"Waiting for Elasticsearch...\"; sleep 5; done' || echo 'Elasticsearch not running yet, will configure anyway'",
      "chmod +x /home/opc/configure_cluster.sh",
      "sudo /home/opc/configure_cluster.sh",
      "sleep 10",
      "sudo systemctl status elasticsearch --no-pager || true"
    ]
  }
}


resource "null_resource" "configure_data_nodes" {
  count = var.data_node_count

  depends_on = [
    oci_core_instance.master,
    oci_core_instance.data,
    oci_core_instance.bastion
  ]

  triggers = {
    master_ips = join(",", local.master_node_ips)
    data_ips   = join(",", local.data_node_ips)
  }

  provisioner "file" {
    connection {
      type                = "ssh"
      user                = "opc"
      host                = oci_core_instance.data[count.index].private_ip
      private_key         = local.ssh_private_key != "" ? local.ssh_private_key : file(var.private_key_path)
      bastion_host        = oci_core_instance.bastion.public_ip
      bastion_user        = "opc"
      bastion_private_key = local.ssh_private_key != "" ? local.ssh_private_key : file(var.private_key_path)
      timeout             = "10m"
    }

    content     = local.configure_cluster_script
    destination = "/home/opc/configure_cluster.sh"
  }

  provisioner "remote-exec" {
    connection {
      type                = "ssh"
      user                = "opc"
      host                = oci_core_instance.data[count.index].private_ip
      private_key         = local.ssh_private_key != "" ? local.ssh_private_key : file(var.private_key_path)
      bastion_host        = oci_core_instance.bastion.public_ip
      bastion_user        = "opc"
      bastion_private_key = local.ssh_private_key != "" ? local.ssh_private_key : file(var.private_key_path)
      timeout             = "10m"
    }

    inline = [
      "echo 'Waiting for cloud-init to complete...'",
      "sudo cloud-init status --wait || true",
      "echo 'Waiting for Elasticsearch to be installed...'",
      "timeout 600 bash -c 'until systemctl is-active elasticsearch >/dev/null 2>&1; do echo \"Waiting for Elasticsearch...\"; sleep 5; done' || echo 'Elasticsearch not running yet, will configure anyway'",
      "chmod +x /home/opc/configure_cluster.sh",
      "sudo /home/opc/configure_cluster.sh",
      "sleep 10",
      "sudo systemctl status elasticsearch --no-pager || true"
    ]
  }
}


resource "null_resource" "check_cluster_health" {
  depends_on = [
    null_resource.configure_master_nodes,
    null_resource.configure_data_nodes
  ]

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting 30 seconds for cluster to form..."
      sleep 30
      echo "Checking cluster health via load balancer..."
      curl -s http://${oci_load_balancer_load_balancer.elasticsearch_lb.ip_address_details[0].ip_address}:${var.elasticsearch_port}/_cluster/health?pretty || echo "Cluster not ready yet"
    EOT
  }
}


resource "null_resource" "generate_certificates" {
  depends_on = [null_resource.check_cluster_health]

  connection {
    type                = "ssh"
    user                = "opc"
    host                = oci_core_instance.master[0].private_ip
    private_key         = local.ssh_private_key
    bastion_host        = oci_core_instance.bastion.public_ip
    bastion_user        = "opc"
    bastion_private_key = local.ssh_private_key
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'Generating CA and certificates on first master node...'",
      "sudo /usr/share/elasticsearch/bin/elasticsearch-certutil ca --silent --pass '' --out /tmp/elastic-stack-ca.p12",
      "sudo /usr/share/elasticsearch/bin/elasticsearch-certutil cert --silent --pass '' --ca /tmp/elastic-stack-ca.p12 --ca-pass '' --out /tmp/elastic-certificates.p12",
      "sudo cp /tmp/elastic-certificates.p12 /etc/elasticsearch/elastic-certificates.p12",
      "sudo chown elasticsearch:elasticsearch /etc/elasticsearch/elastic-certificates.p12",
      "sudo chmod 660 /etc/elasticsearch/elastic-certificates.p12",
      "sudo chmod 644 /tmp/elastic-certificates.p12",
      "echo 'CA and certificates generated successfully'"
    ]
  }
}


resource "null_resource" "download_certificate" {
  depends_on = [null_resource.generate_certificates]

  connection {
    type                = "ssh"
    user                = "opc"
    host                = oci_core_instance.master[0].private_ip
    private_key         = local.ssh_private_key
    bastion_host        = oci_core_instance.bastion.public_ip
    bastion_user        = "opc"
    bastion_private_key = local.ssh_private_key
  }


  provisioner "remote-exec" {
    inline = [
      "sudo chmod 644 /tmp/elastic-certificates.p12"
    ]
  }


  provisioner "local-exec" {
    command = <<-EOT
      scp -o StrictHostKeyChecking=no \
        -o ProxyCommand="ssh -o StrictHostKeyChecking=no -i ${var.ssh_private_key_path} -W %h:%p opc@${oci_core_instance.bastion.public_ip}" \
        -i ${var.ssh_private_key_path} \
        opc@${oci_core_instance.master[0].private_ip}:/tmp/elastic-certificates.p12 \
        /tmp/elastic-certificates.p12
    EOT
  }
}


resource "null_resource" "upload_certificates_master" {
  count = var.master_node_count - 1

  depends_on = [null_resource.download_certificate]

  connection {
    type                = "ssh"
    user                = "opc"
    host                = oci_core_instance.master[count.index + 1].private_ip
    private_key         = local.ssh_private_key
    bastion_host        = oci_core_instance.bastion.public_ip
    bastion_user        = "opc"
    bastion_private_key = local.ssh_private_key
  }

  provisioner "file" {
    source      = "/tmp/elastic-certificates.p12"
    destination = "/tmp/elastic-certificates.p12"
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'Installing certificate on master node ${count.index + 2}...'",
      "sudo mv /tmp/elastic-certificates.p12 /etc/elasticsearch/elastic-certificates.p12",
      "sudo chown elasticsearch:elasticsearch /etc/elasticsearch/elastic-certificates.p12",
      "sudo chmod 660 /etc/elasticsearch/elastic-certificates.p12",
      "echo 'Certificate installed successfully'"
    ]
  }
}


resource "null_resource" "upload_certificates_data" {
  count = var.data_node_count

  depends_on = [null_resource.download_certificate]

  connection {
    type                = "ssh"
    user                = "opc"
    host                = oci_core_instance.data[count.index].private_ip
    private_key         = local.ssh_private_key
    bastion_host        = oci_core_instance.bastion.public_ip
    bastion_user        = "opc"
    bastion_private_key = local.ssh_private_key
  }

  provisioner "file" {
    source      = "/tmp/elastic-certificates.p12"
    destination = "/tmp/elastic-certificates.p12"
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'Installing certificate on data node ${count.index + 1}...'",
      "sudo mv /tmp/elastic-certificates.p12 /etc/elasticsearch/elastic-certificates.p12",
      "sudo chown elasticsearch:elasticsearch /etc/elasticsearch/elastic-certificates.p12",
      "sudo chmod 660 /etc/elasticsearch/elastic-certificates.p12",
      "echo 'Certificate installed successfully'"
    ]
  }
}


resource "null_resource" "enable_security" {
  count = var.master_node_count

  depends_on = [
    null_resource.generate_certificates,
    null_resource.upload_certificates_master
  ]

  connection {
    type                = "ssh"
    user                = "opc"
    host                = oci_core_instance.master[count.index].private_ip
    private_key         = local.ssh_private_key
    bastion_host        = oci_core_instance.bastion.public_ip
    bastion_user        = "opc"
    bastion_private_key = local.ssh_private_key
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'Enabling security on master node ${count.index + 1}...'",
      "sudo sed -i 's/xpack.security.enabled: false/xpack.security.enabled: true/' /etc/elasticsearch/elasticsearch.yml",
      "echo 'xpack.security.transport.ssl.enabled: true' | sudo tee -a /etc/elasticsearch/elasticsearch.yml",
      "echo 'xpack.security.transport.ssl.verification_mode: certificate' | sudo tee -a /etc/elasticsearch/elasticsearch.yml",
      "echo 'xpack.security.transport.ssl.client_authentication: required' | sudo tee -a /etc/elasticsearch/elasticsearch.yml",
      "echo 'xpack.security.transport.ssl.keystore.path: elastic-certificates.p12' | sudo tee -a /etc/elasticsearch/elasticsearch.yml",
      "echo 'xpack.security.transport.ssl.truststore.path: elastic-certificates.p12' | sudo tee -a /etc/elasticsearch/elasticsearch.yml",
      "echo '' | sudo /usr/share/elasticsearch/bin/elasticsearch-keystore add -x xpack.security.transport.ssl.keystore.secure_password",
      "echo '' | sudo /usr/share/elasticsearch/bin/elasticsearch-keystore add -x xpack.security.transport.ssl.truststore.secure_password",
      "echo 'xpack.security.http.ssl.enabled: false' | sudo tee -a /etc/elasticsearch/elasticsearch.yml",
      "echo 'Security enabled on master node ${count.index + 1}'"
    ]
  }
}


resource "null_resource" "enable_security_data" {
  count = var.data_node_count

  depends_on = [null_resource.upload_certificates_data]

  connection {
    type                = "ssh"
    user                = "opc"
    host                = oci_core_instance.data[count.index].private_ip
    private_key         = local.ssh_private_key
    bastion_host        = oci_core_instance.bastion.public_ip
    bastion_user        = "opc"
    bastion_private_key = local.ssh_private_key
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'Enabling security on data node ${count.index + 1}...'",
      "sudo sed -i 's/xpack.security.enabled: false/xpack.security.enabled: true/' /etc/elasticsearch/elasticsearch.yml",
      "echo 'xpack.security.transport.ssl.enabled: true' | sudo tee -a /etc/elasticsearch/elasticsearch.yml",
      "echo 'xpack.security.transport.ssl.verification_mode: certificate' | sudo tee -a /etc/elasticsearch/elasticsearch.yml",
      "echo 'xpack.security.transport.ssl.client_authentication: required' | sudo tee -a /etc/elasticsearch/elasticsearch.yml",
      "echo 'xpack.security.transport.ssl.keystore.path: elastic-certificates.p12' | sudo tee -a /etc/elasticsearch/elasticsearch.yml",
      "echo 'xpack.security.transport.ssl.truststore.path: elastic-certificates.p12' | sudo tee -a /etc/elasticsearch/elasticsearch.yml",
      "echo '' | sudo /usr/share/elasticsearch/bin/elasticsearch-keystore add -x xpack.security.transport.ssl.keystore.secure_password",
      "echo '' | sudo /usr/share/elasticsearch/bin/elasticsearch-keystore add -x xpack.security.transport.ssl.truststore.secure_password",
      "echo 'xpack.security.http.ssl.enabled: false' | sudo tee -a /etc/elasticsearch/elasticsearch.yml",
      "echo 'Security enabled on data node ${count.index + 1}'"
    ]
  }
}

resource "null_resource" "restart_master_nodes" {
  count = var.master_node_count

  depends_on = [
    null_resource.enable_security,
    null_resource.enable_security_data
  ]

  connection {
    type                = "ssh"
    user                = "opc"
    host                = oci_core_instance.master[count.index].private_ip
    private_key         = local.ssh_private_key
    bastion_host        = oci_core_instance.bastion.public_ip
    bastion_user        = "opc"
    bastion_private_key = local.ssh_private_key
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'Restarting Elasticsearch on master node ${count.index + 1}...'",
      "sudo systemctl restart elasticsearch",
      "echo 'Elasticsearch restarted on master node ${count.index + 1}'"
    ]
  }
}

resource "null_resource" "restart_data_nodes" {
  count = var.data_node_count

  depends_on = [
    null_resource.enable_security,
    null_resource.enable_security_data
  ]

  connection {
    type                = "ssh"
    user                = "opc"
    host                = oci_core_instance.data[count.index].private_ip
    private_key         = local.ssh_private_key
    bastion_host        = oci_core_instance.bastion.public_ip
    bastion_user        = "opc"
    bastion_private_key = local.ssh_private_key
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'Restarting Elasticsearch on data node ${count.index + 1}...'",
      "sudo systemctl restart elasticsearch",
      "echo 'Elasticsearch restarted on data node ${count.index + 1}'"
    ]
  }
}

resource "null_resource" "wait_for_restart" {
  depends_on = [
    null_resource.restart_master_nodes,
    null_resource.restart_data_nodes
  ]

  provisioner "local-exec" {
    command = "echo 'Waiting 240 seconds (4 minutes) for cluster to fully stabilize...' && sleep 240"
  }
}

resource "null_resource" "set_passwords" {
  depends_on = [null_resource.wait_for_restart]

  connection {
    type                = "ssh"
    user                = "opc"
    host                = oci_core_instance.master[0].private_ip
    private_key         = local.ssh_private_key
    bastion_host        = oci_core_instance.bastion.public_ip
    bastion_user        = "opc"
    bastion_private_key = local.ssh_private_key
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'Setting up Elasticsearch passwords...'",
      "echo 'Attempting to reset elastic user password (will retry up to 20 times)...'",
      "for i in {1..20}; do if sudo /usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic -b -s > /tmp/elastic_password.txt 2>&1 && grep -v 'ERROR' /tmp/elastic_password.txt > /dev/null; then echo 'Elastic password set successfully!'; cat /tmp/elastic_password.txt; break; else echo \"Retry $i/20 for elastic password (cluster may still be initializing)...\"; sleep 20; fi; done",
      "echo 'Attempting to reset kibana_system user password...'",
      "for i in {1..20}; do if sudo /usr/share/elasticsearch/bin/elasticsearch-reset-password -u kibana_system -b -s > /tmp/kibana_password.txt 2>&1 && grep -v 'ERROR' /tmp/kibana_password.txt > /dev/null; then echo 'Kibana password set successfully!'; cat /tmp/kibana_password.txt; break; else echo \"Retry $i/20 for kibana password...\"; sleep 20; fi; done",
      "echo 'Password setup complete!'",
      "echo 'Verifying password files...'",
      "if grep -q 'ERROR' /tmp/elastic_password.txt; then echo 'WARNING: Elastic password reset may have failed'; else echo 'Elastic password file OK'; fi",
      "if grep -q 'ERROR' /tmp/kibana_password.txt; then echo 'WARNING: Kibana password reset may have failed'; else echo 'Kibana password file OK'; fi"
    ]
  }
}

resource "null_resource" "copy_passwords_to_masters" {
  depends_on = [null_resource.set_passwords]

  count = var.master_node_count - 1

  connection {
    type                = "ssh"
    user                = "opc"
    host                = oci_core_instance.master[0].private_ip
    private_key         = local.ssh_private_key
    bastion_host        = oci_core_instance.bastion.public_ip
    bastion_user        = "opc"
    bastion_private_key = local.ssh_private_key
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'Copying password files to master node ${count.index + 2}...'",
      "scp -o StrictHostKeyChecking=no /tmp/elastic_password.txt /tmp/kibana_password.txt opc@${oci_core_instance.master[count.index + 1].private_ip}:/tmp/",
      "echo 'Password files copied to master node ${count.index + 2}'"
    ]
  }
}

resource "null_resource" "configure_kibana_auth" {
  depends_on = [null_resource.copy_passwords_to_masters]

  count = var.master_node_count

  connection {
    type                = "ssh"
    user                = "opc"
    host                = oci_core_instance.master[count.index].private_ip
    private_key         = local.ssh_private_key
    bastion_host        = oci_core_instance.bastion.public_ip
    bastion_user        = "opc"
    bastion_private_key = local.ssh_private_key
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'Configuring Kibana authentication on master node ${count.index + 1}...'",
      "KIBANA_PASSWORD=$(sudo cat /tmp/kibana_password.txt)",
      "sudo tee -a /etc/kibana/kibana.yml > /dev/null <<EOF",
      "elasticsearch.username: \"kibana_system\"",
      "elasticsearch.password: \"$KIBANA_PASSWORD\"",
      "EOF",
      "sudo systemctl restart kibana",
      "echo 'Kibana configured and restarted on master node ${count.index + 1}'"
    ]
  }
}

resource "null_resource" "wait_for_kibana" {
  depends_on = [null_resource.configure_kibana_auth]

  provisioner "local-exec" {
    command = "echo 'Waiting 30 seconds for Kibana to start...' && sleep 30"
  }
}

resource "null_resource" "display_credentials" {
  depends_on = [null_resource.wait_for_kibana]

  provisioner "local-exec" {
    command = <<-EOT
      echo ""
      echo "========================================="
      echo "✅ ELASTICSEARCH CLUSTER DEPLOYED!"
      echo "========================================="
      echo ""
      echo "🔐 Retrieving credentials..."
      echo ""
      ELASTIC_PASSWORD=$(ssh -o StrictHostKeyChecking=no -i ${var.ssh_private_key_path} -J opc@${oci_core_instance.bastion.public_ip} opc@${oci_core_instance.master[0].private_ip} 'sudo cat /tmp/elastic_password.txt' 2>/dev/null)
      KIBANA_PASSWORD=$(ssh -o StrictHostKeyChecking=no -i ${var.ssh_private_key_path} -J opc@${oci_core_instance.bastion.public_ip} opc@${oci_core_instance.master[0].private_ip} 'sudo cat /tmp/kibana_password.txt' 2>/dev/null)
      echo "Username: elastic"
      echo "Password: $ELASTIC_PASSWORD"
      echo ""
      echo "🌐 Access URLs:"
      echo "   Elasticsearch: http://${oci_load_balancer_load_balancer.elasticsearch_lb.ip_address_details[0].ip_address}:9200"
      echo "   Kibana: http://${oci_load_balancer_load_balancer.elasticsearch_lb.ip_address_details[0].ip_address}:5601"
      echo ""
      echo "📝 Test command:"
      echo "   curl -u elastic:$ELASTIC_PASSWORD http://${oci_load_balancer_load_balancer.elasticsearch_lb.ip_address_details[0].ip_address}:9200/_cluster/health?pretty"
      echo ""
      echo "========================================="
    EOT
  }
}

