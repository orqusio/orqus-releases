#!/bin/bash
#
# Orqus Chain - One-click Install & Upgrade Script
#
# Usage:
#   # Binary mode (default)
#   curl -sSL https://raw.githubusercontent.com/orqusio/orqus-releases/main/install.sh | bash
#
#   # Docker mode
#   curl -sSL https://raw.githubusercontent.com/orqusio/orqus-releases/main/install.sh | INSTALL_MODE=docker bash
#
#   # Connect to existing network (testnet/mainnet)
#   # Genesis is auto-fetched from first peer when NODE_TYPE != validator
#   export NODE_TYPE=rpc
#   export PERSISTENT_PEERS="node_id@sentry1.orqus.io:26656"
#   export RETH_TRUSTED_PEERS="enode://pubkey@sentry1.orqus.io:30303"
#   curl -sSL https://raw.githubusercontent.com/orqusio/orqus-releases/main/install.sh | bash
#
#   # Or specify genesis URL explicitly:
#   export GENESIS_URL="http://sentry_ip:26657/genesis"
#
#   # Upgrade existing installation
#   ~/.orqus/install.sh upgrade
#   # Or:
#   curl -sSL https://raw.githubusercontent.com/orqusio/orqus-releases/main/install.sh | bash -s -- upgrade
#
# This script will:
# 1. Download binaries OR pull Docker images
# 2. Generate configuration files
# 3. Initialize the chain with genesis state
# 4. Create start/stop scripts
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Configuration
INSTALL_DIR="${ORQUS_INSTALL_DIR:-$HOME/.orqus}"
DATA_DIR="${INSTALL_DIR}/data"
BIN_DIR="${INSTALL_DIR}/bin"
CONFIG_DIR="${INSTALL_DIR}/config"

# Installation mode: binary or docker
INSTALL_MODE="${INSTALL_MODE:-binary}"

# Docker image registry
DOCKER_REGISTRY="${DOCKER_REGISTRY:-ghcr.io/orqusio}"

# Chain parameters
CHAIN_ID="${ORQUS_CHAIN_ID:-153871}"
CHAIN_NAME="${ORQUS_CHAIN_NAME:-orqus-testnet}"
MONIKER="${ORQUS_MONIKER:-orqus-node}"

# Node type: validator, sentry, rpc, archive
# - validator: Full validator with signing keys (default)
# - sentry: Protects validator, no signing, public P2P
# - rpc: Public RPC endpoint, no signing
# - archive: Full history node, no signing
NODE_TYPE="${NODE_TYPE:-validator}"

# Versions
COMETBFT_VERSION="${COMETBFT_VERSION:-v0.38.15}"

# P2P configuration
# CometBFT peers - Format: "node_id@ip:port,node_id@ip:port"
# Example: PERSISTENT_PEERS="abc123@sentry-1.orqus.io:26656,def456@sentry-2.orqus.io:26656"
PERSISTENT_PEERS="${PERSISTENT_PEERS:-}"
SEEDS="${SEEDS:-}"

# Reth P2P peers - Format: "enode://pubkey@ip:port,enode://pubkey@ip:port"
# Example: RETH_TRUSTED_PEERS="enode://abc123...@10.0.1.10:30303,enode://def456...@10.0.1.11:30303"
RETH_TRUSTED_PEERS="${RETH_TRUSTED_PEERS:-}"

# Genesis URL (for joining existing network)
# If set, CometBFT genesis will be downloaded from this URL
# Auto-fetched from first peer if NODE_TYPE != validator and PERSISTENT_PEERS is set
# Example: GENESIS_URL="http://sentry_ip:26657/genesis"
GENESIS_URL="${GENESIS_URL:-}"

# Reth Genesis URL (for joining existing network)
# If set, reth genesis will be downloaded from this URL instead of GitHub releases
# Example: RETH_GENESIS_URL="http://sentry_ip:8888/genesis.json"
RETH_GENESIS_URL="${RETH_GENESIS_URL:-}"

# Ports
RETH_HTTP_PORT="${RETH_HTTP_PORT:-8545}"
RETH_WS_PORT="${RETH_WS_PORT:-8546}"
RETH_ENGINE_PORT="${RETH_ENGINE_PORT:-8551}"
RETH_P2P_PORT="${RETH_P2P_PORT:-30303}"
RETH_METRICS_PORT="${RETH_METRICS_PORT:-9001}"
COMETBFT_P2P_PORT="${COMETBFT_P2P_PORT:-26656}"
COMETBFT_RPC_PORT="${COMETBFT_RPC_PORT:-26657}"
ORQUSBFT_ABCI_PORT="${ORQUSBFT_ABCI_PORT:-8080}"

# Detect OS and architecture
detect_platform() {
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)

    case "$ARCH" in
        x86_64)  ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        arm64)   ARCH="arm64" ;;
        *)       log_error "Unsupported architecture: $ARCH"; exit 1 ;;
    esac

    case "$OS" in
        linux)  ;;
        darwin) ;;
        *)      log_error "Unsupported OS: $OS"; exit 1 ;;
    esac

    log_info "Detected platform: ${OS}/${ARCH}"
}

# Get latest release version from GitHub
get_latest_version() {
    local repo=$1
    curl -sL "https://api.github.com/repos/${repo}/releases/latest" | \
        grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/' || echo ""
}

# Download binary from GitHub Releases
download_binary() {
    local name=$1
    local url=$2
    local dest="${BIN_DIR}/${name}"

    log_info "Downloading ${name}..."
    curl -sL -o "${dest}" "${url}"
    chmod +x "${dest}"
    log_ok "Downloaded ${name}"
}

