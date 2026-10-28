aws_region    = "ap-southeast-2"
instance_type = "t2.large"

# RHEL 9 (Red Hat official AMIs). For CentOS Stream 9 instead use:
#   ami_owner       = "125523088429"
#   ami_name_filter = "CentOS Stream 9 x86_64*"
#   ssh_user        = "ec2-user"
ami_owner       = "309956199498"
ami_name_filter = "RHEL-9.*_HVM-*-x86_64-*"
ssh_user        = "ec2-user"

# Existing key pair in the region + matching private key on this machine
key_name         = "Linux_key"
private_key_path = "Linux_key.pem"

root_volume_size = 30

# Open to 0.0.0.0/0
public_ingress_ports = [80, 8080]

# SSH is needed by the provisioners - restrict to your public IP (x.x.x.x/32)
ssh_allowed_cidrs = ["0.0.0.0/0"]

# Instance name => Ansible playbook that configures it
servers = {
  "jenkins-master"   = { playbook = "jenkins.yml" }
  "sonarqube-server" = { playbook = "sonarqube.yml" }
  "trivy-server"     = { playbook = "trivy.yml" }
}

# Route 53
hosted_zone_id = "Z0316863GCDGLHHVF5PT"
domain_name    = "theautomationlab.cloud"
dns_ttl        = 300

common_tags = {
  Project   = "Netflix-DevSecOps"
  ManagedBy = "Terraform"
}
