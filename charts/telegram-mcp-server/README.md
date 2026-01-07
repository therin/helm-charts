# Telegram MCP Server Helm Chart

A Helm chart for deploying [Telegram MCP Server](https://github.com/therin/telegram-mcp-server) - an MCP server that allows AI assistants to interact with your Telegram account.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- Telegram API credentials from [my.telegram.org](https://my.telegram.org/apps)

## Installation

### Quick Start (Demo Mode)

Deploy without Telegram credentials to preview the dashboard:

```bash
helm install telegram-mcp-server oci://ghcr.io/therin/helm-charts/telegram-mcp-server \
  --set demoMode=true
```

### Production Deployment

Telegram's MTProto authentication requires interactive input (verification code, 2FA password) on first login. Since Kubernetes pods don't support interactive terminals, you must **authenticate locally first**, then deploy the session to your cluster.

#### Step 1: Local Authentication

```bash
# Clone and run locally
git clone https://github.com/therin/telegram-mcp-server
cd telegram-mcp-server

# Configure credentials
cat > .env <<EOF
TELEGRAM_API_ID=your_api_id
TELEGRAM_API_HASH=your_api_hash
TELEGRAM_PHONE_NUMBER=+1234567890
EOF

# Start server and complete interactive auth
npm install
npm start

# You will be prompted for:
#   1. Verification code (sent to your Telegram app)
#   2. 2FA password (if enabled)
#
# After successful login, session is saved to ./data/session.json
```

#### Step 2: Create Kubernetes Secrets

```bash
# Session secret (contains authenticated session)
kubectl create secret generic telegram-session \
  --from-file=session.json=./data/session.json

# Credentials secret
kubectl create secret generic telegram-creds \
  --from-literal=api-id=YOUR_API_ID \
  --from-literal=api-hash=YOUR_API_HASH \
  --from-literal=phone-number=+1234567890
```

#### Step 3: Deploy with Helm

```bash
helm install telegram-mcp-server oci://ghcr.io/therin/helm-charts/telegram-mcp-server \
  --set telegram.existingSecret=telegram-creds \
  --set session.existingSecret=telegram-session \
  --set persistence.storageClass=longhorn
```

## How It Works

```
┌─────────────────────────────────────────────────────────────┐
│ LOCAL (one-time setup)                                      │
│                                                             │
│  1. npm start                                               │
│  2. Enter verification code                                 │
│  3. Enter 2FA password (if enabled)                         │
│  4. Session saved to ./data/session.json                    │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ KUBERNETES SECRETS                                          │
│                                                             │
│  telegram-session: session.json file                        │
│  telegram-creds: api-id, api-hash, phone-number             │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ POD STARTUP                                                 │
│                                                             │
│  [init: copy-session] ──► copies session.json to PVC        │
│          │                (skipped if already exists)       │
│          ▼                                                  │
│  [main: telegram-mcp-server] ──► uses existing session      │
│                                  no interactive auth needed │
└─────────────────────────────────────────────────────────────┘
```

The init container only copies the session on first deployment. On subsequent restarts, the existing session on the PVC is preserved.

## Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `image.repository` | Container image | `ghcr.io/therin/telegram-mcp-server` |
| `image.tag` | Image tag | `main` |
| `image.pullPolicy` | Pull policy | `Always` |
| `telegram.existingSecret` | Secret with `api-id`, `api-hash`, `phone-number` keys | `""` |
| `telegram.apiId` | Telegram API ID (if not using existingSecret) | `""` |
| `telegram.apiHash` | Telegram API Hash (if not using existingSecret) | `""` |
| `telegram.phoneNumber` | Phone number with country code | `""` |
| `session.existingSecret` | Secret containing `session.json` file | `""` |
| `demoMode` | Run with mock data (no credentials needed) | `false` |
| `service.type` | Kubernetes service type | `ClusterIP` |
| `service.port` | Service port | `8080` |
| `persistence.enabled` | Enable persistent storage | `true` |
| `persistence.size` | PVC size | `1Gi` |
| `persistence.storageClass` | Storage class name | `""` |
| `resources.requests.cpu` | CPU request | `100m` |
| `resources.requests.memory` | Memory request | `128Mi` |
| `resources.limits.cpu` | CPU limit | `500m` |
| `resources.limits.memory` | Memory limit | `512Mi` |

## Storage & Data Access

### PVC Layout

The persistent volume is mounted at `/app/data/` and contains:

```
/app/data/
├── session.json      # Telegram auth session
├── messages.db       # SQLite database with synced messages
├── messages.db-wal   # SQLite Write-Ahead Log
└── messages.db-shm   # SQLite shared memory file
```

### Storage Configuration

| Setting | Value | Purpose |
|---------|-------|---------|
| `accessModes` | `ReadWriteOnce` | Single pod access (SQLite requirement) |
| `strategy.type` | `Recreate` | Ensures old pod stops before new starts (RWO constraint) |
| `fsGroup: 1000` | node user's GID | Ensures PVC is writable by non-root container |
| `helm.sh/resource-policy: keep` | Annotation | PVC survives `helm uninstall` (data protection) |

The `Recreate` deployment strategy is required because SQLite doesn't support concurrent access from multiple processes.

### Accessing the SQLite Database

**Option 1: Built-in Dashboard**

The server includes a database browser UI:

```bash
kubectl port-forward svc/telegram-mcp-server 8080:8080
open http://localhost:8080/
```

**Option 2: Copy DB locally**

```bash
# Get pod name
POD=$(kubectl get pods -l app.kubernetes.io/name=telegram-mcp-server -o jsonpath='{.items[0].metadata.name}')

# Copy to local machine
kubectl cp $POD:/app/data/messages.db ./messages.db

# Query with any SQLite client
sqlite3 ./messages.db "SELECT * FROM messages LIMIT 10;"
```

**Option 3: Query from within the pod**

```bash
# Using Node.js (sqlite3 binary not included in image)
kubectl exec deployment/telegram-mcp-server -- node -e "
  const Database = require('better-sqlite3');
  const db = new Database('/app/data/messages.db', { readonly: true });
  console.log(db.prepare('SELECT COUNT(*) as count FROM messages').get());
"
```

### Uploading a Large Database to the PVC

For large databases (e.g., 10GB+), `kubectl cp` can be slow and unreliable. Here are better options:

#### Setup: Create a Transfer Pod

First, scale down the main deployment and create a temporary pod with the PVC mounted:

```bash
# Scale down to release the PVC (RWO can only be mounted by one pod)
kubectl scale deployment telegram-mcp-server --replicas=0

# Create transfer pod
kubectl run transfer --image=alpine --restart=Never --overrides='
{
  "spec": {
    "containers": [{
      "name": "transfer",
      "image": "alpine",
      "command": ["sleep", "infinity"],
      "volumeMounts": [{
        "name": "data",
        "mountPath": "/data"
      }]
    }],
    "volumes": [{
      "name": "data",
      "persistentVolumeClaim": {
        "claimName": "telegram-mcp-server-data"
      }
    }]
  }
}'

# Wait for pod to be ready
kubectl wait --for=condition=Ready pod/transfer --timeout=60s
```

#### Option A: HTTP Download (Easiest if pod can reach your machine)

```bash
# On your local machine - serve the database file
cd /path/to/db
python3 -m http.server 8000

# In the transfer pod - download it
kubectl exec transfer -- wget -O /data/messages.db http://YOUR_LOCAL_IP:8000/messages.db
```

#### Option B: Netcat Streaming (Fastest on local network)

```bash
# Terminal 1: Port-forward to the transfer pod
kubectl exec transfer -- apk add --no-cache netcat-openbsd
kubectl port-forward pod/transfer 9999:9999

# Terminal 2: Stream the database (with progress via pv)
pv messages.db | nc localhost 9999

# In the pod (run before starting the stream)
kubectl exec transfer -- sh -c "nc -l -p 9999 > /data/messages.db"
```

#### Option C: kubectl cp with Compression (Simpler but slower)

```bash
# Compress locally first
gzip -k messages.db

# Copy compressed file
kubectl cp messages.db.gz transfer:/data/messages.db.gz

# Decompress in pod
kubectl exec transfer -- gunzip /data/messages.db.gz
```

#### Option D: Rsync over kubectl exec

```bash
# Install rsync in transfer pod
kubectl exec transfer -- apk add --no-cache rsync

# Use rsync with kubectl as transport
rsync -av --progress -e 'kubectl exec -i transfer --' messages.db rsync:/data/messages.db
```

#### Cleanup After Transfer

```bash
# Fix ownership (node user = UID 1000)
kubectl exec transfer -- chown 1000:1000 /data/messages.db

# Delete the transfer pod
kubectl delete pod transfer

# Scale the deployment back up
kubectl scale deployment telegram-mcp-server --replicas=1
```

## Accessing the Server

```bash
# Port forward to access locally
kubectl port-forward svc/telegram-mcp-server 8080:8080

# Dashboard UI
open http://localhost:8080/

# MCP endpoint (for Claude Desktop, Cursor, etc.)
# http://localhost:8080/mcp
```

## Session Management

### Session Expiration

Telegram sessions can expire if:
- You revoke it from another client (Settings → Devices)
- Account is inactive for extended periods
- Telegram invalidates it for security reasons

If the session expires, repeat the local authentication process and update the secret:

```bash
kubectl delete secret telegram-session
kubectl create secret generic telegram-session \
  --from-file=session.json=./data/session.json

# Restart the pod to pick up new session
kubectl rollout restart deployment telegram-mcp-server
```

### Forcing Session Refresh

To force the init container to re-copy the session from the secret:

```bash
# Delete the existing session from the PVC
kubectl exec deployment/telegram-mcp-server -- rm /app/data/session.json

# Restart to trigger init container
kubectl rollout restart deployment telegram-mcp-server
```

## Troubleshooting

### Pod stuck in Init

Check init container logs:
```bash
kubectl logs deployment/telegram-mcp-server -c copy-session
```

### Authentication errors

If you see `AUTH_KEY_UNREGISTERED` or similar errors, your session has expired. Re-authenticate locally and update the secret.

### Rate limiting

Telegram has strict rate limits. If you see `FLOOD_WAIT` errors, the server will automatically wait and retry. For bulk operations, use the Takeout API via the `runTakeoutBackfill` tool.