# Download and extract CometBFT
download_cometbft() {
    local version="${COMETBFT_VERSION}"
    local url="https://github.com/cometbft/cometbft/releases/download/${version}/cometbft_${version#v}_${OS}_${ARCH}.tar.gz"

    log_info "Downloading CometBFT ${version}..."
    curl -sL "${url}" | tar -xz -C "${BIN_DIR}" cometbft
    chmod +x "${BIN_DIR}/cometbft"
    log_ok "Downloaded CometBFT ${version}"
}

# Pull Docker images
pull_docker_images() {
    log_info "Pulling Docker images..."

    # Login to ghcr.io if GITHUB_TOKEN is set (for private repos)
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        log_info "Logging into ghcr.io..."
        echo "${GITHUB_TOKEN}" | docker login ghcr.io -u orqusio --password-stdin || {
            log_warn "Failed to login to ghcr.io, trying without auth..."
        }
    fi

    log_info "Pulling orqus-reth..."
    docker pull "${DOCKER_REGISTRY}/orqus-reth:${DOCKER_TAG}" || {
        log_error "Failed to pull orqus-reth image"
        log_error "If the image is private, set GITHUB_TOKEN environment variable"
        exit 1
    }

    log_info "Pulling orqusbft..."
    docker pull "${DOCKER_REGISTRY}/orqusbft:${DOCKER_TAG}" || {
        log_error "Failed to pull orqusbft image"
        exit 1
    }

    log_info "Pulling CometBFT..."
    docker pull "cometbft/cometbft:${COMETBFT_VERSION}" || {
        log_error "Failed to pull cometbft image"
        exit 1
    }

    log_ok "Docker images pulled"
}

# Generate docker-compose.yml
generate_docker_compose() {
    local compose_file="${INSTALL_DIR}/docker-compose.yml"

    log_info "Generating docker-compose.yml..."
    cat > "${compose_file}" << EOF
version: '3.8'

services:
  orqus-reth:
    image: ${DOCKER_REGISTRY}/orqus-reth:${DOCKER_TAG}
    container_name: orqus-reth
    restart: unless-stopped
    ports:
      - "${RETH_HTTP_PORT}:8545"
      - "${RETH_WS_PORT}:8546"
      - "${RETH_ENGINE_PORT}:8551"
      - "${RETH_P2P_PORT}:30303/tcp"
      - "${RETH_P2P_PORT}:30303/udp"
      - "${RETH_METRICS_PORT}:9001"
    volumes:
      - ${DATA_DIR}/reth:/data
      - ${CONFIG_DIR}/reth-genesis.json:/genesis.json:ro
      - ${CONFIG_DIR}/jwt.hex:/jwt.hex:ro
    command: >
      node
      --datadir /data
      --chain /genesis.json
      --http --http.addr 0.0.0.0 --http.port 8545
      --http.api eth,net,web3,debug,trace
      --ws --ws.addr 0.0.0.0 --ws.port 8546
      --authrpc.addr 0.0.0.0 --authrpc.port 8551
      --authrpc.jwtsecret /jwt.hex
      --port 30303
      --nat none
      --metrics 0.0.0.0:9001
      ${RETH_TRUSTED_PEERS:+--trusted-peers ${RETH_TRUSTED_PEERS}}
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8545"]
      interval: 10s
      timeout: 5s
      retries: 5

  orqusbft:
    image: ${DOCKER_REGISTRY}/orqusbft:${DOCKER_TAG}
    container_name: orqusbft
    restart: unless-stopped
    depends_on:
      orqus-reth:
        condition: service_healthy
    ports:
      - "${ORQUSBFT_ABCI_PORT}:8080"
      - "8090:8090"
    volumes:
      - ${CONFIG_DIR}/orqusbft-config.yaml:/app/config.yaml:ro
      - ${CONFIG_DIR}/jwt.hex:/app/jwt.hex:ro
      - ${DATA_DIR}/orqusbft:/data
    command: ["-config", "/app/config.yaml"]

  cometbft:
    image: cometbft/cometbft:${COMETBFT_VERSION}
    container_name: cometbft
    restart: unless-stopped
    depends_on:
      - orqusbft
    ports:
      - "${COMETBFT_P2P_PORT}:26656"
      - "${COMETBFT_RPC_PORT}:26657"
      - "26660:26660"
    volumes:
      - ${DATA_DIR}/cometbft:/cometbft
    command: start --proxy_app=tcp://orqusbft:8080
    environment:
      - CMTHOME=/cometbft
EOF
    log_ok "docker-compose.yml generated"
}

# Generate orqusbft config for Docker mode
generate_orqusbft_config_docker() {
    local config_file="${CONFIG_DIR}/orqusbft-config.yaml"

    # Node type specific settings
    local slashing_enabled="false"
    local retain_blocks="0"

    case "${NODE_TYPE}" in
        validator)
            slashing_enabled="false"
            retain_blocks="0"
            ;;
        sentry|rpc)
            slashing_enabled="false"
            retain_blocks="100000"
            ;;
        archive)
            slashing_enabled="false"
            retain_blocks="0"
            ;;
    esac

    log_info "Generating orqusbft config (Docker mode, ${NODE_TYPE})..."
    cat > "${config_file}" << EOF
# orqusbft Configuration (Docker mode)
# Node Type: ${NODE_TYPE}
# See: https://github.com/orqusio/orqus-releases

chainId: ${CHAIN_ID}
dataDir: "/data"

# Fee recipient address for block rewards
feeRecipient: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"

ethereum:
  endpoint: "http://orqus-reth:8545"
  engineAPI: "http://orqus-reth:8551"
  jwtSecret: "/app/jwt.hex"

cometbft:
  endpoint: "http://cometbft:26657"
  homeDir: "/data/cometbft"

