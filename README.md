# K3s Single Node Setup on Hetzner with CPX42 + Monitoring

This Terraform configuration sets up a single-node K3s Kubernetes cluster on Hetzner Cloud using the CPX42 server type, with complete monitoring via Prometheus and Grafana.

## Server Specifications (CPX42)
- **CPUs**: 16 vCPU (AMD)
- **RAM**: 32 GB
- **Storage**: 240 GB NVMe
- **Network**: 20 TB traffic

## Installed Components

### Core Infrastructure
- **K3s**: Lightweight Kubernetes distribution (with Traefik ingress enabled)
- **Hetzner Cloud Controller Manager**: Manages Hetzner-specific resources
- **Hetzner CSI Driver**: Provides persistent volume support using Hetzner volumes
- **Flannel**: Network plugin for pod networking

### Monitoring Stack
- **Prometheus**: Metrics collection and storage (30-day retention)
- **Grafana**: Metrics visualization and dashboards
- **Alertmanager**: Alert management and notifications
- **Node Exporter**: Host metrics collection
- **Kube-state-metrics**: Kubernetes object metrics
- **cert-manager**: Automatic TLS certificate management

### Secrets Management
- **External Secrets Operator**: Synchronizes secrets from AWS Parameter Store into Kubernetes Secrets
- **AWS Parameter Store Integration**: Securely manage application secrets in AWS SSM
- See [EXTERNAL_SECRETS_USAGE.md](terraform/EXTERNAL_SECRETS_USAGE.md) for detailed setup and usage guide

### Pre-configured Dashboards
1. **Traefik Dashboard** - Ingress controller metrics and traffic
2. **Kubernetes Cluster Overview** - Cluster-wide resource usage
3. **Node Exporter** - Detailed host metrics
4. **K3s Dashboard** - K3s-specific metrics

## Prerequisites

1. **Hetzner Cloud Account**: Sign up at https://www.hetzner.com/cloud
2. **Terraform**: Install from https://developer.hashicorp.com/terraform/install
3. **kubectl**: Install from https://kubernetes.io/docs/tasks/tools/
4. **SSH Key**: Your existing key at `C:\Users\nndlk\.ssh\id_ed25519`
5. **PowerShell**: For Windows automation scripts

## Setup Instructions

### 1. Create Project Directory

```powershell
mkdir k3s-hetzner
cd k3s-hetzner
```

### 2. Verify SSH Key

Ensure your public key exists:

```powershell
cat C:\Users\nndlk\.ssh\id_ed25519.pub
```

If it doesn't exist, generate it:

```powershell
ssh-keygen -t ed25519 -f C:\Users\nndlk\.ssh\id_ed25519
```

### 3. Create Hetzner Cloud API Token

1. Log in to Hetzner Cloud Console
2. Navigate to your project
3. Go to **Security** → **API Tokens**
4. Click **Generate API Token**
5. Give it a name and set **Read & Write** permissions
6. Copy the token

### 4. Create `.tfvars` File

Create a file named `primary.tfvars` (or any name you prefer) with your configuration:

```hcl
# Hetzner Cloud Configuration
hcloud_token = "YOUR_HETZNER_API_TOKEN_HERE"

# Server location and datacenter (must match)
server_location = "nbg1"
server_datacenter = "nbg1-dc3"

# Grafana Configuration
# Optional: Set a strong Grafana password
grafana_admin_password = "YourStrongPassword123!"

# Optional: Configure domain for Grafana (requires DNS setup)
# grafana_domain = "grafana.yourdomain.com"
# letsencrypt_email = "your-email@example.com"

# AWS Configuration for External Secrets (optional - only needed if using External Secrets)
aws_region = "us-east-1"
aws_profile = "default"  # or your AWS profile name
parameter_store_prefix = "k8s/production"  # Prefix for Parameter Store parameters
```

**Important**: Add `*.tfvars` to your `.gitignore` to keep your token secure!

### 5. Initialize Terraform

```powershell
terraform init
```

### 6. Review the Plan

```powershell
terraform plan --var-file=primary.tfvars
```

### 7. Apply Configuration (Two-Stage Deployment)

