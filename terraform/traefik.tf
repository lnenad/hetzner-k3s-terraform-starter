# Traefik Dashboard Access Configuration
# K3s deploys Traefik by default but without the dashboard enabled
# We'll enable it using a HelmChartConfig overlay and expose it properly

resource "kubectl_manifest" "traefik_config" {
  depends_on = [null_resource.fetch_kubeconfig]

  yaml_body = <<-YAML
    apiVersion: helm.cattle.io/v1
    kind: HelmChartConfig
    metadata:
      name: traefik
      namespace: kube-system
    spec:
      valuesContent: |-
        deployment:
          kind: Deployment
        ports:
          web:
            hostPort: 80
          websecure:
            hostPort: 443
        service:
          type: ClusterIP
        additionalArguments:
          - "--api.dashboard=true"
          - "--api.insecure=true"
          - "--certificatesresolvers.letsencrypt.acme.email=${var.letsencrypt_email}"
          - "--certificatesresolvers.letsencrypt.acme.storage=/data/acme.json"
          - "--certificatesresolvers.letsencrypt.acme.tlschallenge=true"
        logs:
          access:
            enabled: true
        persistence:
          enabled: true
          name: traefik-certs
          size: 128Mi
          path: /data
  YAML
}

# Wait for Traefik to be reconfigured
resource "time_sleep" "wait_for_traefik" {
  depends_on = [kubectl_manifest.traefik_config]

  create_duration = "60s"
}

# Create a service to access Traefik's web port (includes dashboard)
resource "kubectl_manifest" "traefik_web_service" {
  depends_on = [kubectl_manifest.traefik_config]

  yaml_body = <<-YAML
    apiVersion: v1
    kind: Service
    metadata:
      name: traefik-web
      namespace: kube-system
    spec:
      type: ClusterIP
      selector:
        app.kubernetes.io/name: traefik
        app.kubernetes.io/instance: traefik-kube-system
      ports:
      - name: web
        port: 9000
        targetPort: 9000
        protocol: TCP
  YAML
}

output "traefik_dashboard_info" {
  description = "Traefik dashboard access information"
  value       = <<-EOT
    Traefik Dashboard Access:

    kubectl port-forward -n kube-system svc/traefik-web 9000:9000

    Then open: http://localhost:9000/dashboard/

    Traefik is accessible on the server IP on ports 80 and 443 (via hostPort).

    Example: http://${hcloud_primary_ip.k3s_node_public_ip.ip_address}/
  EOT
}