bridge:
  listenAddr: "0.0.0.0:8080"
  logLevel: "info"
  enableBridging: true

metrics:
  enabled: true
  listenAddr: "0.0.0.0:8090"

consensus:
  epochLength: 270
  blockPeriod: 1

slashing:
  enabled: ${slashing_enabled}
  missedBlockThreshold: 10
  jailDuration: 1800

storage:
  retainBlocks: ${retain_blocks}

validatorCommitment:
  enabled: false
  minValidators: 4
  maxChangeRatio: 0.33
  gracePeriodBlocks: 2

contract:
  enabled: true
  validatorRegistry: "0x6f00000000000000000000000000000000001000"
EOF
    log_ok "orqusbft config generated"
}

# Generate validator key for Docker mode
generate_validator_key_docker() {
    local priv_key_file="${CONFIG_DIR}/priv_validator_key.json"

    if [ ! -f "${priv_key_file}" ]; then
        log_info "Generating validator key (Docker mode)..."

        # Ensure cometbft directories exist
        mkdir -p "${DATA_DIR}/cometbft/config" "${DATA_DIR}/cometbft/data"

        # Use CometBFT container to generate keys
        # Run as current user to avoid permission issues
        docker run --rm \
            --user "$(id -u):$(id -g)" \
            -v "${DATA_DIR}/cometbft:/cometbft" \
            "cometbft/cometbft:${COMETBFT_VERSION}" init --home /cometbft || {
            log_error "Failed to generate validator key"
            exit 1
        }

        # Extract the generated key
        cp "${DATA_DIR}/cometbft/config/priv_validator_key.json" "${priv_key_file}"
        cp "${DATA_DIR}/cometbft/config/node_key.json" "${CONFIG_DIR}/node_key.json"

        log_ok "Validator key generated"
    else
        log_info "Validator key already exists"
    fi
}

# Generate Docker start script
generate_docker_start_script() {
    local start_script="${INSTALL_DIR}/start.sh"

    log_info "Generating Docker start script..."
    cat > "${start_script}" << 'SCRIPT'
#!/bin/bash
set -e

INSTALL_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "${INSTALL_DIR}"

echo "Starting Orqus Chain (Docker mode)..."

# Initialize reth if needed
if [ ! -d "${INSTALL_DIR}/data/reth/db" ]; then
    echo "Initializing orqus-reth..."
    docker run --rm \
        -v "${INSTALL_DIR}/data/reth:/data" \
        -v "${INSTALL_DIR}/config/reth-genesis.json:/genesis.json:ro" \
        $(grep 'image:.*orqus-reth' docker-compose.yml | awk '{print $2}') \
        init --datadir /data --chain /genesis.json
fi

docker compose up -d

echo ""
echo "Orqus Chain started!"
echo ""
echo "Endpoints:"
echo "  JSON-RPC:  http://127.0.0.1:8545"
echo "  WebSocket: ws://127.0.0.1:8546"
echo "  CometBFT:  http://127.0.0.1:26657"
echo ""
echo "Logs:"
echo "  docker compose logs -f"
echo ""
SCRIPT
    chmod +x "${start_script}"
    log_ok "Docker start script generated"
}

# Generate Docker stop script
generate_docker_stop_script() {
    local stop_script="${INSTALL_DIR}/stop.sh"

    cat > "${stop_script}" << 'SCRIPT'
#!/bin/bash
INSTALL_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "${INSTALL_DIR}"
echo "Stopping Orqus Chain..."
docker compose down
echo "Stopped"
SCRIPT
    chmod +x "${stop_script}"
}

# Generate JWT secret for Engine API authentication
generate_jwt_secret() {
    local jwt_file="${CONFIG_DIR}/jwt.hex"
    if [ ! -f "${jwt_file}" ]; then
        log_info "Generating JWT secret..."
        openssl rand -hex 32 > "${jwt_file}"
        log_ok "JWT secret generated"
    else
        log_info "JWT secret already exists"
    fi
}

# Generate validator key for CometBFT
generate_validator_key() {
    local priv_key_file="${CONFIG_DIR}/priv_validator_key.json"

    if [ ! -f "${priv_key_file}" ]; then
        log_info "Generating validator key..."
        "${BIN_DIR}/cometbft" init --home "${DATA_DIR}/cometbft" > /dev/null 2>&1

        # Extract the generated key
        cp "${DATA_DIR}/cometbft/config/priv_validator_key.json" "${priv_key_file}"
        cp "${DATA_DIR}/cometbft/config/node_key.json" "${CONFIG_DIR}/node_key.json"

        log_ok "Validator key generated"
    else
        log_info "Validator key already exists"
    fi
}

# Get validator info from key
get_validator_info() {
    local priv_key_file="${CONFIG_DIR}/priv_validator_key.json"

    VALIDATOR_ADDRESS=$(python3 -c "import json; d=json.load(open('${priv_key_file}')); print(d['address'])" 2>/dev/null || \
                       cat "${priv_key_file}" | grep -o '"address": *"[^"]*"' | cut -d'"' -f4)
    VALIDATOR_PUBKEY=$(python3 -c "import json; d=json.load(open('${priv_key_file}')); print(d['pub_key']['value'])" 2>/dev/null || \
                      cat "${priv_key_file}" | grep -o '"value": *"[^"]*"' | head -1 | cut -d'"' -f4)
}