Due to provider initialization requirements, we deploy in two stages:

**Stage 1: Create infrastructure and fetch kubeconfig**
```powershell
terraform apply --target=hcloud_network.private_network --target=hcloud_network_subnet.private_network_subnet --target=hcloud_primary_ip.k3s_node_public_ip --target=data.template_file.k3s-node-config --target=hcloud_server.k3s-node --target=null_resource.fetch_kubeconfig --target=null_resource.wait_for_node --var-file=primary.tfvars
```

This takes about 5-7 minutes. It will:
- Create the server and network
- Install K3s
- Install Hetzner cloud controller and CSI driver
- Download the kubeconfig file
- Wait for the node to be ready

**Stage 2: Install monitoring stack**
```powershell
terraform apply --var-file=primary.tfvars
```

This takes about 3-5 minutes and installs:
- cert-manager
- Prometheus stack
- Grafana with dashboards

### 8. Configure kubectl

Set your `KUBECONFIG` environment variable:

```powershell
$env:KUBECONFIG = "$PWD\k3s.yaml"
```

Or permanently add to your profile:

```powershell
[Environment]::SetEnvironmentVariable("KUBECONFIG", "$PWD\k3s.yaml", "User")
```

### 9. Verify Installation

Check that the node is ready:

```powershell
kubectl get nodes
```

Expected output:
```
NAME       STATUS   ROLES                  AGE   VERSION
k3s-node   Ready    control-plane,master   5m    v1.30.x+k3s1
```

Check all pods are running:

```powershell
kubectl get pods --all-namespaces
```

Verify Hetzner cloud controller is running:

```powershell
kubectl get pods -n kube-system | Select-String "hcloud"
```

You should see:
- `hcloud-cloud-controller-manager` pods
- `hcloud-csi-controller` pod
- `hcloud-csi-node` pods

### 10. Access Grafana

#### Option A: Using Port-Forward (No domain required)

```powershell
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
```

Then open your browser to: http://localhost:3000

#### Option B: Using Domain (Requires DNS setup)

If you set `grafana_domain` in `primary.tfvars`:

1. Point your domain's DNS A record to the server IP:
   ```powershell
   terraform output k3s_node_public_ip
   ```

2. Wait for DNS propagation (~5-10 minutes)

3. Access Grafana at: `https://your-domain.com`

**Default Login:**
- Username: `admin`
- Password: Value from `primary.tfvars` (default: `admin`)

### 11. Get Grafana Credentials

To retrieve the Grafana password:

```powershell
terraform output -json grafana_info
```

## Exploring Grafana Dashboards

After logging in to Grafana:

1. Click **Dashboards** in the left menu (or go to Home → Dashboards)
2. You'll see pre-installed dashboards:
   - **Traefik** - Monitor ingress controller traffic and performance
   - **Kubernetes Cluster** - Overall cluster health and resources
   - **Node Exporter** - Detailed server metrics (CPU, memory, disk, network)
   - **K3s** - K3s-specific metrics

### Key Metrics to Monitor

**Traefik Dashboard:**
- Request rate and response times
- HTTP status codes distribution
- Backend server health
- TLS certificate status

**Cluster Dashboard:**
- Pod CPU and memory usage
- Namespace resource consumption
- Deployment status
- Persistent volume usage

**Node Exporter Dashboard:**
- Server CPU utilization
- Memory usage and swap
- Disk I/O and space
- Network traffic

## Monitoring Features

### What's Being Monitored

1. **Kubernetes Components:**
   - API server health and latency
   - Scheduler performance
   - Controller manager
   - Kubelet metrics
   - etcd (built into K3s)

2. **Traefik Ingress:**
   - Request counts and rates
   - Response times
   - Error rates
   - TLS certificate expiration
   - Backend health

3. **Node/Server Metrics:**
   - CPU usage per core
   - Memory and swap usage
   - Disk I/O and space
   - Network throughput
   - System load average

4. **Application Metrics:**
   - Pod CPU and memory usage
   - Container restarts
   - Deployment status
   - Service availability

### Alerting

Prometheus comes with pre-configured alerts for:
- High CPU/memory usage
- Disk space running low
- Pod crash loops
- API server unavailability
- Certificate expiration warnings

