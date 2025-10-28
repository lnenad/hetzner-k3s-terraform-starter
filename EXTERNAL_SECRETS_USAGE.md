# External Secrets with AWS Parameter Store - Usage Guide

This guide explains how to use External Secrets Operator with AWS Parameter Store in your K3s cluster.

## Overview

External Secrets Operator synchronizes secrets from AWS Parameter Store into Kubernetes Secrets, allowing your applications to access sensitive data securely without hardcoding credentials.

## Prerequisites

1. AWS CLI configured with credentials
2. Terraform installed
3. kubectl access to your K3s cluster

## Setup

### 1. Configure Variables

Create a `terraform.tfvars` file or set the following variables:

```hcl
# AWS Configuration
aws_region              = "us-east-1"  # Your AWS region
aws_profile             = "default"    # Your AWS CLI profile (optional)
parameter_store_prefix  = "k8s/production"  # Prefix for your parameters

# Existing variables
hcloud_token           = "your-hetzner-token"
# ... other variables
```

### 2. Deploy Infrastructure

```bash
terraform init
terraform plan
terraform apply
```

This will:
- Install External Secrets Operator
- Create an IAM user with Parameter Store access
- Create a ClusterSecretStore for cluster-wide access
- Set up example SecretStore and ExternalSecret

## Using External Secrets in Your Applications

### Step 1: Store Secrets in AWS Parameter Store

```bash
# Store a secret
aws ssm put-parameter \
  --name "/k8s/production/myapp/database-password" \
  --value "my-secure-password" \
  --type "SecureString" \
  --region us-east-1

# Store a JSON object (useful for multiple related secrets)
aws ssm put-parameter \
  --name "/k8s/production/myapp/database-config" \
  --value '{"host":"db.example.com","port":"5432","user":"admin"}' \
  --type "SecureString" \
  --region us-east-1

# List your parameters
aws ssm describe-parameters \
  --parameter-filters "Key=Name,Option=BeginsWith,Values=/k8s/production/" \
  --region us-east-1
```

### Step 2: Create an ExternalSecret Resource

Create a file `myapp-external-secret.yaml`:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: myapp-secret
  namespace: default  # Your application namespace
spec:
  refreshInterval: 1h  # How often to sync from Parameter Store

  secretStoreRef:
    name: aws-parameter-store
    kind: ClusterSecretStore

  target:
    name: myapp-secret  # Name of the Kubernetes Secret to create
    creationPolicy: Owner
    deletionPolicy: Retain

  data:
    # Simple parameter
    - secretKey: db-password
      remoteRef:
        key: /k8s/production/myapp/database-password

    # Extract specific field from JSON parameter using gjson
    - secretKey: db-host
      remoteRef:
        key: /k8s/production/myapp/database-config
        property: host

    - secretKey: db-port
      remoteRef:
        key: /k8s/production/myapp/database-config
        property: port
```

Apply it:

```bash
kubectl apply -f myapp-external-secret.yaml
```

### Step 3: Use the Secret in Your Deployment

In your Helm chart or Kubernetes deployment:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  template:
    spec:
      containers:
      - name: myapp
        image: myapp:latest
        env:
          # Use individual secret keys
          - name: DB_PASSWORD
            valueFrom:
              secretKeyRef:
                name: myapp-secret
                key: db-password

          - name: DB_HOST
            valueFrom:
              secretKeyRef:
                name: myapp-secret
                key: db-host

          # Or mount entire secret as files
        volumeMounts:
          - name: secrets
            mountPath: /secrets
            readOnly: true

      volumes:
        - name: secrets
          secret:
            secretName: myapp-secret
```

## Advanced Usage

### Using dataFrom for Multiple Parameters

Fetch all parameters under a path:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: myapp-all-secrets
  namespace: default
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-parameter-store
    kind: ClusterSecretStore
  target:
    name: myapp-all-secrets
  dataFrom:
    - extract:
        key: /k8s/production/myapp/