# Download or generate CometBFT genesis.json
generate_cometbft_genesis() {
    local genesis_file="${CONFIG_DIR}/genesis.json"

    # If GENESIS_URL is set, download from existing node
    if [ -n "${GENESIS_URL}" ]; then
        log_info "Downloading CometBFT genesis from ${GENESIS_URL}..."

        # Check if it's a CometBFT RPC endpoint (returns JSON with result.genesis)
        if [[ "${GENESIS_URL}" == *"/genesis"* ]] || [[ "${GENESIS_URL}" == *":26657"* ]]; then
            # CometBFT RPC format: { "result": { "genesis": {...} } }
            local tmp_file=$(mktemp)
            if curl -sL "${GENESIS_URL}" -o "${tmp_file}"; then
                # Extract genesis from RPC response
                if python3 -c "import json; d=json.load(open('${tmp_file}')); print(json.dumps(d.get('result',{}).get('genesis',d), indent=2))" > "${genesis_file}" 2>/dev/null; then
                    rm -f "${tmp_file}"
                    log_ok "CometBFT genesis downloaded from RPC"
                    return
                else
                    # Maybe it's already a raw genesis file
                    mv "${tmp_file}" "${genesis_file}"
                    log_ok "CometBFT genesis downloaded"
                    return
                fi
            fi
            rm -f "${tmp_file}"
            log_error "Failed to download genesis from ${GENESIS_URL}"
            exit 1
        else
            # Direct genesis.json URL
            if curl -sL "${GENESIS_URL}" -o "${genesis_file}"; then
                log_ok "CometBFT genesis downloaded"
                return
            fi
            log_error "Failed to download genesis from ${GENESIS_URL}"
            exit 1
        fi
    fi

    # If joining existing network (PERSISTENT_PEERS set), try to fetch genesis from first peer
    if [ -n "${PERSISTENT_PEERS}" ] && [ "${NODE_TYPE}" != "validator" ]; then
        local first_peer=$(echo "${PERSISTENT_PEERS}" | cut -d',' -f1)
        local peer_ip=$(echo "${first_peer}" | cut -d'@' -f2 | cut -d':' -f1)
        local rpc_url="http://${peer_ip}:26657/genesis"

        log_info "Fetching CometBFT genesis from peer ${peer_ip}..."
        local tmp_file=$(mktemp)
        if curl -sL --connect-timeout 10 "${rpc_url}" -o "${tmp_file}" 2>/dev/null; then
            if python3 -c "import json; d=json.load(open('${tmp_file}')); g=d.get('result',{}).get('genesis',d); print(json.dumps(g, indent=2))" > "${genesis_file}" 2>/dev/null; then
                rm -f "${tmp_file}"
                # Extract chain_id from downloaded genesis
                CHAIN_ID=$(python3 -c "import json; print(json.load(open('${genesis_file}'))['chain_id'])" 2>/dev/null || echo "${CHAIN_ID}")
                log_ok "CometBFT genesis fetched from peer (chain_id: ${CHAIN_ID})"
                return
            fi
        fi
        rm -f "${tmp_file}"
        log_warn "Could not fetch genesis from peer, generating new genesis"
    fi

    # Generate new genesis (for new network or validator)
    local genesis_time=$(date -u +"%Y-%m-%dT%H:%M:%S.000000000Z")
    get_validator_info

    log_info "Generating new CometBFT genesis..."
    cat > "${genesis_file}" << EOF
{
  "genesis_time": "${genesis_time}",
  "chain_id": "${CHAIN_ID}",
  "initial_height": "1",
  "consensus_params": {
    "block": {
      "max_bytes": "22020096",
      "max_gas": "-1"
    },
    "evidence": {
      "max_age_num_blocks": "100000",
      "max_age_duration": "172800000000000",
      "max_bytes": "1048576"
    },
    "validator": {
      "pub_key_types": ["ed25519"]
    },
    "version": {
      "app": "0"
    },
    "abci": {
      "vote_extensions_enable_height": "0"
    }
  },
  "validators": [
    {
      "address": "${VALIDATOR_ADDRESS}",
      "pub_key": {
        "type": "tendermint/PubKeyEd25519",
        "value": "${VALIDATOR_PUBKEY}"
      },
      "power": "1",
      "name": "${MONIKER}"
    }
  ],
  "app_hash": ""
}
EOF
    log_ok "CometBFT genesis generated"
}

# Generate CometBFT config.toml
generate_cometbft_config() {
    local config_file="${CONFIG_DIR}/cometbft-config.toml"

    # Node type specific settings
    local pex_enabled="true"
    local addr_book_strict="true"

    case "${NODE_TYPE}" in
        validator)
            # Validator: only connects to sentry, no public peer exchange
            pex_enabled="false"
            addr_book_strict="false"
            ;;
        sentry)
            # Sentry: public P2P, peer exchange enabled
            pex_enabled="true"
            addr_book_strict="false"
            ;;
        rpc|archive)
            # RPC/Archive: public P2P, peer exchange enabled
            pex_enabled="true"
            addr_book_strict="true"
            ;;
    esac

    log_info "Generating CometBFT config (${NODE_TYPE})..."
    cat > "${config_file}" << EOF
# CometBFT Configuration
# Node Type: ${NODE_TYPE}

proxy_app = "tcp://127.0.0.1:${ORQUSBFT_ABCI_PORT}"
moniker = "${MONIKER}"
db_backend = "goleveldb"
db_dir = "data"
log_level = "info"
log_format = "plain"

[rpc]
laddr = "tcp://0.0.0.0:${COMETBFT_RPC_PORT}"
cors_allowed_origins = ["*"]
cors_allowed_methods = ["HEAD", "GET", "POST"]
cors_allowed_headers = ["Origin", "Accept", "Content-Type", "X-Requested-With", "X-Server-Time"]

[p2p]
laddr = "tcp://0.0.0.0:${COMETBFT_P2P_PORT}"
seeds = "${SEEDS}"
persistent_peers = "${PERSISTENT_PEERS}"
max_packet_msg_payload_size = 10240
pex = ${pex_enabled}
seed_mode = false
addr_book_strict = ${addr_book_strict}

