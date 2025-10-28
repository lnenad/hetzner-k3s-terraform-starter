# Create monitoring namespace
resource "kubectl_manifest" "monitoring_namespace" {
  depends_on = [null_resource.fetch_kubeconfig]

  yaml_body = <<-YAML
    apiVersion: v1
    kind: Namespace
    metadata:
      name: monitoring
  YAML
}

# Install kube-prometheus-stack (Prometheus + Grafana + Alertmanager)
resource "helm_release" "kube_prometheus_stack" {
  depends_on = [kubectl_manifest.monitoring_namespace]

  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "55.5.0"
  namespace  = "monitoring"

  values = [
    <<-EOT
    # Prometheus configuration
    prometheus:
      prometheusSpec:
        retention: 30d
        storageSpec:
          volumeClaimTemplate:
            spec:
              storageClassName: hcloud-volumes
              accessModes: ["ReadWriteOnce"]
              resources:
                requests:
                  storage: 50Gi
        resources:
          requests:
            cpu: 500m
            memory: 2Gi
          limits:
            cpu: 2000m
            memory: 4Gi
        # Enable service monitors for K3s components
        serviceMonitorSelectorNilUsesHelmValues: false
        podMonitorSelectorNilUsesHelmValues: false

      service:
        type: ClusterIP

    # Grafana configuration
    grafana:
      enabled: true
      adminPassword: ${var.grafana_admin_password}

      persistence:
        enabled: true
        storageClassName: hcloud-volumes
        size: 10Gi

      resources:
        requests:
          cpu: 100m
          memory: 256Mi
        limits:
          cpu: 500m
          memory: 512Mi

      # Grafana ingress configuration
      ingress:
        enabled: ${var.grafana_domain != "" ? "true" : "false"}
        ingressClassName: traefik
        annotations:
          cert-manager.io/cluster-issuer: "letsencrypt-prod"
        hosts:
          - ${var.grafana_domain != "" ? var.grafana_domain : "grafana.local"}
        tls:
          - secretName: grafana-tls
            hosts:
              - ${var.grafana_domain != "" ? var.grafana_domain : "grafana.local"}

      # Additional dashboards
      dashboardProviders:
        dashboardproviders.yaml:
          apiVersion: 1
          providers:
          - name: 'default'
            orgId: 1
            folder: ''
            type: file
            disableDeletion: false
            editable: true
            options:
              path: /var/lib/grafana/dashboards/default

      dashboards:
        default:
          traefik-custom:
            json: |
              ${indent(8, file("${path.module}/grafana-traefik-dashboard.json"))}
          kubernetes-cluster:
            gnetId: 7249
            revision: 1
            datasource: Prometheus
          node-exporter:
            gnetId: 1860
            revision: 31
            datasource: Prometheus
          k3s:
            gnetId: 15282
            revision: 1
            datasource: Prometheus

    # Alertmanager configuration
    alertmanager:
      alertmanagerSpec:
        storage:
          volumeClaimTemplate:
            spec:
              storageClassName: hcloud-volumes
              accessModes: ["ReadWriteOnce"]
              resources:
                requests:
                  storage: 10Gi
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 200m
            memory: 256Mi

    # Node exporter - metrics from nodes
    nodeExporter:
      enabled: true

    # Kube-state-metrics - metrics about Kubernetes objects
    kubeStateMetrics:
      enabled: true

    # Default service monitors
    defaultRules:
      create: true
      rules:
        alertmanager: true
        etcd: true
        configReloaders: true
        general: true
        k8s: true
        kubeApiserverAvailability: true
        kubeApiserverSlos: true
        kubelet: true
        kubeProxy: true
        kubePrometheusGeneral: true
        kubePrometheusNodeRecording: true
        kubernetesApps: true
        kubernetesResources: true
        kubernetesStorage: true
        kubernetesSystem: true
        kubeScheduler: true
        kubeStateMetrics: true
        network: true
        node: true
        nodeExporterAlerting: true
        nodeExporterRecording: true
        prometheus: true
        prometheusOperator: true
    EOT
  ]

  timeout = 600
}

# Wait for Prometheus Operator CRDs to be ready
resource "time_sleep" "wait_for_crds" {
  depends_on = [helm_release.kube_prometheus_stack]

  create_duration = "30s"
}

# Create ServiceMonitor for Traefik
resource "kubectl_manifest" "traefik_metrics_service" {
  depends_on = [time_sleep.wait_for_crds]

  yaml_body = <<-YAML
    apiVersion: v1
    kind: Service
    metadata:
      name: traefik-metrics
      namespace: kube-system
      labels:
        app.kubernetes.io/name: traefik-metrics
        app.kubernetes.io/instance: traefik
    spec:
      type: ClusterIP
      ports:
      - name: metrics
        port: 9100
        targetPort: 9100
        protocol: TCP
      selector:
        app.kubernetes.io/name: traefik
        app.kubernetes.io/instance: traefik-kube-system
  YAML
}

resource "kubectl_manifest" "traefik_service_monitor" {
  depends_on = [time_sleep.wait_for_crds, kubectl_manifest.traefik_metrics_service]

  yaml_body = <<-YAML
    apiVersion: monitoring.coreos.com/v1
    kind: ServiceMonitor
    metadata:
      name: traefik
      namespace: monitoring
      labels:
        app: traefik
        release: kube-prometheus-stack
    spec:
      jobLabel: traefik
      selector:
        matchLabels:
          app.kubernetes.io/name: traefik-metrics
      namespaceSelector:
        matchNames:
        - kube-system
      endpoints:
      - port: metrics
        interval: 30s
        path: /metrics
        scheme: http
  YAML
}

# Output Grafana access information
output "grafana_info" {
  description = "Grafana access information"
  value = {
    url      = var.grafana_domain != "" ? "https://${var.grafana_domain}" : "Use kubectl port-forward: kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80"
    username = "admin"
    password = var.grafana_admin_password
  }
  sensitive = true
}
