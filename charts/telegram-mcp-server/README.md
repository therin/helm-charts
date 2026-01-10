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

#### Step 2: Create Kubernetes Secret

```bash
# Credentials secret (must be named 'telegram-creds')
kubectl create secret generic telegram-creds \
  --from-literal=api-id=YOUR_API_ID \
  --from-literal=api-hash=YOUR_API_HASH \
  --from-literal=phone-number=+1234567890
```

#### Step 3: Deploy with Helm (paused)

```bash
helm install telegram-mcp-server oci://ghcr.io/therin/helm-charts/telegram-mcp-server \
  --set replicaCount=0
```

#### Step 4: Copy Session to PVC

The session file is too large for K8s secrets (~70MB with peer cache, limit is 3MB), so copy it directly to the PVC:

```bash
# Create a temporary pod to copy the session file
kubectl run pvc-copy --rm -i --restart=Never --image=alpine \
  --overrides='{
    "spec": {
      "containers": [{
        "name": "pvc-copy",
        "image": "alpine",
        "command": ["sh", "-c", "cp -v /source/session.json /dest/ && chown 1000:1000 /dest/session.json && ls -lh /dest/"],
        "volumeMounts": [
          {"name": "source", "mountPath": "/source", "readOnly": true},
          {"name": "dest", "mountPath": "/dest"}
        ]
      }],
      "volumes": [
        {"name": "source", "hostPath": {"path": "/path/to/local/data", "type": "Directory"}},
        {"name": "dest", "persistentVolumeClaim": {"claimName": "telegram-mcp-server-data"}}
      ]
    }
  }'
```

If your source is on NFS, replace the hostPath volume with:
```yaml
{"name": "source", "nfs": {"server": "YOUR_NFS_SERVER", "path": "/your/nfs/path"}}
```

#### Step 5: Scale Up

```bash
kubectl scale deployment telegram-mcp-server --replicas=1
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
│ COPY TO PVC (session.json is ~70MB, too large for secrets)  │
│                                                             │
│  kubectl run pvc-copy ... (see Step 4 above)                │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ KUBERNETES SECRET                                           │
│                                                             │
│  telegram-creds: api-id, api-hash, phone-number             │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ POD STARTUP                                                 │
│                                                             │
│  [main: telegram-mcp-server] ──► uses session from PVC      │
│                                  no interactive auth needed │
└─────────────────────────────────────────────────────────────┘
```

The session file persists on the PVC across pod restarts.

## Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of replicas | `1` |
| `image.repository` | Container image | `ghcr.io/therin/telegram-mcp-server` |
| `image.tag` | Image tag | `main` |
| `image.pullPolicy` | Pull policy | `Always` |
| `telegram.existingSecret` | Secret with `api-id`, `api-hash`, `phone-number` keys | `telegram-creds` |
| `demoMode` | Run with mock data (no credentials needed) | `false` |
| `service.type` | Kubernetes service type | `LoadBalancer` |
| `service.port` | Service port | `8080` |
| `persistence.size` | PVC size | `30Gi` |
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
| `storageClassName` | `longhorn` | Hardcoded to use Longhorn storage |
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

#### Setup: Scale Down First

```bash
# Scale down to release the PVC (RWO can only be mounted by one pod)
kubectl scale deployment telegram-mcp-server --replicas=0
```

#### Option A: Direct Copy from NFS (Recommended)

If your database is on NFS storage, copy directly without intermediate steps:

```bash
kubectl run pvc-migrator --rm -i --restart=Never --image=alpine \
  --overrides='{
    "spec": {
      "containers": [{
        "name": "migrator",
        "image": "alpine",
        "command": ["sh", "-c", "cp -v /source/messages.db /dest/ && chown 1000:1000 /dest/messages.db && ls -lh /dest/"],
        "volumeMounts": [
          {"name": "source", "mountPath": "/source", "readOnly": true},
          {"name": "dest", "mountPath": "/dest"}
        ]
      }],
      "volumes": [
        {"name": "source", "nfs": {"server": "YOUR_NFS_SERVER", "path": "/your/nfs/path"}},
        {"name": "dest", "persistentVolumeClaim": {"claimName": "telegram-mcp-server-data"}}
      ]
    }
  }'
```

#### Option B: Using a Transfer Pod

Create a temporary pod with the PVC mounted for more complex transfers:

```bash
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

#### Option C: HTTP Download

```bash
# On your local machine - serve the database file
cd /path/to/db
python3 -m http.server 8000

# In the transfer pod - download it
kubectl exec transfer -- wget -O /data/messages.db http://YOUR_LOCAL_IP:8000/messages.db
```

#### Option D: kubectl cp with Compression

```bash
# Compress locally first
gzip -k messages.db

# Copy compressed file
kubectl cp messages.db.gz transfer:/data/messages.db.gz

# Decompress in pod
kubectl exec transfer -- gunzip /data/messages.db.gz
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

If the session expires, repeat the local authentication process and copy the new session to the PVC:

```bash
# Scale down first
kubectl scale deployment telegram-mcp-server --replicas=0

# Copy new session.json to PVC (see Step 4 in Installation)
# ...

# Scale back up
kubectl scale deployment telegram-mcp-server --replicas=1
```

## Troubleshooting

### Authentication errors

If you see `AUTH_KEY_UNREGISTERED` or similar errors, your session has expired. Re-authenticate locally and update the secret.

### Rate limiting

Telegram has strict rate limits. If you see `FLOOD_WAIT` errors, the server will automatically wait and retry. For bulk operations, use the Takeout API via the `runTakeoutBackfill` tool.