[mempool]
type = "nop"

[consensus]
timeout_propose = "3s"
timeout_propose_delta = "500ms"
timeout_prevote = "1s"
timeout_prevote_delta = "500ms"
timeout_precommit = "1s"
timeout_precommit_delta = "500ms"
timeout_commit = "1s"
skip_timeout_commit = false
create_empty_blocks = true
create_empty_blocks_interval = "2s"

[storage]
discard_abci_responses = false

[tx_index]
indexer = "kv"

[instrumentation]
prometheus = true
prometheus_listen_addr = ":26660"
EOF
    log_ok "CometBFT config generated"
}

# Generate orqusbft config.yaml
generate_orqusbft_config() {
    local config_file="${CONFIG_DIR}/orqusbft-config.yaml"

    # Node type specific settings
    local slashing_enabled="false"
    local retain_blocks="0"

    case "${NODE_TYPE}" in
        validator)
            # Validator: slashing should be enabled in production
            slashing_enabled="false"  # User should enable manually for production
            retain_blocks="0"
            ;;
        sentry|rpc)
            # Sentry/RPC: no slashing, keep recent blocks only
            slashing_enabled="false"
            retain_blocks="100000"  # ~1 day of blocks
            ;;
        archive)
            # Archive: no slashing, keep all blocks
            slashing_enabled="false"
            retain_blocks="0"
            ;;
    esac

    log_info "Generating orqusbft config (${NODE_TYPE})..."
    cat > "${config_file}" << EOF
# orqusbft Configuration
# Node Type: ${NODE_TYPE}
# See: https://github.com/orqusio/orqus-releases

chainId: ${CHAIN_ID}
dataDir: "${DATA_DIR}/orqusbft"

# Fee recipient address for block rewards
# Default: Hardhat account #0 (for testing)
# Production: Change to your validator's address
feeRecipient: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"

ethereum:
  endpoint: "http://127.0.0.1:${RETH_HTTP_PORT}"
  engineAPI: "http://127.0.0.1:${RETH_ENGINE_PORT}"
  jwtSecret: "${CONFIG_DIR}/jwt.hex"

cometbft:
  endpoint: "http://127.0.0.1:${COMETBFT_RPC_PORT}"
  homeDir: "${DATA_DIR}/cometbft"

bridge:
  listenAddr: "0.0.0.0:${ORQUSBFT_ABCI_PORT}"
  logLevel: "info"
  enableBridging: true

metrics:
  enabled: true
  listenAddr: "0.0.0.0:8090"

# Consensus parameters (must match ValidatorRegistry contract)
consensus:
  epochLength: 270    # blocks per epoch (~4.5 min @ 1s block)
  blockPeriod: 1      # seconds per block (production: 1, testing: 2)

# Slashing configuration
# - validator: Enable in production (set enabled: true)
# - sentry/rpc/archive: Keep disabled
slashing:
  enabled: ${slashing_enabled}
  missedBlockThreshold: 10    # Miss 10 blocks -> slash
  jailDuration: 1800          # Jail for 1800 blocks (~30 min)

# Storage settings
storage:
  retainBlocks: ${retain_blocks}    # 0 = keep all blocks

# Validator commitment verification (multi-validator only)
validatorCommitment:
  enabled: false
  minValidators: 4
  maxChangeRatio: 0.33
  gracePeriodBlocks: 2

# Smart contract integration
contract:
  enabled: true
  validatorRegistry: "0x6f00000000000000000000000000000000001000"
EOF
    log_ok "orqusbft config generated"
}

# Download orqus-reth genesis.json from release or custom URL
download_reth_genesis() {
    local genesis_file="${CONFIG_DIR}/reth-genesis.json"

    if [ -f "${genesis_file}" ]; then
        log_info "Reth genesis file already exists, skipping download"
        return
    fi

    # Use RETH_GENESIS_URL if set, otherwise fall back to release URL
    local genesis_url
    if [ -n "${RETH_GENESIS_URL}" ]; then
        genesis_url="${RETH_GENESIS_URL}"
        log_info "Downloading reth genesis from custom URL..."
    else
        genesis_url="${RELEASE_URL}/genesis.json"
        log_info "Downloading reth genesis from release..."
    fi

    if ! curl -sL -o "${genesis_file}" "${genesis_url}"; then
        log_error "Failed to download reth genesis from ${genesis_url}"
        exit 1
    fi

    # Verify it's valid JSON
    if ! python3 -c "import json; json.load(open('${genesis_file}'))" 2>/dev/null; then
        log_error "Downloaded reth genesis is not valid JSON"
        rm -f "${genesis_file}"
        exit 1
    fi

    log_ok "Reth genesis downloaded from ${genesis_url}"
}

# Setup CometBFT data directory
setup_cometbft() {
    local cometbft_home="${DATA_DIR}/cometbft"

    log_info "Setting up CometBFT..."
    mkdir -p "${cometbft_home}/config" "${cometbft_home}/data"

    cp "${CONFIG_DIR}/genesis.json" "${cometbft_home}/config/genesis.json"
    cp "${CONFIG_DIR}/cometbft-config.toml" "${cometbft_home}/config/config.toml"
    cp "${CONFIG_DIR}/priv_validator_key.json" "${cometbft_home}/config/priv_validator_key.json"
    cp "${CONFIG_DIR}/node_key.json" "${cometbft_home}/config/node_key.json"

    # Initialize priv_validator_state.json if not exists
    if [ ! -f "${cometbft_home}/data/priv_validator_state.json" ]; then
        echo '{"height":"0","round":0,"step":0}' > "${cometbft_home}/data/priv_validator_state.json"
    fi

    log_ok "CometBFT setup complete"
}

