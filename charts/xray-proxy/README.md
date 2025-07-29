# Xray Proxy Helm Chart (Simplified)

A simplified Kubernetes Helm chart for deploying Xray proxy server with dual protocol support (SOCKS5 and VLESS+Reality).

## Overview

This simplified Helm chart deploys an Xray proxy server that supports:

- **SOCKS5 proxy** for standard proxy connections (port 1080)
- **VLESS+Reality protocol** for advanced traffic obfuscation (port 443)

### Key Simplifications

- **No Service Account**: Runs without unnecessary service account permissions
- **Plain JSON Configuration**: Uses native Xray JSON config format instead of complex Helm templating
- **Minimal Values**: Simplified values.yaml with only essential settings
- **Direct Configuration**: Easy to customize using standard Xray configuration from [XTLS/Xray-examples](https://github.com/XTLS/Xray-examples)

## Prerequisites

- Kubernetes 1.19+
- Helm 3.2.0+

## Quick Start

### 1. Generate Required Keys

Generate the necessary keys for VLESS+Reality:

```bash
# Generate UUID for client
uuidgen

# Generate Reality key pair
xray x25519
```

Or use the provided script:

```bash
# Generate keys automatically
./generate-keys.sh

# Generate keys and create my-values.yaml
./generate-keys.sh --create-values
```

### 2. Configure Your Values

Create a `my-values.yaml` file and update the `xrayConfig` section with your generated keys:

```yaml
xrayConfig: |
  {
    "log": {
      "loglevel": "info"
    },
    "inbounds": [
      {
        "tag": "socks5",
        "port": 1080,
        "protocol": "socks",
        "settings": {
          "auth": "noauth",
          "udp": true
        }
      },
      {
        "tag": "vless-reality",
        "port": 443,
        "protocol": "vless",
        "settings": {
          "clients": [
            {
              "id": "YOUR_GENERATED_UUID_HERE",
              "flow": "xtls-rprx-vision"
            }
          ],
          "decryption": "none"
        },
        "streamSettings": {
          "network": "tcp",
          "security": "reality",
          "realitySettings": {
            "show": false,
            "dest": "www.microsoft.com:443",
            "xver": 0,
            "serverNames": [
              "www.microsoft.com"
            ],
            "privateKey": "YOUR_PRIVATE_KEY_HERE",
            "shortIds": [
              "YOUR_SHORT_ID_HERE"
            ]
          }
        }
      }
    ],
    "outbounds": [
      {
        "protocol": "freedom",
        "tag": "direct"
      }
    ],
    "routing": {
      "rules": [
        {
          "type": "field",
          "inboundTag": ["socks5", "vless-reality"],
          "outboundTag": "direct"
        }
      ]
    }
  }
```

### 3. Install the Chart

```bash
# Install with custom values
helm install xray-proxy ./charts/xray-proxy -f my-values.yaml

# Or install in a specific namespace
helm install xray-proxy ./charts/xray-proxy -f my-values.yaml -n proxy-system --create-namespace
```

### Common Issues

1. **Configuration Validation**: Test your JSON config with `xray test -config config.json`
2. **Port Conflicts**: Ensure ports 1080 and 443 are available
3. **Reality Target**: Verify the target domain (dest) is accessible from your cluster

## Configuration References

Based on research from:

- [Official Xray Documentation](https://xtls.github.io/config/)
- [Xray Examples Repository](https://github.com/XTLS/Xray-examples)
- [Reality Protocol Guide](https://github.com/XTLS/REALITY)
- [VLESS-TCP-XTLS-Vision-REALITY Examples](https://git.esin.io/github/Xray-examples/src/branch/main/VLESS-TCP-XTLS-Vision-REALITY/REALITY.ENG.md)
