#!/bin/bash
set -e

echo "=========================================="
echo "Elasticsearch Master Node Bootstrap"
echo "=========================================="

# Variables from Terraform
ELASTICSEARCH_VERSION="${elasticsearch_version}"
ELASTIC_REPO_VERSION="${elastic_repo_version}"
CLUSTER_NAME="${cluster_name}"
NODE_NAME="${node_name}"
HEAP_SIZE="${heap_size_gb}g"
ES_PORT="${elasticsearch_port}"
ES_TRANSPORT_PORT="${elasticsearch_transport_port}"
KIBANA_PORT="${kibana_port}"
OCI_STORAGE_ACCESS_KEY="${oci_storage_access_key}"
OCI_STORAGE_SECRET_KEY="${oci_storage_secret_key}"

# Retry function with exponential backoff
retry_command() {
    local max_attempts=3
    local timeout=1
    local attempt=1
    local exitCode=0

    while [ $attempt -le $max_attempts ]; do
        echo "Attempt $attempt of $max_attempts: $@"

        if "$@"; then
            echo "Command succeeded on attempt $attempt"
            return 0
        else
            exitCode=$?
        fi

        if [ $attempt -lt $max_attempts ]; then
            echo "Command failed with exit code $exitCode. Retrying in $timeout seconds..."
            sleep $timeout
            timeout=$((timeout * 2))
        fi

        attempt=$((attempt + 1))
    done

    echo "Command failed after $max_attempts attempts"
    return $exitCode
}

# Wait for network to be ready
echo "Waiting for network to be ready..."
retry_command ping -c 1 8.8.8.8

# Configure DNS to use Google's public DNS (OCI's DNS often fails during cloud-init)
echo "Configuring DNS to use Google's public DNS..."
cat > /etc/resolv.conf <<EOF
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF

# Wait for DNS to be ready
echo "Waiting for DNS to be ready..."
retry_command nslookup artifacts.elastic.co

# System Configuration
echo "Configuring system limits..."
cat >> /etc/security/limits.conf <<EOF
elasticsearch soft nofile 65536
elasticsearch hard nofile 65536
elasticsearch soft nproc 4096
elasticsearch hard nproc 4096
elasticsearch soft memlock unlimited
elasticsearch hard memlock unlimited
EOF

cat >> /etc/sysctl.conf <<EOF
vm.max_map_count=262144
vm.swappiness=1
EOF

sysctl -p

# Disable SELinux for Elasticsearch
echo "Disabling SELinux..."
setenforce 0 || true
sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config

# Install Java with retry
echo "Installing Java..."
retry_command dnf install -y java-11-openjdk java-11-openjdk-devel

# Add Elasticsearch repository with retry
echo "Adding Elasticsearch repository..."
retry_command rpm --import https://artifacts.elastic.co/GPG-KEY-elasticsearch

cat > /etc/yum.repos.d/elasticsearch.repo <<EOF
[elasticsearch]
name=Elasticsearch repository for $${ELASTIC_REPO_VERSION} packages
baseurl=https://artifacts.elastic.co/packages/$${ELASTIC_REPO_VERSION}/yum
gpgcheck=1
gpgkey=https://artifacts.elastic.co/GPG-KEY-elasticsearch
enabled=1
autorefresh=1
type=rpm-md
EOF

# Install Elasticsearch and Kibana with retry
echo "Installing Elasticsearch and Kibana..."
if [[ "$${ELASTICSEARCH_VERSION}" =~ ^[0-9]+\.[0-9]+ ]]; then
  # Specific version requested (e.g., "8.15" or "8.15.0")
  echo "Installing Elasticsearch version $${ELASTICSEARCH_VERSION}..."
  retry_command dnf install -y elasticsearch-$${ELASTICSEARCH_VERSION}* kibana-$${ELASTICSEARCH_VERSION}*
else
  # Major version only (e.g., "8" or "7")
  echo "Installing latest Elasticsearch $${ELASTICSEARCH_VERSION}.x..."
  retry_command dnf install -y elasticsearch kibana
fi

# Install repository-s3 plugin for snapshot support
echo "Installing repository-s3 plugin for OCI Object Storage snapshots..."
/usr/share/elasticsearch/bin/elasticsearch-plugin install --batch repository-s3
echo "Repository-s3 plugin installed successfully"

# Create data directories
echo "Creating data directories..."
mkdir -p /elasticsearch/data /elasticsearch/logs
chown -R elasticsearch:elasticsearch /elasticsearch

# Get local IP - dynamically detect the primary network interface
# This works across different OCI instance types (ens3, enp0s5, etc.)
PRIMARY_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
LOCAL_IP=$(ip addr show "$PRIMARY_INTERFACE" | grep 'inet ' | awk '{print $2}' | cut -f1 -d'/')