# Initialize orqus-reth
init_reth() {
    local reth_datadir="${DATA_DIR}/reth"

    log_info "Initializing orqus-reth..."
    mkdir -p "${reth_datadir}"

    "${BIN_DIR}/orqus-reth" init \
        --datadir "${reth_datadir}" \
        --chain "${CONFIG_DIR}/reth-genesis.json" \
        2>/dev/null || true

    log_ok "orqus-reth initialized"
}

# Generate start script
generate_start_script() {
    local start_script="${INSTALL_DIR}/start.sh"

    log_info "Generating start script..."
    cat > "${start_script}" << 'SCRIPT'
#!/bin/bash
set -e

INSTALL_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${INSTALL_DIR}/env.sh"

# Trap to kill all background processes on exit
cleanup() {
    echo ""
    echo "Shutting down..."
    kill $(jobs -p) 2>/dev/null || true
    wait
    echo "Shutdown complete"
}
trap cleanup EXIT INT TERM

echo "Starting Orqus Chain..."
echo "  Data dir: ${DATA_DIR}"
echo "  RPC: http://127.0.0.1:${RETH_HTTP_PORT}"
echo ""

# Start orqus-reth
echo "[1/3] Starting orqus-reth..."
RETH_TRUSTED_PEERS_ARG=""
if [ -n "${RETH_TRUSTED_PEERS}" ]; then
    RETH_TRUSTED_PEERS_ARG="--trusted-peers ${RETH_TRUSTED_PEERS}"
fi
"${BIN_DIR}/orqus-reth" node \
    --datadir "${DATA_DIR}/reth" \
    --chain "${CONFIG_DIR}/reth-genesis.json" \
    --http --http.addr 0.0.0.0 --http.port ${RETH_HTTP_PORT} \
    --http.api eth,net,web3,debug,trace \
    --ws --ws.addr 0.0.0.0 --ws.port ${RETH_WS_PORT} \
    --authrpc.addr 0.0.0.0 --authrpc.port ${RETH_ENGINE_PORT} \
    --authrpc.jwtsecret "${CONFIG_DIR}/jwt.hex" \
    --port ${RETH_P2P_PORT} \
    --metrics 0.0.0.0:${RETH_METRICS_PORT} \
    ${RETH_TRUSTED_PEERS_ARG} \
    > "${DATA_DIR}/logs/reth.log" 2>&1 &
RETH_PID=$!
echo "    PID: ${RETH_PID}"

# Wait for reth to be ready
sleep 3

# Start orqusbft
echo "[2/3] Starting orqusbft..."
"${BIN_DIR}/orqusbft" \
    -config "${CONFIG_DIR}/orqusbft-config.yaml" \
    > "${DATA_DIR}/logs/orqusbft.log" 2>&1 &
ORQUSBFT_PID=$!
echo "    PID: ${ORQUSBFT_PID}"

# Wait for orqusbft ABCI to be ready
sleep 2

# Start CometBFT
echo "[3/3] Starting CometBFT..."
"${BIN_DIR}/cometbft" start \
    --home "${DATA_DIR}/cometbft" \
    > "${DATA_DIR}/logs/cometbft.log" 2>&1 &
COMETBFT_PID=$!
echo "    PID: ${COMETBFT_PID}"

echo ""
echo "All components started!"
echo ""
echo "Endpoints:"
echo "  JSON-RPC:  http://127.0.0.1:${RETH_HTTP_PORT}"
echo "  WebSocket: ws://127.0.0.1:${RETH_WS_PORT}"
echo "  CometBFT:  http://127.0.0.1:${COMETBFT_RPC_PORT}"
echo ""
echo "Logs:"
echo "  tail -f ${DATA_DIR}/logs/reth.log"
echo "  tail -f ${DATA_DIR}/logs/orqusbft.log"
echo "  tail -f ${DATA_DIR}/logs/cometbft.log"
echo ""
echo "Press Ctrl+C to stop..."
echo ""

# Wait for any process to exit
wait -n
SCRIPT
    chmod +x "${start_script}"
    log_ok "Start script generated"
}

# Generate stop script
generate_stop_script() {
    local stop_script="${INSTALL_DIR}/stop.sh"

    cat > "${stop_script}" << 'SCRIPT'
#!/bin/bash
echo "Stopping Orqus Chain..."
pkill -f "orqus-reth" 2>/dev/null || true
pkill -f "orqusbft" 2>/dev/null || true
pkill -f "cometbft" 2>/dev/null || true
echo "Stopped"
SCRIPT
    chmod +x "${stop_script}"
}

# Generate environment file
generate_env_file() {
    local env_file="${INSTALL_DIR}/env.sh"

    cat > "${env_file}" << EOF
# Orqus Chain Environment
export INSTALL_DIR="${INSTALL_DIR}"
export DATA_DIR="${DATA_DIR}"
export BIN_DIR="${BIN_DIR}"
export CONFIG_DIR="${CONFIG_DIR}"
export CHAIN_ID="${CHAIN_ID}"

# Ports
export RETH_HTTP_PORT="${RETH_HTTP_PORT}"
export RETH_WS_PORT="${RETH_WS_PORT}"
export RETH_ENGINE_PORT="${RETH_ENGINE_PORT}"
export RETH_P2P_PORT="${RETH_P2P_PORT}"
export RETH_METRICS_PORT="${RETH_METRICS_PORT}"
export RETH_TRUSTED_PEERS="${RETH_TRUSTED_PEERS}"
export COMETBFT_P2P_PORT="${COMETBFT_P2P_PORT}"
export COMETBFT_RPC_PORT="${COMETBFT_RPC_PORT}"
export ORQUSBFT_ABCI_PORT="${ORQUSBFT_ABCI_PORT}"

# Add bin to PATH
export PATH="\${BIN_DIR}:\${PATH}"
EOF
}

