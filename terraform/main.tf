############################################
# Lookups: default VPC, subnets, RHEL AMI
############################################

data "aws_vpc" "default" {
  default = true
}

# Only use AZs where the chosen instance type is offered
# (t2.* is not available in every AZ, e.g. us-east-1e).
data "aws_ec2_instance_type_offerings" "supported" {
  location_type = "availability-zone"

  filter {
    name   = "instance-type"
    values = [var.instance_type]
  }
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name   = "default-for-az"
    values = ["true"]
  }

  filter {
    name   = "availability-zone"
    values = data.aws_ec2_instance_type_offerings.supported.locations
  }
}

data "aws_ami" "rhel" {
  most_recent = true
  owners      = [var.ami_owner]

  filter {
    name   = "name"
    values = [var.ami_name_filter]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  subnet_ids   = sort(data.aws_subnets.default.ids)
  server_names = sort(keys(var.servers))

  # Spread servers across the supported default subnets
  server_subnet = {
    for idx, name in local.server_names :
    name => local.subnet_ids[idx % length(local.subnet_ids)]
  }

  # Playbook switch: each server resolves to its own Ansible file
  playbook_for = {
    for name, cfg in var.servers :
    name => "${path.module}/../ansible/${cfg.playbook}"
  }
}

############################################
# Security group
############################################

resource "aws_security_group" "devsecops" {
  name        = "devsecops-tools-sg"
  description = "Jenkins / SonarQube / Trivy servers"
  vpc_id      = data.aws_vpc.default.id

  dynamic "ingress" {
    for_each = toset(var.public_ingress_ports)
    content {
      description = "Public TCP ${ingress.value}"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  ingress {
    description = "SSH for provisioning/admin"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = distinct(concat(var.ssh_allowed_cidrs, var.extra_ssh_cidrs))
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "devsecops-tools-sg"
  }
}

############################################
# EC2 instances
############################################

resource "aws_instance" "server" {
  for_each = var.servers

  ami                         = data.aws_ami.rhel.id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = local.server_subnet[each.key]
  vpc_security_group_ids      = [aws_security_group.devsecops.id]
  associate_public_ip_address = true

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  metadata_options {
    http_tokens = "required" # IMDSv2 only
  }

  tags = {
    Name = each.key
    Role = trimsuffix(each.value.playbook, ".yml")
  }

  # The AMI lookup is "most_recent"; without this every new RHEL release
  # would make a pipeline run destroy and rebuild the servers.
  lifecycle {
    ignore_changes = [ami]
  }
}

############################################
# Configuration with Ansible
#
# The playbook is copied to each server and run there against localhost.
# This works from any workstation (including Windows, where Ansible can't
# run as a control node). The playbook file is chosen per server from
# var.servers[*].playbook, and editing a playbook re-runs only that server.
############################################

resource "terraform_data" "configure" {
  for_each = var.servers

  triggers_replace = {
    instance_id   = aws_instance.server[each.key].id
    playbook_hash = filesha256(local.playbook_for[each.key])
  }

  connection {
    type        = "ssh"
    host        = aws_instance.server[each.key].public_ip
    user        = var.ssh_user
    private_key = file(var.private_key_path)
    timeout     = "10m"
  }

  # Wait for cloud-init, then install Ansible on the node
  provisioner "remote-exec" {
    inline = [
      "sudo cloud-init status --wait > /dev/null 2>&1 || true",
      "sudo dnf install -y ansible-core",
      "mkdir -p /tmp/ansible",
    ]
  }

  # Copy the playbook selected for THIS server
  provisioner "file" {
    source      = local.playbook_for[each.key]
    destination = "/tmp/ansible/${each.value.playbook}"
  }

  # Run it
  provisioner "remote-exec" {
    inline = [
      "sudo ansible-playbook -i 'localhost,' -c local /tmp/ansible/${each.value.playbook}",
    ]
  }
}

############################################
# Route 53 A records
############################################

resource "aws_route53_record" "server" {
  for_each = var.servers

  zone_id = var.hosted_zone_id
  name    = "${each.key}.${var.domain_name}"
  type    = "A"
  ttl     = var.dns_ttl
  records = [aws_instance.server[each.key].public_ip]
}
