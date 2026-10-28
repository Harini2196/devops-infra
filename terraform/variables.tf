variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for all servers"
  type        = string
  default     = "t2.large"
}

variable "ami_name_filter" {
  description = "AMI name pattern used to look up the latest RHEL image"
  type        = string
  default     = "RHEL-9.*_HVM-*-x86_64-*"
}

variable "ami_owner" {
  description = "AWS account that publishes the AMI (309956199498 = Red Hat)"
  type        = string
  default     = "309956199498"
}

variable "ssh_user" {
  description = "Default SSH login user for the AMI (ec2-user for RHEL, centos for CentOS)"
  type        = string
  default     = "ec2-user"
}

variable "key_name" {
  description = "Name of an EXISTING EC2 key pair in the region"
  type        = string
}

variable "private_key_path" {
  description = "Local path to the private key (.pem) matching key_name, used by the provisioners"
  type        = string
}

variable "root_volume_size" {
  description = "Root EBS volume size in GiB"
  type        = number
  default     = 30
}

variable "public_ingress_ports" {
  description = "TCP ports opened to 0.0.0.0/0"
  type        = list(number)
  default     = [80, 8080]
}

variable "ssh_allowed_cidrs" {
  description = "CIDRs allowed to SSH (port 22) - required for the Terraform provisioners"
  type        = list(string)
}

variable "extra_ssh_cidrs" {
  description = "Additional SSH CIDRs, e.g. the GitHub runner's IP injected by CI"
  type        = list(string)
  default     = []
}

variable "servers" {
  description = <<-EOT
    Map of servers to create. The key becomes the instance Name tag and the DNS
    record prefix; 'playbook' is the Ansible file (in ../ansible) that configures it.
  EOT
  type = map(object({
    playbook = string
  }))
}

variable "hosted_zone_id" {
  description = "Route 53 hosted zone ID"
  type        = string
}

variable "domain_name" {
  description = "Route 53 hosted zone name"
  type        = string
}

variable "dns_ttl" {
  description = "TTL for the A records"
  type        = number
  default     = 300
}

variable "common_tags" {
  description = "Tags applied to every resource"
  type        = map(string)
  default     = {}
}
