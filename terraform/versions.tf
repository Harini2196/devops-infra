terraform {
  required_version = ">= 1.10.0"

  # Remote state (required for CI/CD). Values are supplied at init time:
  #   terraform init -backend-config=backend.hcl
  # or, in GitHub Actions, via -backend-config flags from repository variables.
  backend "s3" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.common_tags
  }
}
