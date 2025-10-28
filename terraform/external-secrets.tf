# External Secrets Operator for AWS Parameter Store integration
# This allows Kubernetes applications to securely access secrets from AWS SSM Parameter Store

# Install External Secrets Operator using Helm
resource "helm_release" "external_secrets" {
  depends_on = [null_resource.fetch_kubeconfig]

  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = "0.12.1"
  namespace        = "external-secrets"
  create_namespace = true

  values = [
    <<-EOT
    installCRDs: true

    # Enable Prometheus monitoring if you have monitoring stack
    serviceMonitor:
      enabled: true

    # Use server-side apply for CRDs (required for large CRDs)
    crds:
      createClusterExternalSecret: true
      createClusterSecretStore: true

    webhook:
      create: true

    certController:
      create: true
    EOT
  ]

  timeout = 600
}

# Wait for External Secrets CRDs to be registered
# The Helm chart installation completes before CRDs are fully available in the API server
resource "time_sleep" "wait_for_external_secrets_crds" {
  depends_on = [helm_release.external_secrets]

  create_duration = "30s"
}

# Create AWS IAM User for External Secrets (if using static credentials)
# Note: For production, consider using IRSA (IAM Roles for Service Accounts) instead
resource "aws_iam_user" "external_secrets" {
  name = "external-secrets-k8s-${var.server_name}"
  path = "/k8s/"

  tags = {
    Name        = "External Secrets K8s User"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

# Create access key for the IAM user
resource "aws_iam_access_key" "external_secrets" {
  user = aws_iam_user.external_secrets.name
}

# IAM Policy for Parameter Store access
resource "aws_iam_policy" "external_secrets_parameter_store" {
  name        = "external-secrets-parameter-store-${var.server_name}"
  path        = "/k8s/"
  description = "Policy for External Secrets Operator to access AWS Parameter Store"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath",
          "ssm:GetParameterHistory"
        ]
        Resource = [
          "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/${var.parameter_store_prefix}*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:DescribeParameters"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = [
          "arn:aws:kms:${var.aws_region}:${data.aws_caller_identity.current.account_id}:key/*"
        ]
        Condition = {
          StringEquals = {
            "kms:ViaService" = "ssm.${var.aws_region}.amazonaws.com"
          }
        }
      }
    ]
  })
}

# Attach policy to IAM user
resource "aws_iam_user_policy_attachment" "external_secrets" {
  user       = aws_iam_user.external_secrets.name
  policy_arn = aws_iam_policy.external_secrets_parameter_store.arn
}

# Get current AWS account ID
data "aws_caller_identity" "current" {}

# Create Kubernetes secret with AWS credentials
resource "kubectl_manifest" "aws_credentials_secret" {
  depends_on = [
    time_sleep.wait_for_external_secrets_crds,
    aws_iam_access_key.external_secrets
  ]

  yaml_body = <<-YAML
    apiVersion: v1
    kind: Secret
    metadata:
      name: aws-credentials
      namespace: external-secrets
    type: Opaque
    stringData:
      access-key-id: ${aws_iam_access_key.external_secrets.id}
      secret-access-key: ${aws_iam_access_key.external_secrets.secret}
  YAML

  sensitive_fields = [
    "data.access-key-id",
    "data.secret-access-key"
  ]
}

# Create ClusterSecretStore for AWS Parameter Store
# This can be used by any namespace in the cluster
resource "kubectl_manifest" "cluster_secret_store" {
  depends_on = [
    time_sleep.wait_for_external_secrets_crds,
    kubectl_manifest.aws_credentials_secret
  ]

  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1beta1
    kind: ClusterSecretStore
    metadata:
      name: aws-parameter-store
    spec:
      provider:
        aws:
          service: ParameterStore
          region: ${var.aws_region}
          auth:
            secretRef:
              accessKeyID:
                name: aws-credentials
                namespace: external-secrets
                key: access-key-id
              secretAccessKey:
                name: aws-credentials
                namespace: external-secrets
                key: secret-access-key
  YAML
}

# Example: Create a namespace-scoped SecretStore (optional)
# This is useful if you want different credentials per namespace
resource "kubectl_manifest" "secret_store_example" {
  depends_on = [
    time_sleep.wait_for_external_secrets_crds,
    kubectl_manifest.aws_credentials_secret
  ]

  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1beta1
    kind: SecretStore
    metadata:
      name: aws-parameter-store
      namespace: default
    spec:
      provider:
        aws:
          service: ParameterStore
          region: ${var.aws_region}
          auth:
            secretRef:
              accessKeyID:
                name: aws-credentials
                namespace: external-secrets
                key: access-key-id
              secretAccessKey:
                name: aws-credentials
                namespace: external-secrets
                key: secret-access-key
  YAML
}

# Example ExternalSecret: Fetch a secret from Parameter Store
# This creates a Kubernetes Secret from AWS Parameter Store parameter
# resource "kubectl_manifest" "external_secret_example" {
#   depends_on = [kubectl_manifest.cluster_secret_store]

#   yaml_body = <<-YAML
#     apiVersion: external-secrets.io/v1beta1
#     kind: ExternalSecret
#     metadata:
#       name: example-secret
#       namespace: default
#     spec:
#       refreshInterval: 1h
#       secretStoreRef:
#         name: aws-parameter-store
#         kind: ClusterSecretStore
#       target:
#         name: example-secret
#         creationPolicy: Owner
#         deletionPolicy: Retain
#       data:
#         # Example: Fetch a single parameter
#         - secretKey: database-password
#           remoteRef:
#             key: /${var.parameter_store_prefix}/database/password

#         # Example: Fetch parameter with specific version
#         # - secretKey: api-key
#         #   remoteRef:
#         #     key: /${var.parameter_store_prefix}/api/key
#         #     version: "1"
#   YAML
# }

# Output useful information
output "external_secrets_info" {
  description = "External Secrets Operator configuration information"
  value       = <<-EOT
    External Secrets Operator installed successfully!

    Configuration:
    - Namespace: external-secrets
    - ClusterSecretStore: aws-parameter-store
    - AWS Region: ${var.aws_region}
    - Parameter Store Prefix: /${var.parameter_store_prefix}

    IAM User: ${aws_iam_user.external_secrets.name}
    IAM Policy: ${aws_iam_policy.external_secrets_parameter_store.name}

    To create secrets in your applications:

    1. Store secrets in AWS Parameter Store:
       aws ssm put-parameter \
         --name "/${var.parameter_store_prefix}/my-app/database-password" \
         --value "my-secret-password" \
         --type "SecureString" \
         --region ${var.aws_region}

    2. Create an ExternalSecret in your namespace:
       apiVersion: external-secrets.io/v1
       kind: ExternalSecret
       metadata:
         name: my-app-secret
         namespace: my-namespace
       spec:
         refreshInterval: 1h
         secretStoreRef:
           name: aws-parameter-store
           kind: ClusterSecretStore
         target:
           name: my-app-secret
         data:
           - secretKey: db-password
             remoteRef:
               key: /${var.parameter_store_prefix}/my-app/database-password

    3. Use the secret in your Helm deployment:
       env:
         - name: DB_PASSWORD
           valueFrom:
             secretKeyRef:
               name: my-app-secret
               key: db-password

    Check operator status:
    kubectl get pods -n external-secrets
    kubectl get clustersecretstores
    kubectl get externalsecrets -A
  EOT
}

output "aws_iam_user_name" {
  description = "IAM user created for External Secrets"
  value       = aws_iam_user.external_secrets.name
}

output "aws_iam_user_arn" {
  description = "ARN of the IAM user"
  value       = aws_iam_user.external_secrets.arn
}
