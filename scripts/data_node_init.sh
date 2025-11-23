#!/bin/bash
set -e

echo "=========================================="
echo "Elasticsearch Data Node Bootstrap"
echo "=========================================="

# Variables from Terraform
ELASTICSEARCH_VERSION="${elasticsearch_version}"
ELASTIC_REPO_VERSION="${elastic_repo_version}"
CLUSTER_NAME="${cluster_name}"
NODE_NAME="${node_name}"
HEAP_SIZE="${heap_size_gb}g"
ES_PORT="${elasticsearch_port}"
ES_TRANSPORT_PORT="${elasticsearch_transport_port}"

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

# Wait for block volume to be attached
echo "Waiting for block volume..."
DEVICE="/dev/oracleoci/oraclevdb"
TIMEOUT=300
ELAPSED=0
while [ ! -b "$${DEVICE}" ] && [ $${ELAPSED} -lt $${TIMEOUT} ]; do
    echo "Waiting for $${DEVICE}... ($${ELAPSED}s)"
    sleep 5
    ELAPSED=$((ELAPSED + 5))
done

if [ ! -b "$${DEVICE}" ]; then
    echo "ERROR: Block volume not found at $${DEVICE}"
    exit 1
fi

# Format and mount block volume
echo "Formatting and mounting block volume..."
if ! blkid "$${DEVICE}"; then
    mkfs.ext4 -F "$${DEVICE}"
fi

mkdir -p /elasticsearch
mount "$${DEVICE}" /elasticsearch

# Add to fstab for persistence
DEVICE_UUID=$(blkid -s UUID -o value "$${DEVICE}")
if ! grep -q "$${DEVICE_UUID}" /etc/fstab; then
    echo "UUID=$${DEVICE_UUID} /elasticsearch ext4 defaults,_netdev,nofail 0 2" >> /etc/fstab
fi

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

# Install Elasticsearch with retry
echo "Installing Elasticsearch..."
if [[ "$${ELASTICSEARCH_VERSION}" =~ ^[0-9]+\.[0-9]+ ]]; then
  # Specific version requested (e.g., "8.15" or "8.15.0")
  echo "Installing Elasticsearch version $${ELASTICSEARCH_VERSION}..."
  retry_command dnf install -y elasticsearch-$${ELASTICSEARCH_VERSION}*
else
  # Major version only (e.g., "8" or "7")
  echo "Installing latest Elasticsearch $${ELASTICSEARCH_VERSION}.x..."
  retry_command dnf install -y elasticsearch
fi

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

# Configure Elasticsearch
echo "Configuring Elasticsearch..."
cat > /etc/elasticsearch/elasticsearch.yml <<EOF
cluster.name: $${CLUSTER_NAME}
node.name: $${NODE_NAME}
node.roles: [data, ingest]
path.data: /elasticsearch/data
path.logs: /elasticsearch/logs
network.host: $${LOCAL_IP}
http.port: $${ES_PORT}
transport.port: $${ES_TRANSPORT_PORT}
discovery.seed_hosts: []
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

# Remove auto-generated HTTP SSL configuration that conflicts with our settings
# Elasticsearch auto-generates xpack.security.http.ssl settings on first install
# We need to remove these before starting to avoid conflicts
echo "Removing auto-generated HTTP SSL configuration..."
sed -i '/^xpack\.security\.http\.ssl:/,/^  keystore\.path:/d' /etc/elasticsearch/elasticsearch.yml

# Configure firewall
echo "Configuring firewall..."
firewall-cmd --permanent --add-port=$${ES_PORT}/tcp
firewall-cmd --permanent --add-port=$${ES_TRANSPORT_PORT}/tcp
firewall-cmd --reload

# Enable and start Elasticsearch
echo "Enabling and starting Elasticsearch..."
systemctl daemon-reload
systemctl enable elasticsearch
systemctl start elasticsearch

echo "=========================================="
echo "Data Node Bootstrap Complete"
echo "Node: $${NODE_NAME}"
echo "IP: $${LOCAL_IP}"
echo "=========================================="

