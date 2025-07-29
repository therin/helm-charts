# Xray Proxy Deployment Guide

This guide provides step-by-step instructions for deploying the Xray proxy Helm chart in a Kubernetes cluster with Flux GitOps.

## Prerequisites

- Kubernetes cluster (1.19+)
- Helm 3.2.0+
- Flux v2 installed and configured
- kubectl configured to access your cluster

## Quick Start

### 1. Clone and Prepare

```bash
# Navigate to your project directory
cd /path/to/kube-socks5

# Ensure scripts are executable
chmod +x scripts/generate-keys.sh
```

### 2. Generate Credentials

```bash
# Generate all required keys and credentials
./scripts/generate-keys.sh --complete
```

**Sample Output:**
```
=== XRAY REALITY CONFIGURATION ===

Client UUIDs:
  Client 1: 12345678-1234-1234-1234-123456789abc
  Client 2: 87654321-4321-4321-4321-cba987654321

Reality Key Pair:
  Private Key: gKyKGNuQBhzIwvNaKDPdVVbouZpfrvzIHONOSxrmQ1M
  Public Key: yG02mDZVkGnKs8lrx7cBhw8p7yKpQFWgOaZpZQKqHhk

Short IDs:
  a1b2c3d4e5f6g7h8
  i9j0k1l2m3n4o5p6
  q7r8s9t0u1v2w3x4

SOCKS5 Credentials (optional):
  Username: user1a2b
  Password: Xy9Kp2Mn8Qr5
```

### 3. Configure Values

Create your custom values file:

```bash
cp xray-proxy/values-example.yaml my-values.yaml
```

Edit `my-values.yaml` with your generated credentials:

```yaml
xray:
  reality:
    enabled: true
    privateKey: "gKyKGNuQBhzIwvNaKDPdVVbouZpfrvzIHONOSxrmQ1M"
    publicKey: "yG02mDZVkGnKs8lrx7cBhw8p7yKpQFWgOaZpZQKqHhk"
    shortIds:
      - "a1b2c3d4e5f6g7h8"
      - "i9j0k1l2m3n4o5p6"
      - "q7r8s9t0u1v2w3x4"
    clients:
      - id: "12345678-1234-1234-1234-123456789abc"
        flow: "xtls-rprx-vision"
      - id: "87654321-4321-4321-4321-cba987654321"
        flow: "xtls-rprx-vision"
```

### 4. Deploy with Helm

#### Option A: Direct Helm Installation

```bash
# Install in flux-system namespace
helm install xray-proxy ./xray-proxy -f my-values.yaml -n flux-system

# Verify deployment
kubectl get pods -n flux-system -l app.kubernetes.io/name=xray-proxy
kubectl get svc -n flux-system -l app.kubernetes.io/name=xray-proxy
```

#### Option B: Flux GitOps Deployment

Create a Flux HelmRelease:

```yaml
# flux-helmrelease.yaml
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: xray-proxy
  namespace: flux-system
spec:
  interval: 10m
  chart:
    spec:
      chart: ./xray-proxy
      sourceRef:
        kind: GitRepository
        name: kube-socks5
        namespace: flux-system
      interval: 5m
  values:
    replicaCount: 1
    image:
      repository: teddysun/xray
      tag: "1.8.24"
    xray:
      socks5:
        enabled: true
        port: 1080
        auth: "noauth"
      reality:
        enabled: true
        port: 443
        dest: "www.microsoft.com:443"
        serverNames:
          - "www.microsoft.com"
        privateKey: "YOUR_PRIVATE_KEY"
        publicKey: "YOUR_PUBLIC_KEY"
        shortIds:
          - "YOUR_SHORT_ID_1"
          - "YOUR_SHORT_ID_2"
        clients:
          - id: "YOUR_CLIENT_UUID_1"
            flow: "xtls-rprx-vision"
```

Apply the HelmRelease:

```bash
kubectl apply -f flux-helmrelease.yaml
```

### 5. Verify Deployment

```bash
# Check pod status
kubectl get pods -n flux-system -l app.kubernetes.io/name=xray-proxy

# Check logs
kubectl logs -n flux-system -l app.kubernetes.io/name=xray-proxy

# Check service
kubectl get svc -n flux-system xray-proxy

# Port forward for testing
kubectl port-forward -n flux-system svc/xray-proxy 1080:1080 8443:443
```

## Configuration Options

### Service Types

#### ClusterIP (Default)
```yaml
service:
  type: ClusterIP
```
- Internal cluster access only
- Use with Cloudflare Tunnel or ingress

#### NodePort
```yaml
service:
  type: NodePort
  socks5NodePort: 31080
  realityNodePort: 31443
```
- External access via node IPs
- Ports 30000-32767 range

#### LoadBalancer
```yaml
service:
  type: LoadBalancer
  loadBalancerIP: "1.2.3.4"
  loadBalancerSourceRanges:
    - "10.0.0.0/8"
```
- Cloud provider load balancer
- External IP assignment

### Security Configuration

