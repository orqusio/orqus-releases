# Orqus Releases

Binary releases and Docker images for Orqus Chain.

## Quick Start

Peers are auto-fetched based on `NETWORK` — no manual peer configuration needed.

```bash
# Join testnet (binary mode, Linux amd64)
curl -sSL https://raw.githubusercontent.com/orqusio/orqus-releases/main/install.sh | NETWORK=testnet bash

# Docker mode (macOS/arm64)
curl -sSL https://raw.githubusercontent.com/orqusio/orqus-releases/main/install.sh | INSTALL_MODE=docker NETWORK=testnet bash

# RPC node
curl -sSL https://raw.githubusercontent.com/orqusio/orqus-releases/main/install.sh | NODE_TYPE=rpc NETWORK=testnet bash
```

## Node Management

```bash
~/.orqus/orqusctl.sh start          # Start all components
~/.orqus/orqusctl.sh stop           # Stop all components
~/.orqus/orqusctl.sh status         # Check status
~/.orqus/orqusctl.sh logs           # View logs
~/.orqus/orqusctl.sh logs reth      # Single component logs
~/.orqus/orqusctl.sh restart        # Restart
~/.orqus/orqusctl.sh download       # Download & restore snapshot
~/.orqus/orqusctl.sh reset          # Wipe data & re-sync from genesis
```

## Upgrade

```bash
~/.orqus/install.sh upgrade
```

## Reconfigure

Change settings without touching chain data:

```bash
NODE_TYPE=rpc ~/.orqus/install.sh reconfigure
PROFILE=benchmark ~/.orqus/install.sh reconfigure
```

## Node Types

| Type | Description |
|------|-------------|
| `validator` | Full validator with signing keys (default) |
| `rpc` | Public RPC endpoint |
| `archive` | Full history node |

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `NETWORK` | `testnet` | Network to join (`testnet`, `mainnet`) |
| `NODE_TYPE` | `validator` | Node type (`validator`, `rpc`, `archive`) |
| `INSTALL_MODE` | `binary` | Installation mode (`binary`, `docker`) |
| `ORQUS_MONIKER` | `orqus-node` | Node name |
| `PERSISTENT_PEERS` | auto-fetched | CometBFT peers (overrides auto-fetch) |
| `RETH_TRUSTED_PEERS` | auto-fetched | Reth peers (overrides auto-fetch) |
| `PROFILE` | `default` | Performance profile (`default`, `benchmark`) |
| `GENESIS_GAS_LIMIT` | - | Override genesis gas limit (first install only) |

## Architecture

```
CometBFT (Consensus)  <-->  orqusbft (ABCI Bridge)  <-->  orqus-reth (Execution)
    P2P:26656                    ABCI:8080                    RPC:8545
    RPC:26657                                                 Engine:8551
                                                              P2P:30303
```

## Troubleshooting

**No peers / not syncing:**
```bash
# Check peer count
curl -s http://localhost:26657/net_info | jq '.result.n_peers'

# Re-fetch latest peers
~/.orqus/install.sh reconfigure
~/.orqus/orqusctl.sh start

# Ensure firewall allows: 26656/tcp, 30303/tcp+udp
```

## License

Apache 2.0
