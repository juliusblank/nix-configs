terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.100.0"
    }
    github = {
      source  = "integrations/github"
      version = "= 6.11.1"
    }
  }

  # S3 backend — bucket created by `just setup-terraform-backend`
  backend "s3" {
    bucket         = "juliusblank-terraform-state"
    key            = "nix-configs/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "juliusblank-terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  # Explicit: never use default profile
  # AWS_PROFILE=personal is set by the devShell and justfile
}

provider "github" {
  owner = var.github_owner
  # Uses var.github_token (TF_VAR_github_token) rather than GITHUB_TOKEN to avoid
  # collision with the ephemeral Actions token GitHub injects automatically in CI.
  token = var.github_token
}
