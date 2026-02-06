# Orqus Releases

Binary releases and Docker images for Orqus Chain.

## Downloads

| Component | Binary | Docker Image |
|-----------|--------|--------------|
| orqus-reth | [Releases](https://github.com/orqusio/orqus-releases/releases) | `ghcr.io/orqusio/orqus-reth` |
| orqusbft | [Releases](https://github.com/orqusio/orqus-releases/releases) | `ghcr.io/orqusio/orqusbft` |

## Quick Start

### One-click Install

The installer supports two modes: **binary** and **docker**.

#### Binary Mode (Linux amd64 only)

```bash
# Install with binaries
curl -sSL https://raw.githubusercontent.com/orqusio/orqus-releases/main/install.sh | bash

# Start the chain
~/.orqus/start.sh

# Stop the chain
~/.orqus/stop.sh
```

#### Docker Mode (Recommended for macOS/arm64)

```bash
# Install with Docker
curl -sSL https://raw.githubusercontent.com/orqusio/orqus-releases/main/install.sh | INSTALL_MODE=docker bash

# Start the chain
~/.orqus/start.sh

# Stop the chain
~/.orqus/stop.sh

# View logs
docker compose -f ~/.orqus/docker-compose.yml logs -f
```

#### Upgrade Existing Installation

To upgrade an existing installation to the latest version:

```bash
# Method 1: Use local install script (recommended)
~/.orqus/install.sh upgrade

# Method 2: Fetch latest installer and upgrade
curl -sSL https://raw.githubusercontent.com/orqusio/orqus-releases/main/install.sh | bash -s -- upgrade
```

The upgrade process will:
- Detect installation mode (binary or docker)
- Stop running services
- Download/pull latest binaries or Docker images
- Restart services (Docker mode only)
- Preserve all data and configuration

**Note:** For binary mode, you need to manually restart after upgrade:
```bash
~/.orqus/start.sh
```

#### Join Existing Network

To connect to an existing Orqus network (testnet/mainnet), you need:
1. **CometBFT peers** - for consensus layer sync
2. **Reth peers** - for execution layer sync
3. **Genesis file** - must match the existing network

The installer will automatically fetch genesis from the first peer if `NODE_TYPE` is not `validator`.

```bash
# Get node_id from existing sentry nodes
# On sentry node: curl -s http://localhost:26657/status | jq -r '.result.node_info.id'

# Install and connect to network
export NODE_TYPE=rpc
export INSTALL_MODE=docker
export PERSISTENT_PEERS="<node_id>@<sentry_ip>:26656"
export RETH_TRUSTED_PEERS="enode://<pubkey>@<sentry_ip>:30303"
curl -sSL https://raw.githubusercontent.com/orqusio/orqus-releases/main/install.sh | bash
```

**Explicit genesis download** (if auto-fetch fails):
```bash
# Specify genesis URL directly
export GENESIS_URL="http://<sentry_ip>:26657/genesis"
# Or use a direct file URL
export GENESIS_URL="https://example.com/genesis.json"
```

Example:
```bash
# Set environment variables first
export NODE_TYPE=rpc
export INSTALL_MODE=docker
export PERSISTENT_PEERS="a1b2c3d4e5@10.0.1.10:26656,f6g7h8i9j0@10.0.1.11:26656"
export RETH_TRUSTED_PEERS="enode://5a3d42...@10.0.1.10:30303,enode://59949a...@10.0.1.11:30303"

# Then run installer
curl -sSL https://raw.githubusercontent.com/orqusio/orqus-releases/main/install.sh | bash
```

Alternative (single line with pipe to bash):
```bash
curl -sSL https://raw.githubusercontent.com/orqusio/orqus-releases/main/install.sh | \
  NODE_TYPE=rpc INSTALL_MODE=docker \
  PERSISTENT_PEERS="a1b2c3d4e5@10.0.1.10:26656" \
  RETH_TRUSTED_PEERS="enode://5a3d42...@10.0.1.10:30303" \
  bash
```

**Requirements:**
- Binary mode: Linux amd64
- Docker mode: Docker + Docker Compose

The installer will:
- Download binaries OR pull Docker images
- Download genesis.json with system contracts
- Generate all necessary configuration files
- Initialize the chain with genesis state
- Create start/stop scripts

**Environment variables:**
```bash
# Custom installation directory
ORQUS_INSTALL_DIR=/opt/orqus

# Installation mode (binary or docker)
INSTALL_MODE=docker

# Custom Docker image tag
DOCKER_TAG=v1.0.0

# Node name
ORQUS_MONIKER=my-node

# Node type (validator, sentry, rpc, archive)
NODE_TYPE=rpc

# P2P configuration (for joining existing network)
PERSISTENT_PEERS="node_id@ip:26656,node_id@ip:26656"
SEEDS="node_id@seed:26656"

# Reth P2P peers (for execution layer sync)
RETH_TRUSTED_PEERS="enode://pubkey@ip:30303,enode://pubkey@ip:30303"

# CometBFT genesis (for joining existing network)
# Auto-fetched from first peer if NODE_TYPE != validator
GENESIS_URL="http://sentry_ip:26657/genesis"

# Reth genesis (for joining existing network)
# If not set, downloads from GitHub releases
RETH_GENESIS_URL="http://sentry_ip:8888/genesis.json"

# Custom ports
RETH_HTTP_PORT=8545
RETH_WS_PORT=8546
RETH_ENGINE_PORT=8551
RETH_P2P_PORT=30303
COMETBFT_P2P_PORT=26656
COMETBFT_RPC_PORT=26657
```

### Node Types

| Type | Description | Use Case |
|------|-------------|----------|
| `validator` | Full validator with signing keys (default) | Block production |
| `sentry` | Protects validator, public P2P | Validator protection |
| `rpc` | Public RPC endpoint | API services |
| `archive` | Full history node | Historical queries |

**Configuration differences:**

| Setting | validator | sentry | rpc | archive |
|---------|-----------|--------|-----|---------|
| pex (peer exchange) | false | true | true | true |
| slashing | configurable | disabled | disabled | disabled |
| retainBlocks | all | ~1 day | ~1 day | all |

Example:
```bash
# Deploy RPC node
curl -sSL https://raw.githubusercontent.com/orqusio/orqus-releases/main/install.sh | \
  NODE_TYPE=rpc INSTALL_MODE=docker \
  PERSISTENT_PEERS="abc@10.0.1.10:26656" \
  bash
```

### Manual Download

```bash
# Pull Docker images
docker pull ghcr.io/orqusio/orqus-reth:latest
docker pull ghcr.io/orqusio/orqusbft:latest

# Or download binaries (Linux amd64 only)
curl -LO https://github.com/orqusio/orqus-releases/releases/latest/download/orqus-reth-linux-amd64
curl -LO https://github.com/orqusio/orqus-releases/releases/latest/download/orqusbft-linux-amd64
curl -LO https://github.com/orqusio/orqus-releases/releases/latest/download/genesis.json
chmod +x orqus-reth-linux-amd64 orqusbft-linux-amd64
```

---

# Node Architecture

Orqus Chain uses a modular architecture with three main components running as containers per node.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         Orqus Node                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────┐     ABCI      ┌─────────────┐                 │
│  │  CometBFT   │◄─────────────►│  orqusbft   │                 │
│  │ (Consensus) │   :8080       │  (Bridge)   │                 │
│  │             │               │             │                 │
│  │  P2P:26656  │               │             │                 │
│  │  RPC:26657  │               └──────┬──────┘                 │
│  └─────────────┘                      │                        │
│                                       │ Engine API             │
│                                       │ :8551 (JWT Auth)       │
│                                       ▼                        │
│                              ┌─────────────┐                   │
│                              │ orqus-reth  │                   │
│                              │ (Execution) │                   │
│                              │             │                   │
│                              │  RPC:8545   │                   │
│                              │  WS:8546    │                   │
│                              │  P2P:30303  │                   │
│                              └─────────────┘                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Components

### 1. CometBFT (Consensus Layer)

Byzantine Fault Tolerant consensus engine based on Tendermint.

| Port | Protocol | Description |
|------|----------|-------------|
| 26656 | TCP | P2P communication |
| 26657 | HTTP | RPC endpoint |
| 26660 | HTTP | Prometheus metrics |

**Key Configuration** (`config.toml`):
```toml
[consensus]
timeout_propose = "3s"
timeout_prevote = "1s"
timeout_precommit = "1s"
timeout_commit = "1s"

[p2p]
max_packet_msg_payload_size = 4096  # Increase if "message exceeds max size" errors
```

### 2. orqusbft (ABCI Bridge)

Go application bridging CometBFT consensus to orqus-reth execution layer via Engine API.

| Port | Protocol | Description |
|------|----------|-------------|
| 8080 | TCP | ABCI proxy (CometBFT connects here) |
| 8090 | HTTP | Health check & metrics |

**Block Production Flow**:
1. CometBFT reaches consensus on block height
2. orqusbft receives ABCI callbacks (BeginBlock, DeliverTx, EndBlock, Commit)
3. orqusbft calls Engine API sequence:
   - `engine_forkchoiceUpdatedV3` (prepare)
   - `engine_getPayloadV3` (get block)
   - `engine_newPayloadV3` (submit block)
   - `engine_forkchoiceUpdatedV3` (finalize)

**Configuration** (`config.yaml`):
```yaml
ethereum:
  endpoint: "http://localhost:8545"
  engineAPI: "http://localhost:8551"
  jwtSecret: "/path/to/jwt.hex"

cometbft:
  endpoint: "http://localhost:26657"
  homeDir: "/data/cometbft"

consensus:
  epochLength: 270      # blocks per epoch
  blockPeriod: 2        # seconds per block
```

### 3. orqus-reth (Execution Layer)

Rust execution client based on Reth with custom precompiles for stablecoin gas payments.

| Port | Protocol | Description |
|------|----------|-------------|
| 8545 | HTTP | JSON-RPC endpoint |
| 8546 | WebSocket | WebSocket RPC |
| 8551 | HTTP | Engine API (JWT authenticated) |
| 30303 | TCP/UDP | P2P (devp2p) |
| 9001 | HTTP | Prometheus metrics |

**Custom Precompiles**:

| Address | Name | Description |
|---------|------|-------------|
| `0x6ffc000000000000000000000000000000000000` | OIP20 Factory | Create stablecoin tokens |
| `0x6ffe000000000000000000000000000000000000` | Fee Manager | Gas fee payment with stablecoins |
| `0x6f6f000000000000000000000000000000000000` | Token Rate Oracle | Exchange rates |
| `0x6f20000000000000000000000000000000000000` | Inner USD | Default fee token |
| `0x6f45100000000000000000000000000000000000` | OIP451 Registry | Precompile registry |
| `0x6f45110000000000000000000000000000000000` | OIP4511 | Day limit precompile |
| `0x6f45120000000000000000000000000000000000` | OIP4512 | Token limit precompile |

**System Contracts**:

| Address | Name | Description |
|---------|------|-------------|
| `0x6f00000000000000000000000000000000001000` | Validator Registry | Validator management |
| `0x6f00000000000000000000000000000000001004` | Validator Set Commit | Epoch transitions |

## Chain Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| Chain ID | 153871 | Network identifier |
| Block Time | ~2s | Target block interval |
| Epoch Length | 270 blocks | ~9 minutes per epoch |
| Gas Limit | 30M | Per-block gas limit |
| Base Fee | 200 gwei | Fixed base fee |

## Data Flow

```
User Transaction
       │
       ▼
┌──────────────┐
│  orqus-reth  │ ◄── Receives tx via JSON-RPC :8545
│   (mempool)  │
└──────┬───────┘
       │
       ▼
┌──────────────┐
│   orqusbft   │ ◄── Queries pending txs
│              │
└──────┬───────┘
       │ Proposes block
       ▼
┌──────────────┐
│   CometBFT   │ ◄── BFT consensus (2/3+ validators)
│              │
└──────┬───────┘
       │ Commit
       ▼
┌──────────────┐
│   orqusbft   │ ◄── ABCI Commit callback
│              │
└──────┬───────┘
       │ engine_newPayload + engine_forkchoiceUpdated
       ▼
┌──────────────┐
│  orqus-reth  │ ◄── Executes block, updates state
│              │
└──────────────┘
```

## Deployment

### Kubernetes (Recommended)

Use [orqus-helm](https://github.com/orqusio/orqus-helm) for production deployments:

```bash
helm upgrade --install orqus-node ./charts/orqus-node \
  -f services/orqus-node/helm.yaml \
  -f services/orqus-node/prod/helm.yaml \
  -n orqus-prod --create-namespace
```

### Docker Compose (Development)

```yaml
services:
  orqus-reth:
    image: ghcr.io/orqusio/orqus-reth:latest
    ports:
      - "8545:8545"
      - "8551:8551"
      - "30303:30303"
    volumes:
      - ./data/reth:/data
      - ./jwt.hex:/jwt.hex
    command: >
      node
      --http --http.addr 0.0.0.0
      --authrpc.addr 0.0.0.0 --authrpc.jwtsecret /jwt.hex
      --datadir /data

  orqusbft:
    image: ghcr.io/orqusio/orqusbft:latest
    depends_on:
      - orqus-reth
      - cometbft
    volumes:
      - ./config.yaml:/app/config.yaml
      - ./jwt.hex:/app/jwt.hex
    environment:
      - ORQUSBFT_CONFIG=/app/config.yaml

  cometbft:
    image: cometbft/cometbft:v0.38.15
    ports:
      - "26656:26656"
      - "26657:26657"
    volumes:
      - ./data/cometbft:/cometbft
    command: start --proxy_app=tcp://orqusbft:8080
```

## Troubleshooting

### "message exceeds max size" in CometBFT

Increase `max_packet_msg_payload_size` in CometBFT `config.toml`:

```toml
[p2p]
max_packet_msg_payload_size = 4096
```

### "gas required exceeds allowance (0)" in eth_estimateGas

This occurs when using `--gas-price` with accounts that have low native ETH balance. Orqus uses stablecoin-based gas, so native ETH balance doesn't reflect actual gas allowance.

**Workaround**: Specify explicit `--gas-limit`:
```bash
cast send $CONTRACT "method()" --gas-limit 300000
```

### Engine API connection refused

Ensure orqus-reth is running with Engine API enabled and JWT secret matches:

```bash
# Generate JWT secret
openssl rand -hex 32 > jwt.hex

# Start orqus-reth with Engine API
orqus-reth node --authrpc.addr 0.0.0.0 --authrpc.jwtsecret jwt.hex
```

### Node not syncing / No peers

1. Check if `PERSISTENT_PEERS` is correctly configured:
```bash
# View current config
cat ~/.orqus/data/cometbft/config/config.toml | grep persistent_peers
```

2. Verify peer connectivity:
```bash
# Check connected peers
curl -s http://localhost:26657/net_info | jq '.result.n_peers'
```

3. Ensure firewall allows P2P ports:
   - CometBFT P2P: `26656/tcp`
   - Reth P2P: `30303/tcp+udp`

4. Get node_id from a running sentry:
```bash
curl -s http://<sentry_ip>:26657/status | jq -r '.result.node_info.id'
```

## Related Repositories

- [orqus-reth](https://github.com/orqusio/orqus-reth) - Execution layer source code
- [orqus-bft](https://github.com/orqusio/orqus-bft) - ABCI bridge source code

## License

Apache 2.0
