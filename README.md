# Elasticsearch Cluster on Oracle Cloud Infrastructure (OCI)

This Terraform configuration deploys a production-ready Elasticsearch cluster on Oracle Cloud Infrastructure with the following features:

## Architecture

- **Master Nodes**: 3 nodes (configurable) running Elasticsearch master role + Kibana
- **Data Nodes**: 3 nodes (configurable) running Elasticsearch data role with dedicated block storage
- **Load Balancer**: Public-facing load balancer for Elasticsearch and Kibana access
- **Bastion Host**: Secure SSH access to private nodes
- **Multi-AD Deployment**: Nodes distributed across availability domains for high availability
- **Network Security Groups**: Modern security using NSGs instead of security lists

## Features

- ✅ **Elasticsearch Version Selection**: Choose between Elasticsearch 7.x or 8.x
- ✅ **Security Enabled by Default**: Automatic TLS certificate generation and password setup
- ✅ **Configurable Node Count**: Adjust master and data node counts
- ✅ **Flexible Compute Shapes**: Use OCI Flex shapes with configurable OCPUs and memory
- ✅ **Automated Installation**: Uses official Elastic repositories (no tarballs)
- ✅ **Block Volume Storage**: Dedicated storage for data nodes with automatic mounting
- ✅ **Load Balancer**: Configured with health checks for both Elasticsearch and Kibana
- ✅ **Firewall Configuration**: Automatically opens required ports
- ✅ **Auto-scaling Ready**: Easy to add more nodes by changing variables

## Prerequisites

1. **OCI Account** with appropriate permissions to create:
   - VCN, Subnets, Gateways, Route Tables
   - Network Security Groups
   - Compute Instances
   - Block Volumes
   - Load Balancers

2. **Terraform** >= 1.5.0 installed

3. **OCI CLI** configured (optional but recommended)

4. **API Key** for OCI authentication

## Quick Start

### 1. Clone and Configure

```bash
cd /path/to/your/directory
cp terraform.tfvars.example terraform.tfvars
```

### 2. Edit terraform.tfvars

```hcl
# OCI Authentication
tenancy_ocid     = "ocid1.tenancy.oc1..aaaaa..."
user_ocid        = "ocid1.user.oc1..aaaaa..."
fingerprint      = "aa:bb:cc:dd:ee:ff:00:11:22:33:44:55:66:77:88:99"
private_key_path = "~/.oci/oci_api_key.pem"
region           = "us-ashburn-1"
compartment_ocid = "ocid1.compartment.oc1..aaaaa..."

# Elasticsearch Configuration
elasticsearch_version = "8"  # Choose "7" or "8"
master_node_count     = 3    # Must be odd number
data_node_count       = 3    # Any number >= 1
```

### 3. Deploy

```bash
terraform init
terraform plan
terraform apply
```

Deployment takes approximately 10-15 minutes.

### 4. Access Your Cluster

After deployment completes, Terraform will output:

```
Outputs:

elasticsearch_url = "http://xxx.xxx.xxx.xxx:9200"
kibana_url = "http://xxx.xxx.xxx.xxx:5601"
bastion_public_ip = "xxx.xxx.xxx.xxx"
elastic_password = <sensitive>
kibana_password = <sensitive>
```

**Important**: Authentication is enabled by default. The `elastic` and `kibana_system` user passwords are automatically generated during deployment.

**Check Cluster Health:**
```bash
# Get the password from Terraform output
terraform output elastic_password

# Use it to check cluster health
curl -u elastic:<password> http://<load-balancer-ip>:9200/_cluster/health?pretty
```

**Access Kibana:**
1. Open your browser to: `http://<load-balancer-ip>:5601`
2. Login with username `elastic` and the password from `terraform output elastic_password`

## Configuration Options

### Elasticsearch Version

Choose between Elasticsearch 7.x or 8.x:

```hcl
elasticsearch_version = "8"  # or "7"
```

### Node Configuration

```hcl
# Master nodes (must be odd number for quorum)
master_node_count     = 3
master_node_ocpus     = 2
master_node_memory_gb = 16

# Data nodes
data_node_count     = 3
data_node_ocpus     = 4
data_node_memory_gb = 32
```

### Storage

```hcl
boot_volume_size_gb = 100  # OS disk
data_volume_size_gb = 500  # Data disk for each data node
```

### Network

```hcl
vcn_cidr             = "10.0.0.0/16"
bastion_subnet_cidr  = "10.0.1.0/24"
lb_subnet_cidr       = "10.0.2.0/24"
private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]
```

## SSH Access

### Access Bastion Host

```bash
ssh -i <your-private-key> opc@<bastion-public-ip>
```

### Access Elasticsearch Nodes

From your local machine (via bastion):
```bash
ssh -i <your-private-key> -J opc@<bastion-ip> opc@<node-private-ip>
```

Or from the bastion host:
```bash
ssh opc@<node-private-ip>
```