To configure alert notifications, edit Alertmanager:

```powershell
kubectl edit configmap -n monitoring kube-prometheus-stack-alertmanager
```

## Project Structure

```
k3s-hetzner/
├── terraform/
│   ├── main.tf                      # Terraform and provider configuration
│   ├── provider.tf                  # Provider configurations (Hetzner, Helm, Kubectl, AWS)
│   ├── variables.tf                 # Variable definitions
│   ├── network.tf                   # Private network setup
│   ├── monitoring.tf                # Prometheus and Grafana setup
│   ├── cert-manager.tf              # TLS certificate management
│   ├── traefik.tf                   # Traefik dashboard configuration
│   ├── external-secrets.tf          # External Secrets Operator setup
│   ├── cloud-init.yaml              # K3s installation script
│   ├── primary.tfvars               # Your configuration (DO NOT COMMIT!)
│   ├── k3s.yaml                     # Kubeconfig (auto-generated)
│   └── EXTERNAL_SECRETS_USAGE.md    # External Secrets detailed guide
└── README.md                        # This file
```

## Cost Estimation

- **CPX42 Server**: ~€36.75/month
- **Persistent Volumes** (monitoring storage): ~€6.00/month (70 GB total)
- **Traffic**: 20 TB included
- **Total**: ~€42.75/month

## Common Tasks

### Access Prometheus UI

```powershell
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
```

Then open: http://localhost:9090

### Access Alertmanager UI

```powershell
kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093
```

Then open: http://localhost:9093

### View Traefik Dashboard

The Traefik dashboard is enabled and accessible via port-forward to the pod:

```powershell
# Get Traefik pod name
$TRAEFIK_POD = kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik -o jsonpath='{.items[0].metadata.name}'

# Port-forward to the pod
kubectl port-forward -n kube-system pod/$TRAEFIK_POD 8080:8080
```

Then open: http://localhost:8080/dashboard/

**Note:** The dashboard will show "no data" until you deploy applications with Ingress resources and route traffic through Traefik on **port 80** (or NodePort 30080) of the server's IP. This is normal for a fresh cluster.

**Dashboard sections:**
- **HTTP Routers**: Your ingress rules (empty until you create Ingress resources)
- **HTTP Services**: Backend services (empty until you create services)
- **HTTP Middlewares**: Rate limiting, auth, etc.
- **Entrypoints**: Shows web (80) and websecure (443) are active

For **historical metrics and graphs**, use the Grafana Traefik dashboard which provides:
- Request rates over time
- Response time trends
- Error rates
- Traffic volume
- And more with alerting capabilities

### Check Monitoring Stack Status

```powershell
kubectl get pods -n monitoring
kubectl get pvc -n monitoring
```

### Restart Grafana

```powershell
kubectl rollout restart deployment -n monitoring kube-prometheus-stack-grafana
```

### View Prometheus Targets

Check if all targets are being scraped:

```powershell
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
```

Navigate to: http://localhost:9090/targets

### Check Hetzner Cloud Controller

```powershell
# Check cloud controller pods
kubectl get pods -n kube-system | Select-String "hcloud"

# Check cloud controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=hcloud-cloud-controller-manager

# Check CSI driver
kubectl get pods -n kube-system | Select-String "csi"
```

## Accessing the Server

SSH into the server (password authentication is disabled, SSH key only):

```powershell
ssh -i C:\Users\nndlk\.ssh\id_ed25519 admin@$(terraform output -raw k3s_node_public_ip)
```

### Useful Commands on the Server

```bash
# Check K3s status
sudo systemctl status k3s

# View K3s logs
sudo journalctl -u k3s -f

# Check server resources
htop
df -h
free -h

# View running containers
sudo k3s crictl ps

# Check cloud-init status
sudo cloud-init status

# View cloud-init logs
sudo cat /var/log/cloud-init-output.log
```

## Troubleshooting

### Pods Stuck in Pending

Check if the Hetzner cloud controller is running:

```powershell
kubectl get pods -n kube-system | Select-String "hcloud"
```

If not running, check cloud-init logs on the server:

```bash
sudo cat /var/log/cloud-init-output.log | grep -i error
```

Check node taints:

```powershell
kubectl describe node k3s-node | Select-String "Taints"
```

If the node has the uninitialized taint, wait for the cloud controller to remove it, or manually remove:

```powershell
kubectl taint nodes k3s-node node.cloudprovider.kubernetes.io/uninitialized:NoSchedule-
```

### Terraform Apply Fails on Kubeconfig Fetch

The script waits up to 5 minutes for K3s to be ready. If it fails:

1. Check if the server is accessible:
   ```powershell
   ssh -i C:\Users\nndlk\.ssh\id_ed25519 admin@$(terraform output -raw k3s_node_public_ip)
   ```

2. Manually check K3s status:
   ```bash
   sudo systemctl status k3s
   sudo journalctl -u k3s -f
   ```

3. Manually fetch kubeconfig:
   ```powershell
   scp -i C:\Users\nndlk\.ssh\id_ed25519 admin@YOUR_SERVER_IP:/etc/rancher/k3s/k3s.yaml k3s.yaml
   (Get-Content k3s.yaml) -replace '127.0.0.1', 'YOUR_SERVER_IP' | Set-Content k3s.yaml
   ```

### Monitoring Pods Not Starting

Check events:

```powershell
kubectl get events -n monitoring --sort-by='.lastTimestamp'
```

Check pod logs:

```powershell
kubectl logs -n monitoring deployment/kube-prometheus-stack-grafana
kubectl logs -n monitoring prometheus-kube-prometheus-stack-prometheus-0
```

### Persistent Volumes Not Binding

Check PVC status:

```powershell
kubectl get pvc -n monitoring
```

Check if Hetzner CSI driver is running:

```powershell
kubectl get pods -n kube-system | Select-String "csi"
```

Check CSI driver logs:

```powershell
kubectl logs -n kube-system -l app=hcloud-csi-controller
```

### Grafana Not Accessible

Check Grafana pod status:

```powershell
kubectl get pods -n monitoring | Select-String "grafana"
kubectl logs -n monitoring deployment/kube-prometheus-stack-grafana
```

Verify ingress (if using domain):

```powershell
kubectl get ingress -n monitoring
```

### Traefik Metrics Not Available in Grafana

If the Grafana Traefik dashboard shows "No Data":

1. **Check if Traefik metrics service exists:**
   ```powershell
   kubectl get svc -n kube-system traefik-metrics
   ```

2. **Check if ServiceMonitor exists:**
   ```powershell
   kubectl get servicemonitor -n monitoring traefik
   ```

3. **Verify Prometheus is scraping Traefik:**
   ```powershell
   kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
   ```

   Open http://localhost:9090/targets and look for "traefik" endpoint - it should show as "UP"

4. **Check Traefik metrics endpoint directly:**
   ```powershell
   kubectl port-forward -n kube-system svc/traefik-metrics 9100:9100
   ```

   Open http://localhost:9090/metrics - you should see Traefik metrics

5. **If metrics service doesn't exist, apply it manually:**
   ```powershell
   kubectl apply -f - <<'EOF'
   apiVersion: v1
   kind: Service
   metadata:
     name: traefik-metrics
     namespace: kube-system
     labels:
       app.kubernetes.io/name: traefik-metrics
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
   ---
   apiVersion: monitoring.coreos.com/v1
   kind: ServiceMonitor
   metadata:
     name: traefik
     namespace: monitoring
     labels:
       release: kube-prometheus-stack
   spec:
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
   EOF
   ```

6. **Wait a few minutes** for Prometheus to scrape metrics, then refresh Grafana

7. **If the dashboard is empty**, it may be using the wrong dashboard ID. Import dashboard manually:
   - Go to Grafana → Dashboards → Import
   - Enter dashboard ID: **17346** (Traefik Official Dashboard)
   - Select Prometheus as data source
   - Click Import

### SSH Host Key Warnings

If you recreate the server and get SSH warnings:

```powershell
ssh-keygen -R YOUR_SERVER_IP
```

### Certificate Errors with Helm/kubectl

