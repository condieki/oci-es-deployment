
variable "tenancy_ocid" {
  description = "The OCID of the tenancy"
  type        = string
}

variable "user_ocid" {
  description = "The OCID of the user"
  type        = string
}

variable "fingerprint" {
  description = "The fingerprint of the API key"
  type        = string
}

variable "private_key_path" {
  description = "The path to the private key file"
  type        = string
}

variable "region" {
  description = "The OCI region"
  type        = string
}

variable "compartment_ocid" {
  description = "The OCID of the compartment where resources will be created"
  type        = string
}

# Elasticsearch Configuration
variable "elasticsearch_version" {
  description = "Elasticsearch version to install (7 or 8)"
  type        = string
  default     = "8"
  validation {
    condition     = contains(["7", "8"], var.elasticsearch_version)
    error_message = "Elasticsearch version must be either 7 or 8"
  }
}

variable "elasticsearch_cluster_name" {
  description = "Name of the Elasticsearch cluster"
  type        = string
  default     = "oci-es-cluster"
}

# Node Configuration
variable "master_node_count" {
  description = "Number of Elasticsearch master nodes (must be odd number, recommended 3)"
  type        = number
  default     = 3
  validation {
    condition     = var.master_node_count % 2 == 1 && var.master_node_count >= 1
    error_message = "Master node count must be an odd number (1, 3, 5, etc.) for quorum"
  }
}

variable "data_node_count" {
  description = "Number of Elasticsearch data nodes"
  type        = number
  default     = 3
  validation {
    condition     = var.data_node_count >= 1
    error_message = "Must have at least 1 data node"
  }
}

# Compute Shapes
variable "bastion_shape" {
  description = "Shape for bastion host"
  type        = string
  default     = "VM.Standard.E4.Flex"
}

variable "bastion_ocpus" {
  description = "Number of OCPUs for bastion host"
  type        = number
  default     = 1
}

variable "bastion_memory_gb" {
  description = "Amount of memory in GB for bastion host"
  type        = number
  default     = 4
}

variable "master_node_shape" {
  description = "Shape for Elasticsearch master nodes"
  type        = string
  default     = "VM.Standard.E4.Flex"
}

variable "master_node_ocpus" {
  description = "Number of OCPUs for master nodes"
  type        = number
  default     = 2
}

variable "master_node_memory_gb" {
  description = "Amount of memory in GB for master nodes"
  type        = number
  default     = 16
}

variable "data_node_shape" {
  description = "Shape for Elasticsearch data nodes"
  type        = string
  default     = "VM.Standard.E4.Flex"
}

variable "data_node_ocpus" {
  description = "Number of OCPUs for data nodes"
  type        = number
  default     = 4
}

variable "data_node_memory_gb" {
  description = "Amount of memory in GB for data nodes"
  type        = number
  default     = 32
}

# Storage Configuration
variable "boot_volume_size_gb" {
  description = "Size of boot volume in GB"
  type        = number
  default     = 100
}

variable "data_volume_size_gb" {
  description = "Size of data block volume in GB for data nodes"
  type        = number
  default     = 500
}

# Network Configuration
variable "vcn_cidr" {
  description = "CIDR block for VCN"
  type        = string
  default     = "10.0.0.0/16"
}

variable "bastion_subnet_cidr" {
  description = "CIDR block for bastion subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "lb_subnet_cidr" {
  description = "CIDR block for load balancer subnet"
  type        = string
  default     = "10.0.2.0/24"
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AD)"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]
}

# Load Balancer Configuration
variable "lb_shape" {
  description = "Shape for load balancer"
  type        = string
  default     = "flexible"
}

variable "lb_min_bandwidth_mbps" {
  description = "Minimum bandwidth for flexible load balancer"
  type        = number
  default     = 10
}

variable "lb_max_bandwidth_mbps" {
  description = "Maximum bandwidth for flexible load balancer"
  type        = number
  default     = 100
}

# Elasticsearch Ports
variable "elasticsearch_port" {
  description = "Elasticsearch HTTP port"
  type        = number
  default     = 9200
}

variable "elasticsearch_transport_port" {
  description = "Elasticsearch transport port"
  type        = number
  default     = 9300
}

variable "kibana_port" {
  description = "Kibana port"
  type        = number
  default     = 5601
}

# SSH Configuration
variable "ssh_public_key" {
  description = "SSH public key for instance access (optional, will generate if not provided)"
  type        = string
  default     = ""
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key for provisioners (required if ssh_public_key is provided)"
  type        = string
  default     = ""
}

# Operating System
variable "instance_os" {
  description = "Operating system for compute instances"
  type        = string
  default     = "Oracle Linux"
}

variable "linux_os_version" {
  description = "Operating system version"
  type        = string
  default     = "9"
}

# Tags
variable "project_tag" {
  description = "Project tag for resources"
  type        = string
  default     = "elasticsearch-cluster"
}

# OCI Object Storage for Snapshots (Optional)
variable "oci_object_storage_access_key" {
  description = "OCI Object Storage access key for snapshots (optional - leave empty to configure manually later)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "oci_object_storage_secret_key" {
  description = "OCI Object Storage secret key for snapshots (optional - leave empty to configure manually later)"
  type        = string
  default     = ""
  sensitive   = true
}