# Upgrade existing installation
do_upgrade() {
    echo ""
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║              Orqus Chain - Upgrade                        ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""

    # Check if installation exists
    if [ ! -d "${INSTALL_DIR}" ]; then
        log_error "No existing installation found at ${INSTALL_DIR}"
        log_error "Run install first (without 'upgrade' argument)"
        exit 1
    fi

    # Load existing environment
    if [ -f "${INSTALL_DIR}/env.sh" ]; then
        source "${INSTALL_DIR}/env.sh"
    fi

    # Detect install mode from existing installation
    if [ -f "${INSTALL_DIR}/docker-compose.yml" ]; then
        INSTALL_MODE="docker"
    else
        INSTALL_MODE="binary"
    fi

    log_info "Detected installation mode: ${INSTALL_MODE}"
    log_info "Installation directory: ${INSTALL_DIR}"

    detect_platform

    # Fetch latest release info
    log_info "Fetching latest release..."
    LATEST_VERSION=$(get_latest_version "orqusio/orqus-releases")

    if [ -z "${LATEST_VERSION}" ]; then
        log_error "Could not fetch latest version"
        exit 1
    fi

    log_info "Latest version: ${LATEST_VERSION}"
    RELEASE_URL="https://github.com/orqusio/orqus-releases/releases/download/${LATEST_VERSION}"
    DOCKER_TAG="${DOCKER_TAG:-${LATEST_VERSION}}"

    if [ "${INSTALL_MODE}" = "docker" ]; then
        # ==================== Docker Mode Upgrade ====================
        log_info "Stopping containers..."
        cd "${INSTALL_DIR}"
        docker compose down 2>/dev/null || true

        log_info "Pulling new Docker images..."
        pull_docker_images

        # Update docker-compose.yml with new image tags
        log_info "Updating docker-compose.yml..."
        sed -i.bak "s|${DOCKER_REGISTRY}/orqus-reth:[^[:space:]]*|${DOCKER_REGISTRY}/orqus-reth:${DOCKER_TAG}|g" "${INSTALL_DIR}/docker-compose.yml"
        sed -i.bak "s|${DOCKER_REGISTRY}/orqusbft:[^[:space:]]*|${DOCKER_REGISTRY}/orqusbft:${DOCKER_TAG}|g" "${INSTALL_DIR}/docker-compose.yml"
        rm -f "${INSTALL_DIR}/docker-compose.yml.bak"

        log_info "Starting containers with new images..."
        docker compose up -d

    else
        # ==================== Binary Mode Upgrade ====================
        log_info "Stopping services..."
        "${INSTALL_DIR}/stop.sh" 2>/dev/null || true
        sleep 2

        # Backup old binaries
        log_info "Backing up old binaries..."
        for bin in orqus-reth orqusbft cometbft; do
            if [ -f "${BIN_DIR}/${bin}" ]; then
                mv "${BIN_DIR}/${bin}" "${BIN_DIR}/${bin}.bak"
            fi
        done

        # Download new binaries
        log_info "Downloading new binaries..."

        if [ "${OS}" = "linux" ] && [ "${ARCH}" = "amd64" ]; then
            download_binary "orqus-reth" "${RELEASE_URL}/orqus-reth-linux-amd64"
            download_binary "orqusbft" "${RELEASE_URL}/orqusbft-linux-amd64"
        else
            log_error "Binary upgrade only available for linux-amd64"
            # Restore backups
            for bin in orqus-reth orqusbft cometbft; do
                if [ -f "${BIN_DIR}/${bin}.bak" ]; then
                    mv "${BIN_DIR}/${bin}.bak" "${BIN_DIR}/${bin}"
                fi
            done
            exit 1
        fi

        download_cometbft

        # Remove backups after successful download
        for bin in orqus-reth orqusbft cometbft; do
            rm -f "${BIN_DIR}/${bin}.bak"
        done

        log_info "Upgrade complete. Start the chain with:"
        log_info "  ${INSTALL_DIR}/start.sh"
    fi

    echo ""
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║                   Upgrade Complete!                       ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""
    echo "Upgraded to version: ${LATEST_VERSION}"
    echo ""
    if [ "${INSTALL_MODE}" = "docker" ]; then
        echo "Containers are now running with the new images."
        echo "View logs: docker compose -f ${INSTALL_DIR}/docker-compose.yml logs -f"
    else
        echo "To start the chain:"
        echo "  ${INSTALL_DIR}/start.sh"
    fi
    echo ""
}