#### SOCKS5 Authentication
```yaml
xray:
  socks5:
    auth: "password"
    accounts:
      - user: "admin"
        pass: "secure_password"
```

#### Reality Target Domains
Choose reliable HTTPS websites:
- `www.microsoft.com:443`
- `www.cloudflare.com:443`
- `www.apple.com:443`
- `www.google.com:443`

### Resource Management

```yaml
resources:
  limits:
    cpu: 1000m
    memory: 1Gi
  requests:
    cpu: 200m
    memory: 256Mi
```

## Client Configuration

### SOCKS5 Proxy Setup

**Browser Configuration:**
1. Open browser proxy settings
2. Set SOCKS5 proxy:
   - Host: `cluster-ip` or `localhost` (if port-forwarded)
   - Port: `1080`
   - Username/Password: If authentication enabled

**Command Line:**
```bash
# Using curl with SOCKS5 proxy
curl --socks5 localhost:1080 https://httpbin.org/ip

# Using ssh with SOCKS5 proxy
ssh -o ProxyCommand="nc -X 5 -x localhost:1080 %h %p" user@remote-host
```

### VLESS+Reality Client

**Xray Client Configuration:**
```json
{
  "outbounds": [
    {
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "your-server-ip",
            "port": 443,
            "users": [
              {
                "id": "12345678-1234-1234-1234-123456789abc",
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
          "shortId": "a1b2c3d4e5f6g7h8",
          "publicKey": "yG02mDZVkGnKs8lrx7cBhw8p7yKpQFWgOaZpZQKqHhk"
        }
      }
    }
  ]
}
```

## Testing

### SOCKS5 Proxy Test

```bash
# Port forward
kubectl port-forward -n flux-system svc/xray-proxy 1080:1080

# Test connection
curl --socks5 localhost:1080 https://httpbin.org/ip
```

### VLESS+Reality Test

```bash
# Port forward
kubectl port-forward -n flux-system svc/xray-proxy 8443:443

# Test with xray client (requires xray client configuration)
xray run -config client-config.json
```

## Monitoring

### Enable Metrics

```yaml
monitoring:
  enabled: true
  port: 8080
```

### Prometheus Integration

```yaml
# ServiceMonitor for Prometheus
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: xray-proxy
  namespace: flux-system
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: xray-proxy
  endpoints:
  - port: metrics
    path: /stats/prometheus
```

## Troubleshooting

### Common Issues

1. **Pod CrashLoopBackOff**
   ```bash
   kubectl describe pod -n flux-system -l app.kubernetes.io/name=xray-proxy
   kubectl logs -n flux-system -l app.kubernetes.io/name=xray-proxy
   ```

2. **Connection Refused**
   - Check service endpoints: `kubectl get endpoints -n flux-system xray-proxy`
   - Verify port forwarding: `kubectl port-forward -n flux-system svc/xray-proxy 1080:1080`

3. **Reality Connection Fails**
   - Verify target domain accessibility
   - Check Reality keys match between server and client
   - Ensure SNI matches serverNames configuration

### Debug Commands

```bash
# Check configuration
kubectl get configmap -n flux-system xray-proxy-config -o yaml

# Check secrets
kubectl get secret -n flux-system xray-proxy-secret -o yaml

# Test network connectivity
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- bash
```

## Maintenance

### Updating

```bash
# Update Helm chart
helm upgrade xray-proxy ./xray-proxy -f my-values.yaml -n flux-system

# Check rollout status
kubectl rollout status deployment/xray-proxy -n flux-system
```

### Backup Configuration

```bash
# Export current configuration
helm get values xray-proxy -n flux-system > xray-proxy-backup.yaml

# Export Kubernetes resources
kubectl get all -n flux-system -l app.kubernetes.io/name=xray-proxy -o yaml > k8s-backup.yaml
```

### Scaling

```bash
# Scale replicas
kubectl scale deployment xray-proxy -n flux-system --replicas=3

# Or update values.yaml
helm upgrade xray-proxy ./xray-proxy -f my-values.yaml --set replicaCount=3 -n flux-system
```

## Security Best Practices

1. **Rotate Keys Regularly**: Generate new Reality keys monthly
2. **Use Strong Passwords**: For SOCKS5 authentication
3. **Network Policies**: Restrict pod-to-pod communication
4. **Resource Limits**: Prevent resource exhaustion
5. **Monitor Access**: Enable logging and monitoring
6. **Update Images**: Keep Xray image updated

## Integration with Cloudflare Tunnel

Since you have Cloudflare Tunnel running externally, configure it to route traffic to your Xray service:

```yaml
# cloudflared config.yaml
tunnel: your-tunnel-id
credentials-file: /path/to/credentials.json

ingress:
  - hostname: proxy.yourdomain.com
    service: http://xray-proxy.flux-system.svc.cluster.local:1080
  - hostname: reality.yourdomain.com
    service: tcp://xray-proxy.flux-system.svc.cluster.local:443
  - service: http_status:404
```

This allows external access to your Xray proxy through Cloudflare's secure tunnel.