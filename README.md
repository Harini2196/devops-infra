# Netflix DevSecOps – Jenkins / SonarQube / Trivy infrastructure

```
terraform/
  versions.tf        provider + version pins
  variables.tf       all inputs
  terraform.tfvars   your values (edit this)
  main.tf            default VPC lookup, SG, 3x EC2, Ansible provisioning, Route 53
  outputs.tf         IPs, DNS names, URLs, SSH commands
ansible/
  jenkins.yml        Jenkins LTS + Java 21          -> port 8080
  sonarqube.yml      SonarQube 10.6 + PostgreSQL    -> port 8080
  trivy.yml          Trivy in server mode           -> port 8080
```

## What gets created

| Instance (Name tag) | Playbook      | DNS (A record)                            |
|---------------------|---------------|-------------------------------------------|
| jenkins-master      | jenkins.yml   | jenkins-master.theautomationlab.click     |
| sonarqube-server    | sonarqube.yml | sonarqube-server.theautomationlab.click   |
| trivy-server        | trivy.yml     | trivy-server.theautomationlab.click       |

- 3 × `t2.large`, latest RHEL 9 AMI (Red Hat official), default VPC, 30 GiB gp3, IMDSv2.
- One security group: 80 and 8080 from `0.0.0.0/0`; 22 from `ssh_allowed_cidrs` (the provisioners need SSH).
- A records in hosted zone `Z0355223311NIY67H6DHL`.

## How the playbook switch works

The `servers` map in `terraform.tfvars` is the single source of truth:

```hcl
servers = {
  "jenkins-master"   = { playbook = "jenkins.yml" }
  "sonarqube-server" = { playbook = "sonarqube.yml" }
  "trivy-server"     = { playbook = "trivy.yml" }
}
```

`aws_instance.server`, `terraform_data.configure` and `aws_route53_record.server` all use
`for_each = var.servers`. Inside the provisioner block the file is picked per server via
`local.playbook_for[each.key]` / `each.value.playbook`, so each instance gets only its own
playbook. To add a server or swap a playbook, edit the map – no code changes.

The playbook is copied to the instance and run there with `-c local`. This means you do
**not** need Ansible on your workstation (Ansible can't run as a control node on Windows).
Editing a playbook changes its hash, so the next `terraform apply` re-runs only that server's
configuration without recreating the instance.

## Usage

1. Edit `terraform/terraform.tfvars`:
   - `key_name` – an existing EC2 key pair in the region
   - `private_key_path` – the matching `.pem` on your machine (use forward slashes on Windows)
   - `ssh_allowed_cidrs` – ideally your IP, e.g. `["203.0.113.10/32"]`
2. Run:
   ```bash
   cd terraform
   terraform init
   terraform plan
   terraform apply
   ```
   AWS credentials come from your normal AWS CLI profile / environment variables.
3. Open:
   - Jenkins:   http://jenkins-master.theautomationlab.click:8080 (initial admin password is printed in the apply output, or `sudo cat /var/lib/jenkins/secrets/initialAdminPassword`)
   - SonarQube: http://sonarqube-server.theautomationlab.click:8080 (admin / admin, change on first login)
   - Trivy:     from Jenkins, `trivy image --server http://trivy-server.theautomationlab.click:8080 <image>`

## Notes

- Change `sonar_db_password` in `ansible/sonarqube.yml` (or move it to Ansible Vault).
- Public IPs change if an instance is stopped/started; the A records update on the next `terraform apply`.
  Add an `aws_eip` per instance if you need fixed IPs.
- For CentOS Stream 9 instead of RHEL, swap the `ami_owner` / `ami_name_filter` values commented in `terraform.tfvars`.
- `terraform destroy` removes everything, including the DNS records.

## CI/CD (GitHub Actions)

Workflow: `.github/workflows/terraform.yml`

| Trigger | Jobs that run |
|---|---|
| Pull request to `main` | Validate & Plan (Ansible syntax check, `fmt`, `validate`, `plan`) |
| Push to `main` (terraform/ansible changes) | Validate & Plan → **Apply** |
| Run workflow → `plan` | Validate & Plan |
| Run workflow → `apply` | Validate & Plan → **Apply** |
| Run workflow → `destroy` + type `destroy` in the confirm box | **Destroy** only |

The apply job allows the runner's own IP on port 22 for that run, so the Ansible
provisioners can SSH in even when `ssh_allowed_cidrs` is restricted to your IP.

### One-time setup

1. **S3 bucket for state** (versioning on), e.g.
   `aws s3api create-bucket --bucket <name> --region us-east-1` and
   `aws s3api put-bucket-versioning --bucket <name> --versioning-configuration Status=Enabled`
2. **Repository → Settings → Secrets and variables → Actions**

   | Type | Name | Value |
   |---|---|---|
   | Secret | `EC2_SSH_PRIVATE_KEY` | full contents of `Linux_key.pem` |
   | Secret | `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | only if not using OIDC |
   | Variable | `AWS_ROLE_ARN` | IAM role for GitHub OIDC (recommended; leave unset to use access keys) |
   | Variable | `TF_STATE_BUCKET` | the bucket from step 1 |
   | Variable | `TF_STATE_KEY` | optional, default `netflix-devsecops/terraform.tfstate` |
   | Variable | `AWS_REGION` | optional, default `us-east-1` |

3. **Settings → Environments**: create `production` and `destroy`. Add yourself as a
   *required reviewer* on `destroy` (and on `production` if you want to approve every apply).

### Local runs now need the backend

```bash
cp backend.hcl.example backend.hcl   # fill in the same bucket as CI
terraform init -backend-config=backend.hcl
```
If you already applied locally with local state, run `terraform init -migrate-state -backend-config=backend.hcl` once to move it to S3.