Make sure the kubeconfig file exists before running stage 2:

```powershell
Test-Path k3s.yaml
```

If it doesn't exist, run stage 1 again.

## Security Considerations

1. **Firewall**: Configure Hetzner Cloud Firewall to restrict access:
   - Allow SSH (22) from your IP only
   - Allow HTTP (80) and HTTPS (443) from anywhere (for Traefik)
   - Allow Kubernetes API (6443) from your IP only

2. **Change Default Passwords**: Always change the default Grafana password in `primary.tfvars`

3. **SSH Keys Only**: Password authentication is disabled - only SSH key authentication is allowed

4. **API Token**: Keep your Hetzner API token secure and never commit `*.tfvars` files to version control

5. **Network Policies**: Implement Kubernetes Network Policies for pod-to-pod communication

6. **RBAC**: Configure proper Role-Based Access Control for your cluster

7. **TLS**: Use cert-manager with Let's Encrypt for automatic TLS certificates

8. **Secrets Management**: Use External Secrets Operator with AWS Parameter Store for secure secrets management (see [EXTERNAL_SECRETS_USAGE.md](EXTERNAL_SECRETS_USAGE.md)). Never commit secrets to version control.

## Backup Strategy

### Backup Grafana Dashboards

```powershell
kubectl exec -n monitoring deployment/kube-prometheus-stack-grafana -- grafana-cli admin export-all-dashboards > dashboards-backup.json
```

### Backup Prometheus Data

Create a snapshot using Hetzner's snapshot feature or backup the persistent volume.

### Backup K3s Configuration

```powershell
ssh -i C:\Users\nndlk\.ssh\id_ed25519 admin@$(terraform output -raw k3s_node_public_ip) "sudo tar -czf /tmp/k3s-backup.tar.gz /etc/rancher /var/lib/rancher"
scp -i C:\Users\nndlk\.ssh\id_ed25519 admin@$(terraform output -raw k3s_node_public_ip):/tmp/k3s-backup.tar.gz .
```

## Updating the Cluster

### Update K3s

SSH into the server and run:

```bash
curl -sfL https://get.k3s.io | sh -
```

### Update Helm Charts

```powershell
# Update cert-manager
helm upgrade cert-manager jetstack/cert-manager -n cert-manager

# Update kube-prometheus-stack
helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack -n monitoring
```

### Update Hetzner Controllers

```powershell
# Update cloud controller
kubectl apply -f https://github.com/hetznercloud/hcloud-cloud-controller-manager/releases/latest/download/ccm-networks.yaml

# Update CSI driver
kubectl apply -f https://raw.githubusercontent.com/hetznercloud/csi-driver/v2.6.0/deploy/kubernetes/hcloud-csi.yml
```

## Cleanup

To destroy all resources:

```powershell
terraform destroy --var-file=primary.tfvars
```

**Warning**: This will delete the server and all persistent volumes. Make sure to backup any important data first!

## Customization

### Change Server Location

Edit `primary.tfvars`:

```hcl
server_location = "fsn1"          # Falkenstein
server_datacenter = "fsn1-dc14"   # Must match location

# Other options:
# nbg1 / nbg1-dc3   - Nuremberg, Germany
# fsn1 / fsn1-dc14  - Falkenstein, Germany
# hel1 / hel1-dc2   - Helsinki, Finland
# ash / ash-dc1     - Ashburn, USA
# hil / hil-dc1     - Hillsboro, USA
```

### Adjust Prometheus Retention

Edit `monitoring.tf` and change:

```hcl
retention: 30d  # Change to 7d, 60d, 90d, etc.
```

### Adjust Storage Sizes

Edit `monitoring.tf`:

```hcl
# Prometheus storage
storage: 50Gi  # Increase/decrease as needed

# Grafana storage
size: 10Gi

# Alertmanager storage
storage: 10Gi
```

Then apply:

```powershell
terraform apply --var-file=primary.tfvars
```

## Secrets Management with External Secrets

This cluster includes External Secrets Operator for managing secrets from AWS Parameter Store. This allows you to:

- Store sensitive data (API keys, passwords, certificates) in AWS Parameter Store
- Automatically sync them into Kubernetes Secrets
- Rotate secrets without redeploying applications
- Use AWS IAM for access control and audit logging

### Quick Start

1. **Store a secret in AWS Parameter Store:**
   ```bash
   aws ssm put-parameter \
     --name "/k8s/production/myapp/database-password" \
     --value "my-secure-password" \
     --type "SecureString" \
     --region us-east-1
   ```

2. **Create an ExternalSecret resource:**
   ```yaml
   apiVersion: external-secrets.io/v1beta1
   kind: ExternalSecret
   metadata:
     name: myapp-secret
     namespace: default
   spec:
     refreshInterval: 1h
     secretStoreRef:
       name: aws-parameter-store
       kind: ClusterSecretStore
     target:
       name: myapp-secret
     data:
       - secretKey: db-password
         remoteRef:
           key: /k8s/production/myapp/database-password
   ```

3. **Use the secret in your deployment:**
   ```yaml
   env:
     - name: DB_PASSWORD
       valueFrom:
         secretKeyRef:
           name: myapp-secret
           key: db-password
   ```

### Full Documentation

For complete setup instructions, advanced usage, Helm integration, and troubleshooting, see:
**[External Secrets Usage Guide](terraform/EXTERNAL_SECRETS_USAGE.md)**

## Next Steps

1. **Set Up Secrets Management**: Configure External Secrets for your applications (see [EXTERNAL_SECRETS_USAGE.md](terraform/EXTERNAL_SECRETS_USAGE.md))

2. **Deploy Applications**: Start deploying your applications to the cluster

3. **Configure Ingress**: Create Ingress resources for your applications with Traefik

4. **Set Up Backups**: Implement automated backup solutions using Velero

5. **Configure Alerts**: Set up Alertmanager to send notifications (Slack, email, PagerDuty)

6. **Add Custom Dashboards**: Create custom Grafana dashboards for your applications

7. **Implement GitOps**: Consider using ArgoCD or Flux for GitOps deployments

8. **Scale Resources**: Monitor resource usage and adjust server size if needed

9. **High Availability**: For production, consider a multi-node setup with load balancers

## Example: Deploy a Sample Application

To test the cluster and see data in Traefik/Grafana dashboards, deploy a simple test application:

### Quick Test with Port-Forward (No Domain Required)

**Note:** Port-forwarding bypasses Traefik, so it won't generate metrics. Use this only for quick testing of the application itself.

```powershell
# Deploy the whoami test app
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: whoami
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: whoami
  template:
    metadata:
      labels:
        app: whoami
    spec:
      containers:
      - name: whoami
        image: traefik/whoami:latest
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: whoami
  namespace: default
spec:
  selector:
    app: whoami
  ports:
  - port: 80
    targetPort: 80
EOF

# Test via port-forward (bypasses Traefik - no metrics)
kubectl port-forward svc/whoami 8080:80

# In another terminal, test it
curl http://localhost:8080
```

### With Ingress (Generates Traefik Metrics)

**To see metrics in Traefik and Grafana, you MUST route traffic through the Ingress.**

**Option A: Using catch-all Ingress (easiest, no DNS needed)**

```powershell
# Create Ingress without specific host
kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: whoami
  namespace: default
spec:
  ingressClassName: traefik
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: whoami
            port:
              number: 80
EOF

# Access via server IP (goes through Traefik)
$SERVER_IP = terraform output -raw k3s_node_public_ip
Invoke-WebRequest -Uri "http://$SERVER_IP/" | Out-Null

# Generate traffic to populate metrics
for ($i=0; $i -lt 100; $i++) {
    Invoke-WebRequest -Uri "http://$SERVER_IP/" | Out-Null
    Write-Host "Request $i"
    Start-Sleep -Milliseconds 100
}
```

**Option B: Using Host header (no DNS/hosts file needed)**

