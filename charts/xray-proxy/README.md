# Xray Proxy Helm Chart (Simplified)

Kubernetes Helm chart for deploying Xray proxy server with dual protocol support (SOCKS5 and VLESS+Reality).

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

### 2. Create Your Configuration

Create a JSON configuration file with your generated keys:

```json
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
            "id": "your-generated-uuid-here",
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
          "privateKey": "your-generated-private-key-here",
          "shortIds": [
            "your-generated-short-id-here"
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

### 3. Create ConfigMap

Create a ConfigMap with your configuration:

```bash
kubectl create configmap xray-config --from-file=config.json=your-config.json --namespace=your-namespace
```

## Configuration References

Based on research from:

- [Official Xray Documentation](https://xtls.github.io/config/)
- [Xray Examples Repository](https://github.com/XTLS/Xray-examples)
- [Reality Protocol Guide](https://github.com/XTLS/REALITY)
- [VLESS-TCP-XTLS-Vision-REALITY Examples](https://git.esin.io/github/Xray-examples/src/branch/main/VLESS-TCP-XTLS-Vision-REALITY/REALITY.ENG.md)