## File Structure

```
.
├── README.md                    # This file
├── versions.tf                  # Terraform and provider versions
├── provider.tf                  # OCI provider configuration
├── variables.tf                 # Input variables
├── terraform.tfvars.example     # Example variables file
├── locals.tf                    # Local values and calculations
├── datasources.tf               # Data sources
├── ssh.tf                       # SSH key generation
├── network.tf                   # VCN, subnets, gateways, route tables
├── nsg.tf                       # Network Security Groups and rules
├── compute.tf                   # Compute instances (bastion, master, data nodes)
├── storage.tf                   # Block volumes and attachments
├── loadbalancer.tf              # Load balancer configuration
├── configure_cluster.tf         # Post-deployment cluster configuration
├── outputs.tf                   # Output values
└── scripts/
    ├── master_node_init.sh      # Master node bootstrap script
    └── data_node_init.sh        # Data node bootstrap script
```

## Architecture Details

### Network Architecture

- **VCN**: Single VCN with multiple subnets
- **Public Subnets**: Bastion and Load Balancer
- **Private Subnets**: Elasticsearch nodes (one per AD)
- **Internet Gateway**: For public subnet internet access
- **NAT Gateway**: For private subnet outbound access
- **Service Gateway**: For OCI services access

### Security

- **Network Security Groups (NSGs)**: Modern security approach
  - Bastion NSG: SSH from internet
  - Load Balancer NSG: HTTP/HTTPS from internet
  - Elasticsearch NSG: Cluster communication and LB access
- **No Public IPs**: Elasticsearch nodes are private
- **Bastion Host**: Single point of SSH access

### High Availability

- **Multi-AD Deployment**: Nodes distributed across availability domains
- **Load Balancer**: Health checks and automatic failover
- **Quorum-based**: Odd number of master nodes for split-brain prevention

## Elasticsearch Configuration

### Master Nodes

- **Roles**: `master`, `data`, `ingest`
- **Kibana**: Installed on all master nodes
- **JVM Heap**: 50% of memory (max 31GB per ES best practices)
- **Storage**: Boot volume only (no data storage)

### Data Nodes

- **Roles**: `data`, `ingest`
- **JVM Heap**: 50% of memory (max 31GB per ES best practices)
- **Storage**: Boot volume + dedicated block volume for data
- **Block Volume**: Automatically formatted, mounted at `/elasticsearch`

### Ports

- **9200**: Elasticsearch HTTP API
- **9300**: Elasticsearch transport (cluster communication)
- **5601**: Kibana

## Troubleshooting

### Check Elasticsearch Status

SSH to a node and run:
```bash
sudo systemctl status elasticsearch
sudo journalctl -u elasticsearch -f
```

### Check Cluster Health

```bash
# Get the elastic password
terraform output elastic_password

# Check cluster health (from bastion or master node)
curl -u elastic:<password> localhost:9200/_cluster/health?pretty
curl -u elastic:<password> localhost:9200/_cat/nodes?v
```

### Check Kibana Status

```bash
sudo systemctl status kibana
sudo journalctl -u kibana -f
```

### View Logs

```bash
# Elasticsearch logs
sudo tail -f /elasticsearch/logs/<cluster-name>.log

# Kibana logs
sudo journalctl -u kibana -f
```

### Common Issues

1. **Cluster not forming**: Check that all nodes can communicate on port 9300
2. **Kibana not accessible**: Ensure Elasticsearch is running first
3. **Out of memory**: Increase node memory or reduce heap size
4. **Disk full**: Increase data volume size

## Scaling

### Add More Data Nodes

```hcl
data_node_count = 5  # Increase from 3 to 5
```

Then run:
```bash
terraform apply
```

### Add More Master Nodes

```hcl
master_node_count = 5  # Must be odd number
```

Then run:
```bash
terraform apply
```

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

**Warning**: This will delete all data. Make sure to backup any important data first.

## Cost Optimization

- Use smaller shapes for testing: `VM.Standard.E4.Flex` with 1-2 OCPUs
- Reduce data volume size for non-production
- Use fewer nodes for development (1 master, 1 data)
- Stop instances when not in use (data persists on block volumes)

## Production Recommendations

1. **Backup Strategy**: Implement snapshot/restore to OCI Object Storage
2. **Monitoring**: Set up monitoring with OCI Monitoring or Elastic Stack
3. **Alerting**: Configure alerts for cluster health, disk space, memory
4. **Index Lifecycle Management**: Configure ILM policies
5. **Resource Limits**: Set appropriate shard limits and index settings
6. **Change Default Passwords**: After deployment, change the auto-generated passwords to your own secure passwords

## Support

For issues or questions:
- Check Elasticsearch documentation: https://www.elastic.co/guide/
- OCI Documentation: https://docs.oracle.com/en-us/iaas/
- Terraform OCI Provider: https://registry.terraform.io/providers/oracle/oci/

