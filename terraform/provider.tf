terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "1.45.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

# Configure the Hetzner Cloud Provider with your token
provider "hcloud" {
  token = var.hcloud_token
}

# Configure Helm provider to use the K3s kubeconfig file
provider "helm" {
  kubernetes {
    config_path = "${path.module}/k3s.yaml"
  }
}

# Configure kubectl provider to use the K3s kubeconfig file
provider "kubectl" {
  config_path = "${path.module}/k3s.yaml"
}

# Configure AWS provider for External Secrets
provider "aws" {
  region = var.aws_region
  # If you want to use a specific AWS profile, uncomment below:
  # profile = var.aws_profile
}