# Main installation
main() {
    echo ""
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║             Orqus Chain - One-click Installer             ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""

    # Validate install mode
    if [ "${INSTALL_MODE}" != "binary" ] && [ "${INSTALL_MODE}" != "docker" ]; then
        log_error "Invalid INSTALL_MODE: ${INSTALL_MODE}"
        log_error "Valid options: binary, docker"
        exit 1
    fi

    # Validate node type
    case "${NODE_TYPE}" in
        validator|sentry|rpc|archive) ;;
        *)
            log_error "Invalid NODE_TYPE: ${NODE_TYPE}"
            log_error "Valid options: validator, sentry, rpc, archive"
            exit 1
            ;;
    esac

    log_info "Installation mode: ${INSTALL_MODE}"
    log_info "Node type: ${NODE_TYPE}"

    detect_platform

    # Check Docker for docker mode
    if [ "${INSTALL_MODE}" = "docker" ]; then
        if ! command -v docker &> /dev/null; then
            log_error "Docker is not installed. Please install Docker first."
            exit 1
        fi
        if ! docker compose version &> /dev/null && ! docker-compose version &> /dev/null; then
            log_error "Docker Compose is not installed. Please install Docker Compose first."
            exit 1
        fi
    fi

    # Create directories
    log_info "Creating directories..."
    mkdir -p "${BIN_DIR}" "${CONFIG_DIR}" "${DATA_DIR}/logs" "${DATA_DIR}/reth" "${DATA_DIR}/cometbft" "${DATA_DIR}/orqusbft"

    # Fetch latest release info
    log_info "Fetching latest release..."
    LATEST_VERSION=$(get_latest_version "orqusio/orqus-releases")

    if [ -z "${LATEST_VERSION}" ]; then
        log_warn "Could not fetch latest version, using 'latest' tag"
        LATEST_VERSION="latest"
    else
        log_info "Latest version: ${LATEST_VERSION}"
    fi

    RELEASE_URL="https://github.com/orqusio/orqus-releases/releases/download/${LATEST_VERSION}"
    DOCKER_TAG="${DOCKER_TAG:-${LATEST_VERSION}}"

    if [ "${INSTALL_MODE}" = "binary" ]; then
        # ==================== Binary Mode ====================
        # Download orqus-reth (currently only linux-amd64 available)
        if [ ! -f "${BIN_DIR}/orqus-reth" ]; then
            if [ "${OS}" = "linux" ] && [ "${ARCH}" = "amd64" ]; then
                download_binary "orqus-reth" "${RELEASE_URL}/orqus-reth-linux-amd64"
            else
                log_error "orqus-reth binary not available for ${OS}-${ARCH}"
                log_error "Currently only linux-amd64 is supported. Use INSTALL_MODE=docker instead."
                exit 1
            fi
        else
            log_info "orqus-reth already exists, skipping download"
        fi

        # Download orqusbft (currently only linux-amd64 available)
        if [ ! -f "${BIN_DIR}/orqusbft" ]; then
            if [ "${OS}" = "linux" ] && [ "${ARCH}" = "amd64" ]; then
                download_binary "orqusbft" "${RELEASE_URL}/orqusbft-linux-amd64"
            else
                log_error "orqusbft binary not available for ${OS}-${ARCH}"
                log_error "Currently only linux-amd64 is supported. Use INSTALL_MODE=docker instead."
                exit 1
            fi
        else
            log_info "orqusbft already exists, skipping download"
        fi

        # Download CometBFT
        if [ ! -f "${BIN_DIR}/cometbft" ]; then
            download_cometbft
        else
            log_info "CometBFT already exists, skipping download"
        fi

        # Generate configurations
        generate_jwt_secret
        generate_validator_key
        generate_cometbft_genesis
        generate_cometbft_config
        generate_orqusbft_config
        download_reth_genesis

        # Setup components
        setup_cometbft
        init_reth

        # Generate scripts
        generate_env_file
        generate_start_script
        generate_stop_script

    else
        # ==================== Docker Mode ====================
        # Pull Docker images
        pull_docker_images

        # Generate configurations
        generate_jwt_secret
        generate_validator_key_docker
        generate_cometbft_genesis
        generate_cometbft_config
        generate_orqusbft_config_docker
        download_reth_genesis

        # Setup CometBFT data directory
        setup_cometbft

        # Generate Docker files
        generate_docker_compose
        generate_env_file
        generate_docker_start_script
        generate_docker_stop_script
    fi

    # Copy install script for future upgrades
    log_info "Saving install script for future upgrades..."
    SCRIPT_PATH="${BASH_SOURCE[0]}"
    if [ -f "${SCRIPT_PATH}" ]; then
        cp "${SCRIPT_PATH}" "${INSTALL_DIR}/install.sh"
        chmod +x "${INSTALL_DIR}/install.sh"
    else
        # Downloaded via curl, fetch again
        curl -sL -o "${INSTALL_DIR}/install.sh" \
            "https://raw.githubusercontent.com/orqusio/orqus-releases/main/install.sh"
        chmod +x "${INSTALL_DIR}/install.sh"
    fi

    echo ""
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║                  Installation Complete!                   ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""
    echo "Installation mode: ${INSTALL_MODE}"
    echo "Node type: ${NODE_TYPE}"
    echo "Installation directory: ${INSTALL_DIR}"
    echo ""
    echo "To start the chain:"
    echo "  ${INSTALL_DIR}/start.sh"
    echo ""
    echo "To stop the chain:"
    echo "  ${INSTALL_DIR}/stop.sh"
    echo ""
    echo "To upgrade to latest version:"
    echo "  ${INSTALL_DIR}/install.sh upgrade"
    echo ""
    if [ "${INSTALL_MODE}" = "binary" ]; then
        echo "To add binaries to PATH:"
        echo "  source ${INSTALL_DIR}/env.sh"
        echo ""
    fi
    echo "Chain ID: ${CHAIN_ID}"
    echo "RPC endpoint: http://127.0.0.1:${RETH_HTTP_PORT}"
    echo ""
    if [ -n "${PERSISTENT_PEERS}" ]; then
        echo "P2P peers: ${PERSISTENT_PEERS}"
        echo ""
    fi
}

# Parse command
COMMAND="${1:-install}"

case "${COMMAND}" in
    upgrade)
        do_upgrade
        ;;
    install|"")
        main
        ;;
    *)
        echo "Usage: $0 [install|upgrade]"
        echo ""
        echo "Commands:"
        echo "  install   Install Orqus Chain (default)"
        echo "  upgrade   Upgrade existing installation to latest version"
        exit 1
        ;;
esac