```powershell
# Create Ingress with specific host
kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: whoami
  namespace: default
spec:
  ingressClassName: traefik
  rules:
  - host: whoami.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: whoami
            port:
              number: 80
EOF

# Access using Host header (goes through Traefik)
$SERVER_IP = terraform output -raw k3s_node_public_ip
Invoke-WebRequest -Uri "http://$SERVER_IP/" -Headers @{"Host"="whoami.local"} | Out-Null

# Or use curl.exe
curl.exe -H "Host: whoami.local" http://$SERVER_IP/

# Generate traffic
for ($i=0; $i -lt 100; $i++) {
    Invoke-WebRequest -Uri "http://$SERVER_IP/" -Headers @{"Host"="whoami.local"} | Out-Null
    Write-Host "Request $i"
    Start-Sleep -Milliseconds 100
}
```

**Option C: Using hosts file**

As Administrator, edit `C:\Windows\System32\drivers\etc\hosts` and add:

```
YOUR_SERVER_IP whoami.local
```

Then access normally:

```powershell
Invoke-WebRequest -Uri "http://whoami.local/" | Out-Null

# Or open in browser: http://whoami.local/
```

Create `test-app.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: whoami
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: whoami
  template:
    metadata:
      labels:
        app: whoami
    spec:
      containers:
      - name: whoami
        image: traefik/whoami:latest
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: whoami
  namespace: default
spec:
  selector:
    app: whoami
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: whoami
  namespace: default
  annotations:
    # Uncomment for automatic TLS with your domain
    # cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  ingressClassName: traefik
  rules:
  - host: whoami.yourdomain.com  # Change to your domain
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: whoami
            port:
              number: 80
  # Uncomment for TLS
  # tls:
  # - secretName: whoami-tls
  #   hosts:
  #   - whoami.yourdomain.com
```

Deploy it:

```powershell
kubectl apply -f test-app.yaml
```

**Access it through Traefik** (not port-forward) to generate metrics.

### Verify in Dashboards

After deploying the app and **sending traffic through Traefik** (not port-forward):

1. **Traefik Dashboard** - You'll now see:
   - HTTP Router for the whoami ingress
   - HTTP Service for the whoami backend
   - Request counts

2. **Grafana Traefik Dashboard** - After traffic goes through Traefik, you'll see (wait 1-2 minutes):
   - Request rate graphs
   - Response time charts
   - Status code distribution
   - Traffic volume

**Important:** Traffic must go through Traefik's Ingress for metrics to appear. Port-forwarding bypasses Traefik completely.

Generate traffic through Traefik:

```powershell
# Get server IP
$SERVER_IP = terraform output -raw k3s_node_public_ip

# Generate test traffic through Traefik (Option 1: catch-all ingress)
for ($i=0; $i -lt 100; $i++) {
    Invoke-WebRequest -Uri "http://$SERVER_IP/" | Out-Null
    Write-Host "Request $i"
    Start-Sleep -Milliseconds 100
}

# Or with Host header (Option 2)
for ($i=0; $i -lt 100; $i++) {
    Invoke-WebRequest -Uri "http://$SERVER_IP/" -Headers @{"Host"="whoami.local"} | Out-Null
    Write-Host "Request $i"
    Start-Sleep -Milliseconds 100
}
```

Then check Grafana - metrics should now appear!

### Clean Up Test App

```powershell
kubectl delete deployment whoami
kubectl delete service whoami
kubectl delete ingress whoami
```

## Resources

- [K3s Documentation](https://docs.k3s.io/)
- [Hetzner Cloud Documentation](https://docs.hetzner.cloud/)
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Traefik Documentation](https://doc.traefik.io/traefik/)
- [cert-manager Documentation](https://cert-manager.io/docs/)
- [Terraform Hetzner Provider](https://registry.terraform.io/providers/hetznercloud/hcloud/latest/docs)
- [Hetzner Cloud Controller Manager](https://github.com/hetznercloud/hcloud-cloud-controller-manager)
- [Hetzner CSI Driver](https://github.com/hetznercloud/csi-driver)

## Support

If you encounter issues:

1. Check the troubleshooting section above
2. Review Terraform logs
3. Check Kubernetes events: `kubectl get events --all-namespaces --sort-by='.lastTimestamp'`
4. Check pod logs for specific issues
5. Review cloud-init logs on the server: `sudo cat /var/log/cloud-init-output.log`

## License

This configuration is provided as-is for educational and production use.
