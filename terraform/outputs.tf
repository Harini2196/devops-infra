output "ami_used" {
  value = "${data.aws_ami.rhel.name} (${data.aws_ami.rhel.id})"
}

output "public_ips" {
  value = { for name, inst in aws_instance.server : name => inst.public_ip }
}

output "dns_names" {
  value = { for name, rec in aws_route53_record.server : name => rec.fqdn }
}

output "urls" {
  value = {
    for name, rec in aws_route53_record.server : name => "http://${rec.fqdn}:8080"
  }
}

output "ssh_commands" {
  value = {
    for name, inst in aws_instance.server :
    name => "ssh -i ${var.private_key_path} ${var.ssh_user}@${inst.public_ip}"
  }
}
