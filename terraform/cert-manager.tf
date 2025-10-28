# Install cert-manager for automatic TLS certificates
resource "helm_release" "cert_manager" {
  depends_on = [null_resource.fetch_kubeconfig]

  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = "v1.14.0"
  namespace        = "cert-manager"
  create_namespace = true

  values = [
    <<-EOT
    installCRDs: true
    prometheus:
      enabled: true
      servicemonitor:
        enabled: true
    EOT
  ]

  timeout = 600
}

# Create Let's Encrypt ClusterIssuer for production
resource "kubectl_manifest" "letsencrypt_prod" {
  depends_on = [helm_release.cert_manager]

  yaml_body = <<-YAML
    apiVersion: cert-manager.io/v1
    kind: ClusterIssuer
    metadata:
      name: letsencrypt-prod
    spec:
      acme:
        server: https://acme-v02.api.letsencrypt.org/directory
        email: ${var.letsencrypt_email}
        privateKeySecretRef:
          name: letsencrypt-prod-key
        solvers:
        - http01:
            ingress:
              class: traefik
  YAML
}

# Create Let's Encrypt ClusterIssuer for staging (testing)
resource "kubectl_manifest" "letsencrypt_staging" {
  depends_on = [helm_release.cert_manager]

  yaml_body = <<-YAML
    apiVersion: cert-manager.io/v1
    kind: ClusterIssuer
    metadata:
      name: letsencrypt-staging
    spec:
      acme:
        server: https://acme-staging-v02.api.letsencrypt.org/directory
        email: ${var.letsencrypt_email}
        privateKeySecretRef:
          name: letsencrypt-staging-key
        solvers:
        - http01:
            ingress:
              class: traefik
  YAML
}