echo "Detected primary interface: $PRIMARY_INTERFACE"
echo "Local IP: $LOCAL_IP"

# Remove auto-generated keystore with SSL settings and create a fresh one
echo "Resetting Elasticsearch keystore..."
rm -f /etc/elasticsearch/elasticsearch.keystore
/usr/share/elasticsearch/bin/elasticsearch-keystore create
chown elasticsearch:elasticsearch /etc/elasticsearch/elasticsearch.keystore
chmod 660 /etc/elasticsearch/elasticsearch.keystore

# Temporarily grant write permissions to /etc/elasticsearch for keystore operations
chmod 775 /etc/elasticsearch

# Add OCI Object Storage credentials to keystore if provided
if [ -n "$OCI_STORAGE_ACCESS_KEY" ] && [ -n "$OCI_STORAGE_SECRET_KEY" ]; then
  echo "Adding OCI Object Storage credentials to keystore..."
  echo "$OCI_STORAGE_ACCESS_KEY" | sudo -u elasticsearch /usr/share/elasticsearch/bin/elasticsearch-keystore add --stdin s3.client.default.access_key
  echo "$OCI_STORAGE_SECRET_KEY" | sudo -u elasticsearch /usr/share/elasticsearch/bin/elasticsearch-keystore add --stdin s3.client.default.secret_key
  echo "OCI Object Storage credentials added to keystore"
else
  echo "No OCI Object Storage credentials provided - keystore ready for manual configuration"
fi

# Restore proper permissions to /etc/elasticsearch
chmod 750 /etc/elasticsearch

# Configure Elasticsearch
echo "Configuring Elasticsearch..."
cat > /etc/elasticsearch/elasticsearch.yml <<EOF
cluster.name: $${CLUSTER_NAME}
node.name: $${NODE_NAME}
node.roles: [master, data, ingest]
path.data: /elasticsearch/data
path.logs: /elasticsearch/logs
network.host: $${LOCAL_IP}
http.port: $${ES_PORT}
transport.port: $${ES_TRANSPORT_PORT}
discovery.seed_hosts: []
cluster.initial_master_nodes: []
bootstrap.memory_lock: true

# Disable xpack security for simplicity
xpack.security.enabled: false
EOF

# Configure JVM options
echo "Configuring JVM heap size to $${HEAP_SIZE}..."
cat > /etc/elasticsearch/jvm.options.d/heap.options <<EOF
-Xms$${HEAP_SIZE}
-Xmx$${HEAP_SIZE}
EOF

# Configure systemd for memory lock
echo "Configuring systemd for Elasticsearch..."
mkdir -p /etc/systemd/system/elasticsearch.service.d
cat > /etc/systemd/system/elasticsearch.service.d/override.conf <<EOF
[Service]
LimitMEMLOCK=infinity
EOF

# Configure Kibana
echo "Configuring Kibana..."
cat > /etc/kibana/kibana.yml <<EOF
server.host: "$${LOCAL_IP}"
server.port: $${KIBANA_PORT}
elasticsearch.hosts: ["http://$${LOCAL_IP}:$${ES_PORT}"]
EOF

# Remove auto-generated HTTP SSL configuration that conflicts with our settings
# Elasticsearch auto-generates xpack.security.http.ssl settings on first install
# We need to remove these before starting to avoid conflicts
echo "Removing auto-generated HTTP SSL configuration..."
sed -i '/^xpack\.security\.http\.ssl:/,/^  keystore\.path:/d' /etc/elasticsearch/elasticsearch.yml

# Configure firewall
echo "Configuring firewall..."
firewall-cmd --permanent --add-port=$${ES_PORT}/tcp
firewall-cmd --permanent --add-port=$${ES_TRANSPORT_PORT}/tcp
firewall-cmd --permanent --add-port=$${KIBANA_PORT}/tcp
firewall-cmd --reload

# Enable and start Elasticsearch
echo "Enabling and starting Elasticsearch..."
systemctl daemon-reload
systemctl enable elasticsearch
systemctl start elasticsearch

# Wait for Elasticsearch to be ready
echo "Waiting for Elasticsearch to start..."
timeout 120 bash -c 'until curl -s http://localhost:9200 >/dev/null 2>&1; do echo "Waiting..."; sleep 2; done' || echo "Elasticsearch may not be fully ready yet"



# Start Kibana
echo "Starting Kibana..."
systemctl enable kibana
systemctl start kibana

echo "=========================================="
echo "Master Node Bootstrap Complete"
echo "Node: $${NODE_NAME}"
echo "IP: $${LOCAL_IP}"
echo "=========================================="

