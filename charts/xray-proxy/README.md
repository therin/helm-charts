# Xray Proxy Helm Chart

A Kubernetes Helm chart for deploying Xray proxy server with dual protocol support (SOCKS5 and VLESS+Reality).

## Overview

This Helm chart deploys an Xray proxy server that supports:
- **SOCKS5 proxy** for standard proxy connections (port 1080)
- **VLESS+Reality protocol** for advanced traffic obfuscation (port 443)

The chart is designed to work with existing Cloudflare Tunnel infrastructure and can be deployed via Flux GitOps.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.2.0+
- PV provisioner support in the underlying infrastructure (optional)

## Installation

### 1. Generate Required Keys

Before installation, generate the necessary keys and credentials:

```bash
# Make the script executable
chmod +x scripts/generate-keys.sh

# Generate complete configuration
./scripts/generate-keys.sh --complete
```

This will generate:
- Client UUIDs for VLESS connections
- Reality key pair (private/public keys)
- Short IDs for Reality protocol
- Optional SOCKS5 credentials

### 2. Configure Values

Copy the example values file and update with your generated keys:

```bash
cp values-example.yaml my-values.yaml
```

Edit `my-values.yaml` and replace the example values with your generated keys:

```yaml
xray:
  reality:
    privateKey: "YOUR_GENERATED_PRIVATE_KEY"
    publicKey: "YOUR_GENERATED_PUBLIC_KEY"
    shortIds:
      - "your_short_id_1"
      - "your_short_id_2"
      - "your_short_id_3"
    clients:
      - id: "your-client-uuid-1"
        flow: "xtls-rprx-vision"
      - id: "your-client-uuid-2"
        flow: "xtls-rprx-vision"
```

### 3. Install the Chart

```bash
# Install with custom values
helm install xray-proxy ./xray-proxy -f my-values.yaml

# Or install in a specific namespace
helm install xray-proxy ./xray-proxy -f my-values.yaml -n flux-system
```

### 4. Verify Installation

```bash
# Check pod status
kubectl get pods -l app.kubernetes.io/name=xray-proxy

# Check service
kubectl get svc -l app.kubernetes.io/name=xray-proxy

# View logs
kubectl logs -l app.kubernetes.io/name=xray-proxy
```

## Configuration

### Key Configuration Options

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of replicas | `1` |
| `image.repository` | Xray image repository | `teddysun/xray` |
| `image.tag` | Xray image tag | `1.8.24` |
| `service.type` | Kubernetes service type | `ClusterIP` |
| `xray.socks5.enabled` | Enable SOCKS5 proxy | `true` |
| `xray.socks5.port` | SOCKS5 port | `1080` |
| `xray.socks5.auth` | SOCKS5 authentication | `noauth` |
| `xray.reality.enabled` | Enable VLESS+Reality | `true` |
| `xray.reality.port` | VLESS+Reality port | `443` |
| `xray.reality.dest` | Reality target domain | `www.microsoft.com:443` |

### SOCKS5 Configuration

```yaml
xray:
  socks5:
    enabled: true
    port: 1080
    auth: "password"  # or "noauth"
    udp: true
    accounts:
      - user: "username1"
        pass: "password1"
      - user: "username2"
        pass: "password2"
```

### VLESS+Reality Configuration

```yaml
xray:
  reality:
    enabled: true
    port: 443
    dest: "www.microsoft.com:443"
    serverNames:
      - "www.microsoft.com"
    privateKey: "your_private_key"
    publicKey: "your_public_key"
    shortIds:
      - "short_id_1"
      - "short_id_2"
    clients:
      - id: "client-uuid-1"
        flow: "xtls-rprx-vision"
```

### Service Configuration

```yaml
service:
  type: ClusterIP  # or NodePort, LoadBalancer
  socks5Port: 1080
  realityPort: 443
  # For LoadBalancer type
  loadBalancerIP: "1.2.3.4"
  loadBalancerSourceRanges:
    - "10.0.0.0/8"
```

### Resource Configuration

```yaml
resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 100m
    memory: 128Mi
```

## Usage

### SOCKS5 Proxy

Configure your browser or application to use SOCKS5 proxy:
- **Host**: Service IP or domain
- **Port**: 1080 (default)
- **Authentication**: As configured in values

### VLESS+Reality Client

Use an Xray-compatible client with the following configuration:

```json
{
  "outbounds": [
    {
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "your-server-address",
            "port": 443,
            "users": [
              {
                "id": "your-client-uuid",
                "flow": "xtls-rprx-vision"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "serverName": "www.microsoft.com",
          "fingerprint": "chrome",
          "shortId": "your_short_id",
          "publicKey": "your_public_key"
        }
      }
    }
  ]
}
```

## Monitoring

Enable monitoring to expose Prometheus metrics:

```yaml
monitoring:
  enabled: true
  port: 8080
```

Metrics will be available at `/stats/prometheus` endpoint.

## Security Considerations

1. **Key Management**: Store Reality keys securely using Kubernetes Secrets
2. **Network Policies**: Implement network policies to restrict access
3. **Resource Limits**: Set appropriate resource limits to prevent abuse
4. **Regular Updates**: Keep Xray image updated to latest stable version

## Troubleshooting

### Common Issues

1. **Pod not starting**:
   ```bash
   kubectl describe pod -l app.kubernetes.io/name=xray-proxy
   kubectl logs -l app.kubernetes.io/name=xray-proxy
   ```

2. **Connection refused**:
   - Check service configuration
   - Verify port forwarding if using port-forward
   - Check firewall rules

3. **Reality connection fails**:
   - Verify target domain is accessible
   - Check Reality keys are correctly generated
   - Ensure client configuration matches server

### Debug Commands

```bash
# Port forward for local testing
kubectl port-forward svc/xray-proxy 1080:1080 8443:443

# Check configuration
kubectl get configmap xray-proxy-config -o yaml

# Check secrets
kubectl get secret xray-proxy-secret -o yaml
```

## Upgrading

```bash
# Upgrade with new values
helm upgrade xray-proxy ./xray-proxy -f my-values.yaml

# Check upgrade status
helm status xray-proxy
```

## Uninstalling

```bash
# Uninstall the chart
helm uninstall xray-proxy

# Clean up any remaining resources
kubectl delete pvc -l app.kubernetes.io/name=xray-proxy
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test the changes
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.