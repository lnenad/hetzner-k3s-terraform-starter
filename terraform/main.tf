# Server creation with one linked primary ip (ipv4)
resource "hcloud_primary_ip" "k3s_node_public_ip" {
  name          = "k3s-node-ip"
  datacenter    = var.server_datacenter
  type          = "ipv4"
  assignee_type = "server"
  auto_delete   = true
}

resource "hcloud_ssh_key" "ssh_key" {
  name       = "hetzner-ssh-key"
  public_key = file("C:/Users/nndlk/.ssh/id_ed25519.pub")
}

data "template_file" "k3s-node-config" {
  template = file("${path.module}/cloud-init.yaml")
  vars = {
    local_ssh_public_key = file("C:/Users/nndlk/.ssh/id_ed25519.pub")
    hcloud_token         = var.hcloud_token
    hcloud_network       = hcloud_network.private_network.id
    public_ip            = tostring(hcloud_primary_ip.k3s_node_public_ip.ip_address)
  }
}

resource "hcloud_server" "k3s-node" {
  name        = var.server_name
  image       = "ubuntu-24.04"
  server_type = "cpx42"
  datacenter  = var.server_datacenter
  user_data   = data.template_file.k3s-node-config.rendered
  ssh_keys    = [hcloud_ssh_key.ssh_key.id]

  public_net {
    ipv4         = hcloud_primary_ip.k3s_node_public_ip.id
    ipv4_enabled = true
    ipv6_enabled = true
  }

  network {
    network_id = hcloud_network.private_network.id
    ip         = "10.0.1.1"
  }

  depends_on = [hcloud_network_subnet.private_network_subnet]
}

output "k3s_node_public_ip" {
  description = "Public IP address of the K3s node"
  value       = tostring(hcloud_primary_ip.k3s_node_public_ip.ip_address)
}

# Wait for K3s to be ready and fetch kubeconfig
resource "null_resource" "fetch_kubeconfig" {
  depends_on = [hcloud_server.k3s-node]

  provisioner "local-exec" {
    command = <<-EOT
      # Remove old host key if it exists
      ssh-keygen -R ${hcloud_primary_ip.k3s_node_public_ip.ip_address} 2>$null

      $maxAttempts = 60
      $attempt = 0
      $connected = $false

      while (-not $connected -and $attempt -lt $maxAttempts) {
        $attempt++
        Write-Host "Waiting for K3s to be ready... (Attempt $attempt/$maxAttempts)"

        try {
          ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL -o ConnectTimeout=5 -i C:/Users/nndlk/.ssh/id_ed25519 admin@${hcloud_primary_ip.k3s_node_public_ip.ip_address} "sudo test -f /etc/rancher/k3s/k3s.yaml"
          if ($LASTEXITCODE -eq 0) {
            $connected = $true
            Write-Host "K3s is ready!"
          }
        } catch {
          Start-Sleep -Seconds 5
        }

        if (-not $connected) {
          Start-Sleep -Seconds 5
        }
      }

      if (-not $connected) {
        Write-Host "Timeout waiting for K3s to be ready"
        exit 1
      }

      # Fetch kubeconfig
      scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL -i C:/Users/nndlk/.ssh/id_ed25519 admin@${hcloud_primary_ip.k3s_node_public_ip.ip_address}:/etc/rancher/k3s/k3s.yaml ${path.module}/k3s.yaml

      # Update server address
      (Get-Content ${path.module}/k3s.yaml) -replace '127.0.0.1', '${hcloud_primary_ip.k3s_node_public_ip.ip_address}' | Set-Content ${path.module}/k3s.yaml

      Write-Host "Kubeconfig is ready at ${path.module}/k3s.yaml"
    EOT
    interpreter = ["PowerShell", "-Command"]
  }

  triggers = {
    server_id = hcloud_server.k3s-node.id
  }
}
