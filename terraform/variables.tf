variable "hcloud_token" {
  description = "Hetzner Cloud API Token"
  sensitive   = true
}

variable "server_datacenter" {
  description = "Server location"
  default     = "fsn1"
}

variable "server_name" {
  description = "Name of the K3s server"
  default     = "k3s-node"
}

variable "grafana_admin_password" {
  description = "Grafana admin password"
  type        = string
  sensitive   = true
  default     = "admin"
}

variable "grafana_domain" {
  description = "Domain for Grafana (e.g., grafana.example.com). Leave empty to use port-forward"
  type        = string
  default     = ""
}

variable "letsencrypt_email" {
  description = "Email for Let's Encrypt certificate notifications"
  type        = string
  default     = "admin@example.com"
}

# AWS Variables for External Secrets
variable "aws_region" {
  description = "AWS region for Parameter Store and IAM resources"
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "AWS profile to use for authentication (optional)"
  type        = string
  default     = "default"
}

variable "parameter_store_prefix" {
  description = "Prefix for Parameter Store parameters (e.g., 'k8s/production')"
  type        = string
  default     = "k8s/production"
}