```

### Parameter Versioning

Fetch a specific version of a parameter:

```yaml
data:
  - secretKey: api-key
    remoteRef:
      key: /k8s/production/myapp/api-key
      version: "5"  # Specific version
```

### Namespace-Specific SecretStore

If you need different credentials per namespace:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: namespace-parameter-store
  namespace: my-namespace
spec:
  provider:
    aws:
      service: ParameterStore
      region: us-east-1
      auth:
        secretRef:
          accessKeyID:
            name: aws-credentials
            key: access-key-id
          secretAccessKey:
            name: aws-credentials
            key: secret-access-key
```

## Helm Chart Integration

In your Helm values.yaml:

```yaml
externalSecrets:
  enabled: true
  secretStoreName: aws-parameter-store
  secretStoreKind: ClusterSecretStore
  secrets:
    - name: myapp-database
      refreshInterval: 1h
      data:
        - secretKey: password
          remoteRef:
            key: /k8s/production/myapp/db-password
```

In your Helm template:

```yaml
{{- if .Values.externalSecrets.enabled }}
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: {{ include "myapp.fullname" . }}-secret
  namespace: {{ .Release.Namespace }}
spec:
  refreshInterval: {{ .Values.externalSecrets.refreshInterval }}
  secretStoreRef:
    name: {{ .Values.externalSecrets.secretStoreName }}
    kind: {{ .Values.externalSecrets.secretStoreKind }}
  target:
    name: {{ include "myapp.fullname" . }}-secret
  data:
  {{- range .Values.externalSecrets.secrets }}
    - secretKey: {{ .secretKey }}
      remoteRef:
        key: {{ .remoteRef.key }}
  {{- end }}
{{- end }}
```

## Monitoring and Troubleshooting

### Check External Secrets Status

```bash
# Check operator pods
kubectl get pods -n external-secrets

# List all ExternalSecrets
kubectl get externalsecrets -A

# Check specific ExternalSecret status
kubectl describe externalsecret myapp-secret -n default

# View events
kubectl get events -n default --sort-by='.lastTimestamp'

# Check if secret was created
kubectl get secret myapp-secret -n default
```

### Common Issues

**ExternalSecret not syncing:**
- Check IAM permissions
- Verify parameter exists in AWS Parameter Store
- Check the parameter path matches exactly (including prefix)
- Ensure AWS region is correct

**Authentication errors:**
- Verify AWS credentials secret exists: `kubectl get secret aws-credentials -n external-secrets`
- Check IAM user has correct policy attached
- Test AWS CLI access with the same credentials

**Secret not updating:**
- Check `refreshInterval` value
- Force sync by deleting and recreating the ExternalSecret
- Check operator logs: `kubectl logs -n external-secrets deployment/external-secrets`

## Security Best Practices

1. **Use KMS encryption** for Parameter Store parameters (SecureString type)
2. **Rotate IAM credentials** regularly
3. **Use IRSA** (IAM Roles for Service Accounts) in production EKS clusters instead of static credentials
4. **Limit parameter paths** in IAM policies using least privilege principle
5. **Set appropriate refreshInterval** to balance security and API costs
6. **Use deletionPolicy: Retain** to prevent accidental secret deletion
7. **Monitor access** using CloudTrail and Parameter Store access logs

## Production Considerations

### For AWS EKS (Recommended)

Instead of static IAM credentials, use IRSA:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: aws-parameter-store
spec:
  provider:
    aws:
      service: ParameterStore
      region: us-east-1
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets
            namespace: external-secrets
```

Configure the service account with IAM role annotation:
```yaml
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT_ID:role/external-secrets-role
```

## Cost Optimization

- Parameter Store API calls cost $0.05 per 10,000 requests
- Set reasonable `refreshInterval` (1h or more for static secrets)
- Use `dataFrom` to fetch multiple parameters in one API call
- Consider using AWS Secrets Manager for secrets that change frequently (with its rotation features)

## References

- [External Secrets Operator Documentation](https://external-secrets.io/)
- [AWS Parameter Store Pricing](https://aws.amazon.com/systems-manager/pricing/)
- [IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
