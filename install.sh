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
#   # Benchmark profile with custom genesis gas limit (variables must be placed BEFORE bash)
#   curl -sSL https://raw.githubusercontent.com/orqusio/orqus-releases/main/install.sh | GENESIS_GAS_LIMIT=7000000000 PROFILE=benchmark bash
#   # NOTE: "GENESIS_GAS_LIMIT=... curl ... | bash" is WRONG - variables before curl go to curl, not bash
#
#   # Join testnet (peers are auto-fetched from GitHub)
#   curl -sSL https://raw.githubusercontent.com/orqusio/orqus-releases/main/install.sh | NETWORK=testnet bash
#
#   # Join as RPC node with snapshot (recommended)
#   curl -sSL https://raw.githubusercontent.com/orqusio/orqus-releases/main/install.sh | NODE_TYPE=rpc NETWORK=testnet bash
#
#   # Override peers manually (skips auto-fetch)
#   export PERSISTENT_PEERS="node_id@sentry1.orqus.io:26656"
#   export RETH_TRUSTED_PEERS="enode://pubkey@sentry1.orqus.io:30303"
#   curl -sSL https://raw.githubusercontent.com/orqusio/orqus-releases/main/install.sh | bash
#
#   # Upgrade existing installation
#   ~/.orqus/install.sh upgrade
#   # Or:
#   curl -sSL https://raw.githubusercontent.com/orqusio/orqus-releases/main/install.sh | bash -s -- upgrade
#
# This script will:
# 1. Download binaries OR pull Docker images
# 2. Download and restore snapshot (if configured)
# 3. Generate configuration files
# 4. Initialize the chain with genesis state (if no snapshot)
# 5. Create start/stop scripts
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

# Capture raw user-provided env vars before defaults are applied.
# Used by `reconfigure` to distinguish user overrides from stored env.sh values.
_USER_NODE_TYPE="${NODE_TYPE:-}"
_USER_MONIKER="${ORQUS_MONIKER:-}"
_USER_SEEDS="${SEEDS:-}"
_USER_PERSISTENT_PEERS="${PERSISTENT_PEERS:-}"
_USER_RETH_TRUSTED_PEERS="${RETH_TRUSTED_PEERS:-}"
_USER_NETWORK="${NETWORK:-}"
_USER_SNAPSHOT_BASE_URL="${SNAPSHOT_BASE_URL:-}"
_USER_PROFILE="${PROFILE:-}"
_USER_RETH_RPC_MAX_CONNECTIONS="${RETH_RPC_MAX_CONNECTIONS:-}"
_USER_RETH_BUILDER_GAS_LIMIT="${RETH_BUILDER_GAS_LIMIT:-}"
_USER_RETH_TXPOOL_MAX_PENDING="${RETH_TXPOOL_MAX_PENDING:-}"
_USER_RETH_TXPOOL_MAX_QUEUED="${RETH_TXPOOL_MAX_QUEUED:-}"
_USER_RETH_TXPOOL_MAX_ACCOUNT_SLOTS="${RETH_TXPOOL_MAX_ACCOUNT_SLOTS:-}"
_USER_RETH_TXPOOL_MAX_PENDING_TXNS="${RETH_TXPOOL_MAX_PENDING_TXNS:-}"
_USER_RETH_TXPOOL_MAX_NEW_TXNS="${RETH_TXPOOL_MAX_NEW_TXNS:-}"
_USER_LOG_LEVEL="${LOG_LEVEL:-}"

# Docker image registry
DOCKER_REGISTRY="${DOCKER_REGISTRY:-ghcr.io/orqusio}"

# Chain parameters
CHAIN_ID="${ORQUS_CHAIN_ID:-153871}"
CHAIN_NAME="${ORQUS_CHAIN_NAME:-orqus-testnet}"
MONIKER="${ORQUS_MONIKER:-orqus-node}"

# Node type: validator, rpc
# - validator: Full validator with signing keys (default)
# - rpc: Public RPC endpoint, no signing
NODE_TYPE="${NODE_TYPE:-validator}"

# Versions
COMETBFT_VERSION="${COMETBFT_VERSION:-v0.38.21}"

# P2P configuration
# Peers are auto-fetched from GitHub based on NETWORK if not explicitly set.
# To override, set these environment variables before running the script.
# CometBFT peers - Format: "node_id@ip:port,node_id@ip:port"
PERSISTENT_PEERS="${PERSISTENT_PEERS:-}"
SEEDS="${SEEDS:-}"

# Reth P2P peers - Format: "enode://pubkey@ip:port,enode://pubkey@ip:port"
RETH_TRUSTED_PEERS="${RETH_TRUSTED_PEERS:-}"

# Peers URL: auto-constructed from GitHub raw URL based on NETWORK
# Override with PEERS_URL to use a custom endpoint
PEERS_URL="${PEERS_URL:-}"

# Genesis URL (for joining existing network)
# If set, CometBFT genesis will be downloaded from this URL
# Auto-fetched from first peer if NODE_TYPE != validator and PERSISTENT_PEERS is set
# Example: GENESIS_URL="http://sentry_ip:26657/genesis"
GENESIS_URL="${GENESIS_URL:-}"

# Reth Genesis URL (for joining existing network)
# If set, reth genesis will be downloaded from this URL instead of GitHub releases
# Example: RETH_GENESIS_URL="http://sentry_ip:8888/genesis.json"
RETH_GENESIS_URL="${RETH_GENESIS_URL:-}"

# Override genesis gasLimit after download (decimal or hex, e.g. 70000000 or 0x42C1D80)
# Leave empty to use the value from the downloaded genesis (default)
GENESIS_GAS_LIMIT="${GENESIS_GAS_LIMIT:-}"

# Snapshot configuration (for fast sync)
# SNAPSHOT_URL: Direct URL to snapshot tarball
#   Example: SNAPSHOT_URL="https://snapshots.orqus.io/testnet/orqus-testnet-snapshot-latest.tar.gz"
# SNAPSHOT_BASE_URL: Base URL for auto-discovery (will append network name)
#   Example: SNAPSHOT_BASE_URL="https://snapshots.orqus.io"
#   Auto-constructs: ${SNAPSHOT_BASE_URL}/${NETWORK}/orqus-${NETWORK}-snapshot-latest.tar.gz
SNAPSHOT_URL="${SNAPSHOT_URL:-}"
SNAPSHOT_BASE_URL="${SNAPSHOT_BASE_URL:-https://orqus-snapshots.oss-cn-hongkong.aliyuncs.com}"
NETWORK="${NETWORK:-testnet}"

# Ports
RETH_HTTP_PORT="${RETH_HTTP_PORT:-8545}"
RETH_WS_PORT="${RETH_WS_PORT:-8546}"
RETH_ENGINE_PORT="${RETH_ENGINE_PORT:-8551}"
RETH_P2P_PORT="${RETH_P2P_PORT:-30303}"
RETH_METRICS_PORT="${RETH_METRICS_PORT:-9101}"
COMETBFT_P2P_PORT="${COMETBFT_P2P_PORT:-26656}"
COMETBFT_RPC_PORT="${COMETBFT_RPC_PORT:-26657}"
ORQUSBFT_ABCI_PORT="${ORQUSBFT_ABCI_PORT:-8080}"

# Log level for all components (error/warn/info/debug)
LOG_LEVEL="${LOG_LEVEL:-info}"

# Reth performance tuning (overridable via env or reconfigure PROFILE=benchmark)
RETH_RPC_MAX_CONNECTIONS="${RETH_RPC_MAX_CONNECTIONS:-20000}"
RETH_BUILDER_GAS_LIMIT="${RETH_BUILDER_GAS_LIMIT:-70000000}"
RETH_TXPOOL_MAX_PENDING="${RETH_TXPOOL_MAX_PENDING:-100000}"
RETH_TXPOOL_MAX_QUEUED="${RETH_TXPOOL_MAX_QUEUED:-100000}"
RETH_TXPOOL_MAX_ACCOUNT_SLOTS="${RETH_TXPOOL_MAX_ACCOUNT_SLOTS:-5000}"
RETH_TXPOOL_MAX_PENDING_TXNS="${RETH_TXPOOL_MAX_PENDING_TXNS:-200000}"
RETH_TXPOOL_MAX_NEW_TXNS="${RETH_TXPOOL_MAX_NEW_TXNS:-100000}"

# Install Docker automatically (supports Ubuntu/Debian/CentOS/RHEL/Fedora/Arch/Alpine)
install_docker() {
    log_info "Docker not found. Attempting automatic installation..."

    local os distro

    if [ "$(uname -s)" != "Linux" ]; then
        log_error "Automatic Docker installation is only supported on Linux."
        log_error "Please install Docker Desktop manually: https://docs.docker.com/desktop/"
        exit 1
    fi

    # Detect Linux distro
    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        distro=$(. /etc/os-release && echo "${ID}")
    elif [ -f /etc/redhat-release ]; then
        distro="rhel"
    else
        distro="unknown"
    fi

    case "${distro}" in
        ubuntu|debian|linuxmint|pop|kali|raspbian)
            log_info "Detected Debian/Ubuntu-based distro: ${distro}"
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq
            apt-get install -y -qq ca-certificates curl gnupg
            install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            chmod a+r /etc/apt/keyrings/docker.gpg
            # Use ubuntu for all ubuntu-based, debian for debian-based
            if echo "ubuntu linuxmint pop kali raspbian" | grep -qw "${distro}"; then
                local repo_distro="ubuntu"
            else
                local repo_distro="debian"
            fi
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/${repo_distro} \
$(. /etc/os-release && echo "${UBUNTU_CODENAME:-${VERSION_CODENAME}}") stable" \
                > /etc/apt/sources.list.d/docker.list
            apt-get update -qq
            apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        centos|rhel|ol)
            log_info "Detected RHEL/CentOS-based distro: ${distro}"
            yum install -y -q yum-utils
            yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            yum install -y -q docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        fedora)
            log_info "Detected Fedora"
            dnf -y -q install dnf-plugins-core
            dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
            dnf install -y -q docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        arch|manjaro|endeavouros)
            log_info "Detected Arch-based distro: ${distro}"
            pacman -Sy --noconfirm --quiet docker docker-compose
            ;;
        alpine)
            log_info "Detected Alpine Linux"
            apk add --quiet docker docker-compose
            rc-update add docker boot 2>/dev/null || true
            ;;
        *)
            log_warn "Unknown distro '${distro}', trying Docker's convenience script..."
            curl -fsSL https://get.docker.com | sh
            ;;
    esac

    # Start and enable Docker service
    if command -v systemctl &>/dev/null; then
        systemctl enable docker 2>/dev/null || true
        systemctl start docker
    elif command -v service &>/dev/null; then
        service docker start
    fi

    # Verify installation
    if ! command -v docker &>/dev/null; then
        log_error "Docker installation failed. Please install manually: https://docs.docker.com/engine/install/"
        exit 1
    fi

    log_ok "Docker installed successfully: $(docker --version)"
}

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

# Fetch peers from GitHub (auto-discovery based on NETWORK)
# Only fetches if PERSISTENT_PEERS and RETH_TRUSTED_PEERS are not already set.
# Peers JSON format: { "cometbft": { "persistent_peers": "...", "seeds": "..." }, "reth": { "trusted_peers": "..." } }
fetch_peers() {
    # Skip if both are already set by user
    if [ -n "${PERSISTENT_PEERS}" ] && [ -n "${RETH_TRUSTED_PEERS}" ]; then
        log_info "Peers already configured, skipping auto-fetch"
        return
    fi

    local peers_url="${PEERS_URL:-https://raw.githubusercontent.com/orqusio/orqus-releases/main/peers/${NETWORK}.json}"
    log_info "Fetching peers from ${peers_url}..."

    local peers_json
    peers_json=$(curl -fsSL --retry 2 --retry-delay 1 "${peers_url}" 2>/dev/null) || {
        log_warn "Could not fetch peers from ${peers_url}, continuing without auto-discovered peers"
        return
    }

    # Parse JSON (portable: use grep+sed, no jq dependency)
    if [ -z "${PERSISTENT_PEERS}" ]; then
        local cometbft_peers
        cometbft_peers=$(echo "${peers_json}" | grep '"persistent_peers"' | sed -E 's/.*"persistent_peers"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')
        if [ -n "${cometbft_peers}" ]; then
            PERSISTENT_PEERS="${cometbft_peers}"
            log_ok "Auto-discovered CometBFT peers: ${PERSISTENT_PEERS}"
        fi
    fi

    if [ -z "${SEEDS}" ]; then
        local cometbft_seeds
        cometbft_seeds=$(echo "${peers_json}" | grep '"seeds"' | sed -E 's/.*"seeds"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')
        if [ -n "${cometbft_seeds}" ]; then
            SEEDS="${cometbft_seeds}"
            log_ok "Auto-discovered CometBFT seeds: ${SEEDS}"
        fi
    fi

    if [ -z "${RETH_TRUSTED_PEERS}" ]; then
        local reth_peers
        reth_peers=$(echo "${peers_json}" | grep '"trusted_peers"' | sed -E 's/.*"trusted_peers"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')
        if [ -n "${reth_peers}" ]; then
            RETH_TRUSTED_PEERS="${reth_peers}"
            log_ok "Auto-discovered Reth peers: ${RETH_TRUSTED_PEERS}"
        fi
    fi
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
    local tmp="${dest}.tmp"

    log_info "Downloading ${name}..."
    if ! curl -fSL --retry 3 --retry-delay 2 -o "${tmp}" "${url}"; then
        log_error "Failed to download ${name} from ${url}"
        rm -f "${tmp}"
        exit 1
    fi
    # Sanity check: reject suspiciously small files (< 1 MB likely an error page)
    local size
    size=$(wc -c < "${tmp}")
    if [ "${size}" -lt 1048576 ]; then
        log_error "Downloaded ${name} is too small (${size} bytes), aborting"
        rm -f "${tmp}"
        exit 1
    fi
    # Verify sha256 if remote checksum file is available
    local remote_sha256
    remote_sha256=$(curl -fsSL "${url}.sha256" 2>/dev/null | awk '{print $1}')
    if [ -n "${remote_sha256}" ]; then
        local actual_sha256
        actual_sha256=$(sha256sum "${tmp}" | awk '{print $1}')
        if [ "${actual_sha256}" != "${remote_sha256}" ]; then
            log_error "sha256 mismatch for ${name}!"
            log_error "  expected: ${remote_sha256}"
            log_error "  actual:   ${actual_sha256}"
            rm -f "${tmp}"
            exit 1
        fi
        log_ok "sha256 verified"
    fi
    mv "${tmp}" "${dest}"
    chmod +x "${dest}"
    log_ok "Downloaded ${name} (${size} bytes)"
}

# Download and extract CometBFT
download_cometbft() {
    # CometBFT is now bundled in orqus-releases alongside reth and orqusbft.
    # RELEASE_URL must be set before calling this function.
    download_binary "cometbft" "${RELEASE_URL}/cometbft-linux-amd64"
}

# Check if snapshot is available
check_snapshot_available() {
    local url="$1"

    # Try HEAD request to check if snapshot exists
    if curl -sI --connect-timeout 10 "${url}" 2>/dev/null | head -1 | grep -q "200"; then
        return 0
    fi
    return 1
}

# Get snapshot URL (direct URL or auto-discover from base URL)
get_snapshot_url() {
    # If direct URL is set, use it
    if [ -n "${SNAPSHOT_URL}" ]; then
        echo "${SNAPSHOT_URL}"
        return
    fi

    # If base URL is set, construct the URL
    if [ -n "${SNAPSHOT_BASE_URL}" ]; then
        echo "${SNAPSHOT_BASE_URL}/${NETWORK}/orqus-${NETWORK}-snapshot-latest.tar.gz"
        return
    fi

    # No snapshot configured
    echo ""
}

# Download and restore snapshot
download_snapshot() {
    local snapshot_url=$(get_snapshot_url)

    if [ -z "${snapshot_url}" ]; then
        log_info "No snapshot URL configured, will sync from genesis"
        return 1
    fi

    log_info "Checking snapshot availability..."
    if ! check_snapshot_available "${snapshot_url}"; then
        log_warn "Snapshot not available at ${snapshot_url}, will sync from genesis"
        return 1
    fi

    # Get snapshot metadata if available
    local metadata_url="${snapshot_url}.json"
    local metadata_file=$(mktemp)
    if curl -sL --connect-timeout 10 "${metadata_url}" -o "${metadata_file}" 2>/dev/null; then
        if python3 -c "import json; d=json.load(open('${metadata_file}')); print(f\"  Network: {d.get('network', 'N/A')}\"); print(f\"  Block height: {d.get('block_height', 'N/A')}\"); print(f\"  Timestamp: {d.get('timestamp', 'N/A')}\")" 2>/dev/null; then
            log_info "Snapshot info:"
        fi
    fi
    rm -f "${metadata_file}"

    # Download snapshot
    log_info "Downloading snapshot from ${snapshot_url}..."
    log_info "This may take a while depending on your network speed..."

    local snapshot_file="${DATA_DIR}/snapshot.tar.gz"
    if ! curl -L --progress-bar -o "${snapshot_file}" "${snapshot_url}"; then
        log_error "Failed to download snapshot"
        rm -f "${snapshot_file}"
        return 1
    fi

    # Verify checksum if available
    local checksum_url="${snapshot_url}.sha256"
    local checksum_file=$(mktemp)
    if curl -sL --connect-timeout 10 "${checksum_url}" -o "${checksum_file}" 2>/dev/null; then
        log_info "Verifying snapshot checksum..."
        local expected_hash=$(cat "${checksum_file}" | awk '{print $1}')
        local actual_hash=$(sha256sum "${snapshot_file}" | awk '{print $1}')
        if [ "${expected_hash}" != "${actual_hash}" ]; then
            log_error "Snapshot checksum mismatch!"
            log_error "Expected: ${expected_hash}"
            log_error "Actual:   ${actual_hash}"
            rm -f "${snapshot_file}" "${checksum_file}"
            return 1
        fi
        log_ok "Checksum verified"
    fi
    rm -f "${checksum_file}"

    # Extract snapshot
    log_info "Extracting snapshot..."
    if ! tar -xzf "${snapshot_file}" -C "${DATA_DIR}"; then
        log_error "Failed to extract snapshot"
        rm -f "${snapshot_file}"
        return 1
    fi

    rm -f "${snapshot_file}"
    log_ok "Snapshot restored successfully"

    # Mark that we used a snapshot (skip init steps)
    SNAPSHOT_RESTORED=true
    return 0
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
      --discovery.port 30303
      --metrics 0.0.0.0:9001
      ${RETH_TRUSTED_PEERS:+--trusted-peers ${RETH_TRUSTED_PEERS}}
    environment:
      - RUST_LOG=${LOG_LEVEL}
    healthcheck:
      test: ["CMD-SHELL", "cat /proc/net/tcp | grep -q ':2161'"]
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
      - ${DATA_DIR}/cometbft:/cometbft
    command: ["-config", "/app/config.yaml"]

  cometbft:
    image: cometbft/cometbft:${COMETBFT_VERSION}
    container_name: cometbft
    restart: unless-stopped
    user: "0"
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
        rpc)
            slashing_enabled="false"
            retain_blocks="100000"
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
  homeDir: "/cometbft"

bridge:
  listenAddr: "0.0.0.0:8080"
  logLevel: "${LOG_LEVEL}"
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
        # Set directory permissions first (CometBFT runs as uid 100)
        chmod 777 "${DATA_DIR}/cometbft" "${DATA_DIR}/cometbft/config" "${DATA_DIR}/cometbft/data"

        docker run --rm \
            -v "${DATA_DIR}/cometbft:/cometbft" \
            "cometbft/cometbft:${COMETBFT_VERSION}" init --home /cometbft || {
            log_error "Failed to generate validator key"
            exit 1
        }

        # Fix permissions after init (CometBFT runs as uid 100)
        chmod -R 777 "${DATA_DIR}/cometbft"

        # Extract the generated key
        cp "${DATA_DIR}/cometbft/config/priv_validator_key.json" "${priv_key_file}"
        cp "${DATA_DIR}/cometbft/config/node_key.json" "${CONFIG_DIR}/node_key.json"

        log_ok "Validator key generated"
    else
        log_info "Validator key already exists"
    fi
}

# Generate unified orqusctl.sh for Docker mode
generate_docker_orqusctl_script() {
    local ctl_script="${INSTALL_DIR}/orqusctl.sh"

    log_info "Generating Docker orqusctl.sh..."
    cat > "${ctl_script}" << 'SCRIPT'
#!/bin/bash
#
# orqusctl.sh - Orqus Chain control script (Docker mode)
# Usage: orqusctl.sh <command>
#
# Commands:
#   start     Start containers (docker compose up -d)
#   stop      Stop containers (docker compose down)
#   restart   Restart containers
#   status    Show container status
#   logs      Tail logs (or: logs reth|orqusbft|cometbft)
#   download  Download latest snapshot and restore
#   reset     Wipe chain data and re-initialize from genesis
#

INSTALL_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "${INSTALL_DIR}"
source "${INSTALL_DIR}/env.sh"

cmd_start() {
    local component="${1:-}"
    if [ -n "${component}" ]; then
        echo "Starting ${component}..."
        docker compose up -d "${component}"
        echo "${component} started."
    else
        echo "Starting Orqus Chain (Docker mode)..."
        docker compose up -d
        echo ""
        echo "Orqus Chain started!"
        echo "  JSON-RPC:  http://127.0.0.1:8545"
        echo "  WebSocket: ws://127.0.0.1:8546"
        echo "  CometBFT:  http://127.0.0.1:26657"
        echo ""
        echo "View logs: $(basename "$0") logs"
    fi
}

cmd_stop() {
    local component="${1:-}"
    if [ -n "${component}" ]; then
        echo "Stopping ${component}..."
        docker compose stop "${component}"
        echo "${component} stopped."
    else
        echo "Stopping Orqus Chain..."
        docker compose down
        echo "Stopped."
    fi
}

cmd_status() {
    docker compose ps
}

cmd_logs() {
    local component="${1:-}"
    if [ -n "${component}" ]; then
        docker compose logs -f --tail 100 "${component}"
    else
        docker compose logs -f --tail 100
    fi
}

cmd_download() {
    local snapshot_url="${SNAPSHOT_URL:-}"
    if [ -z "${snapshot_url}" ] && [ -n "${SNAPSHOT_BASE_URL}" ]; then
        snapshot_url="${SNAPSHOT_BASE_URL}/${NETWORK}/orqus-${NETWORK}-snapshot-latest.tar.gz"
    fi
    if [ -z "${snapshot_url}" ]; then
        echo "Error: SNAPSHOT_BASE_URL or SNAPSHOT_URL not set in env.sh"
        exit 1
    fi

    echo "Snapshot URL: ${snapshot_url}"
    echo "Stopping containers..."
    docker compose down

    local tmp_file="${DATA_DIR}/snapshot.tar.gz"
    echo "Downloading snapshot..."
    curl -L --progress-bar -o "${tmp_file}" "${snapshot_url}"

    # Verify checksum
    local checksum_url="${snapshot_url}.sha256"
    local checksum_file=$(mktemp)
    if curl -sL --connect-timeout 10 "${checksum_url}" -o "${checksum_file}" 2>/dev/null && [ -s "${checksum_file}" ]; then
        echo "Verifying checksum..."
        local expected=$(awk '{print $1}' "${checksum_file}")
        local actual=$(sha256sum "${tmp_file}" | awk '{print $1}')
        if [ "${expected}" != "${actual}" ]; then
            echo "Error: Checksum mismatch! expected=${expected} actual=${actual}"
            rm -f "${tmp_file}" "${checksum_file}"
            exit 1
        fi
        echo "Checksum OK"
    fi
    rm -f "${checksum_file}"

    echo "Clearing existing chain data..."
    rm -rf "${DATA_DIR}/reth" "${DATA_DIR}/cometbft/data" "${DATA_DIR}/orqusbft"

    echo "Extracting snapshot to ${DATA_DIR}..."
    tar -xzf "${tmp_file}" -C "${DATA_DIR}"
    rm -f "${tmp_file}"

    # Restore node-specific files overwritten by snapshot
    cp "${CONFIG_DIR}/priv_validator_key.json" "${DATA_DIR}/cometbft/config/priv_validator_key.json" 2>/dev/null || true
    cp "${CONFIG_DIR}/node_key.json" "${DATA_DIR}/cometbft/config/node_key.json" 2>/dev/null || true
    cp "${CONFIG_DIR}/cometbft-config.toml" "${DATA_DIR}/cometbft/config/config.toml" 2>/dev/null || true

    # Ensure priv_validator_state.json exists (snapshot may not include it)
    mkdir -p "${DATA_DIR}/cometbft/data"
    if [ ! -f "${DATA_DIR}/cometbft/data/priv_validator_state.json" ]; then
        echo '{"height":"0","round":0,"step":0}' > "${DATA_DIR}/cometbft/data/priv_validator_state.json"
    fi

    echo ""
    echo "Snapshot restored. Start the chain with:"
    echo "  $(basename $0) start"
}

cmd_reset() {
    echo "WARNING: This will delete all chain data and start fresh from genesis!"
    read -p "Are you sure? (yes/no): " confirm
    if [ "${confirm}" != "yes" ]; then
        echo "Aborted."
        exit 0
    fi

    echo "Stopping containers..."
    docker compose down

    echo "Wiping chain data..."
    rm -rf "${DATA_DIR}/reth"
    rm -rf "${DATA_DIR}/cometbft/data"
    rm -rf "${DATA_DIR}/orqusbft"

    echo "Re-initializing cometbft data..."
    mkdir -p "${DATA_DIR}/cometbft/config" "${DATA_DIR}/cometbft/data"
    cp "${CONFIG_DIR}/genesis.json" "${DATA_DIR}/cometbft/config/genesis.json"
    cp "${CONFIG_DIR}/cometbft-config.toml" "${DATA_DIR}/cometbft/config/config.toml"
    cp "${CONFIG_DIR}/priv_validator_key.json" "${DATA_DIR}/cometbft/config/priv_validator_key.json"
    cp "${CONFIG_DIR}/node_key.json" "${DATA_DIR}/cometbft/config/node_key.json"
    echo '{"height":"0","round":0,"step":0}' > "${DATA_DIR}/cometbft/data/priv_validator_state.json"

    echo ""
    echo "Reset complete. Start the chain with:"
    echo "  $(basename $0) start"
}

case "${1:-}" in
    start)    cmd_start "${2:-}" ;;
    stop)     cmd_stop "${2:-}" ;;
    restart)  cmd_stop "${2:-}"; cmd_start "${2:-}" ;;
    status)   cmd_status ;;
    logs)     cmd_logs "${2:-}" ;;
    download) cmd_download ;;
    reset)    cmd_reset ;;
    *)
        echo "Usage: $(basename $0) <command> [component]"
        echo ""
        echo "Commands:"
        echo "  start     [reth|orqusbft|cometbft]  Start all or a specific service"
        echo "  stop      [reth|orqusbft|cometbft]  Stop all or a specific service"
        echo "  restart   [reth|orqusbft|cometbft]  Restart all or a specific service"
        echo "  status    Show container status"
        echo "  logs      [reth|orqusbft|cometbft]  Tail logs"
        echo "  download  Download latest snapshot and restore"
        echo "  reset     Wipe data and re-initialize from genesis"
        exit 1
        ;;
esac
SCRIPT
    chmod +x "${ctl_script}"
    log_ok "Docker orqusctl.sh generated"
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
            # Validator: only connects to trusted peers, no public peer exchange
            pex_enabled="false"
            addr_book_strict="false"
            ;;
        rpc)
            # RPC: public P2P, peer exchange enabled
            pex_enabled="true"
            addr_book_strict="true"
            ;;
    esac

    log_info "Generating CometBFT config (${NODE_TYPE})..."
    cat > "${config_file}" << EOF
# CometBFT Configuration
# Node Type: ${NODE_TYPE}

proxy_app = "unix://${DATA_DIR}/orqusbft/abci.sock"
moniker = "${MONIKER}"
db_backend = "goleveldb"
db_dir = "data"
log_level = "${LOG_LEVEL}"
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
        rpc)
            # RPC: no slashing, keep recent blocks only
            slashing_enabled="false"
            retain_blocks="100000"  # ~1 day of blocks
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
  listenAddr: "unix://${DATA_DIR}/orqusbft/abci.sock"
  logLevel: "${LOG_LEVEL}"
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
# - rpc: Keep disabled
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
        # Still apply GENESIS_GAS_LIMIT patch if set
        if [ -n "${GENESIS_GAS_LIMIT}" ]; then
            # Check if gasLimit actually changed
            local current_limit
            current_limit=$(python3 -c "
import sys, json
g = json.load(open('${genesis_file}'))
v = g.get('gasLimit', '0x0')
print(int(v, 16) if isinstance(v, str) and v.startswith('0x') else int(v))
" 2>/dev/null || echo "0")
            local new_limit
            new_limit=$(python3 -c "
v='${GENESIS_GAS_LIMIT}'
print(int(v,16) if v.startswith('0x') or v.startswith('0X') else int(v))
" 2>/dev/null || echo "0")

            if [ "${current_limit}" != "${new_limit}" ]; then
                log_warn "GENESIS_GAS_LIMIT changed (${current_limit} -> ${new_limit}), wiping chain data for clean re-init..."
                rm -rf "${DATA_DIR}/reth"
                rm -rf "${DATA_DIR}/cometbft/data"
                rm -rf "${DATA_DIR}/orqusbft"
                mkdir -p "${DATA_DIR}/reth" "${DATA_DIR}/cometbft/data" "${DATA_DIR}/orqusbft"
                echo '{"height":"0","round":0,"step":0}' > "${DATA_DIR}/cometbft/data/priv_validator_state.json"
                log_ok "Chain data wiped"
            fi

            log_info "Patching genesis gasLimit to ${GENESIS_GAS_LIMIT}..."
            python3 - "${genesis_file}" "${GENESIS_GAS_LIMIT}" << 'PYEOF'
import sys, json

path, gas = sys.argv[1], sys.argv[2]

with open(path) as f:
    g = json.load(f)

limit = int(gas, 16) if gas.startswith("0x") or gas.startswith("0X") else int(gas)
g["gasLimit"] = hex(limit)

with open(path, "w") as f:
    json.dump(g, f, indent=2)

print(f"  gasLimit set to {hex(limit)} ({limit:,})")
PYEOF
            log_ok "Genesis gasLimit patched"
        fi
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

    # Patch gasLimit if GENESIS_GAS_LIMIT is set
    if [ -n "${GENESIS_GAS_LIMIT}" ]; then
        log_info "Patching genesis gasLimit to ${GENESIS_GAS_LIMIT}..."
        python3 - "${genesis_file}" "${GENESIS_GAS_LIMIT}" << 'PYEOF'
import sys, json

path, gas = sys.argv[1], sys.argv[2]

with open(path) as f:
    g = json.load(f)

# Accept decimal or hex (0x...)
limit = int(gas, 16) if gas.startswith("0x") or gas.startswith("0X") else int(gas)
g["gasLimit"] = hex(limit)

with open(path, "w") as f:
    json.dump(g, f, indent=2)

print(f"  gasLimit set to {hex(limit)} ({limit:,})")
PYEOF
        log_ok "Genesis gasLimit patched"
    fi

    log_ok "Reth genesis downloaded from ${genesis_url}"
}

# Generate reth.toml configuration with trusted peers
generate_reth_config() {
    local reth_datadir="${DATA_DIR}/reth"
    local config_file="${reth_datadir}/reth.toml"

    mkdir -p "${reth_datadir}"

    # Convert comma-separated trusted peers to TOML array format
    local trusted_nodes_toml="[]"
    if [ -n "${RETH_TRUSTED_PEERS}" ]; then
        # Split by comma and format as TOML array
        trusted_nodes_toml=$(echo "${RETH_TRUSTED_PEERS}" | tr ',' '\n' | while read -r peer; do
            echo "\"${peer}\""
        done | paste -sd, | sed 's/^/[/; s/$/]/')
    fi

    log_info "Generating reth config with trusted peers..."
    cat > "${config_file}" << EOF
# Reth configuration
# Generated by install.sh

[peers]
refill_slots_interval = "5s"
trusted_nodes = ${trusted_nodes_toml}
trusted_nodes_only = false
max_backoff_count = 5
ban_duration = "12h"

[peers.connection_info]
max_outbound = 100
max_inbound = 30
max_concurrent_outbound_dials = 15

[sessions]
session_command_buffer = 32
session_event_buffer = 260

[prune]
block_interval = 5

[prune.segments.merkle_changesets]
distance = 128
EOF
    log_ok "Reth config generated"
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

    # Set permissions for Docker mode (CometBFT container runs as uid 100)
    if [ "${INSTALL_MODE}" = "docker" ]; then
        chmod -R 777 "${cometbft_home}"
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
generate_orqusctl_script() {
    local ctl_script="${INSTALL_DIR}/orqusctl.sh"

    log_info "Generating orqusctl.sh..."
    cat > "${ctl_script}" << 'SCRIPT'
#!/bin/bash
#
# orqusctl.sh - Orqus Chain control script
# Usage: orqusctl.sh <command>
#
# Commands:
#   start     Start all services (reth -> orqusbft -> cometbft)
#   stop      Stop all services
#   restart   Stop then start
#   status    Show running status
#   logs      Tail all logs (or: logs reth|orqusbft|cometbft)
#   download  Download latest snapshot and restore (stops/starts services)
#   reset     Wipe chain data and re-initialize from genesis
#

INSTALL_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${INSTALL_DIR}/env.sh"

start_reth() {
    mkdir -p "${DATA_DIR}/logs"
    RETH_TRUSTED_PEERS_ARG=""
    if [ -n "${RETH_TRUSTED_PEERS}" ]; then
        RETH_TRUSTED_PEERS_ARG="--trusted-peers ${RETH_TRUSTED_PEERS}"
    fi
    echo "Starting orqus-reth..."
    RUST_LOG="${LOG_LEVEL}" "${BIN_DIR}/orqus-reth" node \
        --datadir "${DATA_DIR}/reth" \
        --chain "${CONFIG_DIR}/reth-genesis.json" \
        --http --http.addr 0.0.0.0 --http.port ${RETH_HTTP_PORT} \
        --http.api eth,net,web3,debug,trace \
        --ws --ws.addr 0.0.0.0 --ws.port ${RETH_WS_PORT} \
        --authrpc.addr 0.0.0.0 --authrpc.port ${RETH_ENGINE_PORT} \
        --authrpc.jwtsecret "${CONFIG_DIR}/jwt.hex" \
        --port ${RETH_P2P_PORT} \
        --metrics 0.0.0.0:${RETH_METRICS_PORT} \
        --rpc.max-connections ${RETH_RPC_MAX_CONNECTIONS} \
        --builder.gaslimit ${RETH_BUILDER_GAS_LIMIT} \
        --txpool.pending-max-count ${RETH_TXPOOL_MAX_PENDING} \
        --txpool.queued-max-count ${RETH_TXPOOL_MAX_QUEUED} \
        --txpool.max-account-slots ${RETH_TXPOOL_MAX_ACCOUNT_SLOTS} \
        --txpool.max-pending-txns ${RETH_TXPOOL_MAX_PENDING_TXNS} \
        --txpool.max-new-txns ${RETH_TXPOOL_MAX_NEW_TXNS} \
        ${RETH_TRUSTED_PEERS_ARG} \
        >> "${DATA_DIR}/logs/reth.log" 2>&1 &
    RETH_PID=$!
    echo "  PID: ${RETH_PID}"

    printf "Waiting for reth engine API (port ${RETH_ENGINE_PORT})"
    _elapsed=0
    while true; do
        if nc -z 127.0.0.1 "${RETH_ENGINE_PORT}" 2>/dev/null; then
            printf " (${_elapsed}s)\n"
            break
        fi
        if ! kill -0 "${RETH_PID}" 2>/dev/null; then
            printf "\n"
            echo "ERROR: reth exited unexpectedly, check logs: ${DATA_DIR}/logs/reth.log"
            exit 1
        fi
        printf "."
        sleep 1
        _elapsed=$((_elapsed + 1))
        [ $((_elapsed % 30)) -eq 0 ] && printf "\n  (${_elapsed}s elapsed, still loading...)"
    done
    unset _elapsed
}

start_orqusbft() {
    mkdir -p "${DATA_DIR}/logs"
    echo "Starting orqusbft..."
    "${BIN_DIR}/orqusbft" \
        -config "${CONFIG_DIR}/orqusbft-config.yaml" \
        >> "${DATA_DIR}/logs/orqusbft.log" 2>&1 &
    ORQUSBFT_PID=$!
    echo "  PID: ${ORQUSBFT_PID}"

    printf "Waiting for orqusbft ABCI socket"
    _elapsed=0
    while true; do
        if [ -S "${DATA_DIR}/orqusbft/abci.sock" ]; then
            printf " (${_elapsed}s)\n"
            break
        fi
        if ! kill -0 "${ORQUSBFT_PID}" 2>/dev/null; then
            printf "\n"
            echo "ERROR: orqusbft exited unexpectedly, check logs: ${DATA_DIR}/logs/orqusbft.log"
            exit 1
        fi
        printf "."
        sleep 1
        _elapsed=$((_elapsed + 1))
        [ $((_elapsed % 30)) -eq 0 ] && printf "\n  (${_elapsed}s elapsed, still loading...)"
    done
    unset _elapsed
}

start_cometbft() {
    mkdir -p "${DATA_DIR}/logs"
    echo "Starting cometbft..."
    "${BIN_DIR}/cometbft" start \
        --home "${DATA_DIR}/cometbft" \
        >> "${DATA_DIR}/logs/cometbft.log" 2>&1 &
    echo "  PID: $!"
}

stop_reth() {
    echo "Stopping orqus-reth..."
    pkill -f "orqus-reth" 2>/dev/null || true
}

stop_orqusbft() {
    echo "Stopping orqusbft..."
    pkill -f "orqusbft" 2>/dev/null || true
}

stop_cometbft() {
    echo "Stopping cometbft..."
    pkill -f "cometbft start" 2>/dev/null || true
}

cmd_start() {
    local component="${1:-}"
    case "${component}" in
        reth)      start_reth ;;
        orqusbft)  start_orqusbft ;;
        cometbft)  start_cometbft ;;
        "")
            echo "Starting Orqus Chain..."
            start_reth
            start_orqusbft
            start_cometbft
            echo ""
            echo "All components started!"
            echo "  JSON-RPC:  http://127.0.0.1:${RETH_HTTP_PORT}"
            echo "  WebSocket: ws://127.0.0.1:${RETH_WS_PORT}"
            echo "  CometBFT:  http://127.0.0.1:${COMETBFT_RPC_PORT}"
            ;;
        *)
            echo "Unknown component: ${component}"
            echo "Available: reth, orqusbft, cometbft"
            exit 1
            ;;
    esac
}

cmd_stop() {
    local component="${1:-}"
    case "${component}" in
        reth)      stop_reth ;;
        orqusbft)  stop_orqusbft ;;
        cometbft)  stop_cometbft ;;
        "")
            echo "Stopping Orqus Chain..."
            stop_cometbft
            stop_orqusbft
            stop_reth
            sleep 2
            ;;
        *)
            echo "Unknown component: ${component}"
            echo "Available: reth, orqusbft, cometbft"
            exit 1
            ;;
    esac
    echo "Stopped."
}

cmd_status() {
    echo "Orqus Chain Status:"
    for proc in orqus-reth orqusbft cometbft; do
        if pgrep -f "${proc}" > /dev/null 2>&1; then
            echo "  [UP]   ${proc} (pid: $(pgrep -f ${proc} | head -1))"
        else
            echo "  [DOWN] ${proc}"
        fi
    done
}

cmd_logs() {
    local component="${1:-}"
    case "${component}" in
        reth)      tail -n 100 -f "${DATA_DIR}/logs/reth.log" ;;
        orqusbft)  tail -n 100 -f "${DATA_DIR}/logs/orqusbft.log" ;;
        cometbft)  tail -n 100 -f "${DATA_DIR}/logs/cometbft.log" ;;
        *)         tail -n 100 -f "${DATA_DIR}/logs/reth.log" \
                          "${DATA_DIR}/logs/orqusbft.log" \
                          "${DATA_DIR}/logs/cometbft.log" ;;
    esac
}

cmd_download() {
    local snapshot_url="${SNAPSHOT_URL:-}"
    if [ -z "${snapshot_url}" ] && [ -n "${SNAPSHOT_BASE_URL}" ]; then
        snapshot_url="${SNAPSHOT_BASE_URL}/${NETWORK}/orqus-${NETWORK}-snapshot-latest.tar.gz"
    fi
    if [ -z "${snapshot_url}" ]; then
        echo "Error: SNAPSHOT_BASE_URL or SNAPSHOT_URL not set in env.sh"
        exit 1
    fi

    echo "Snapshot URL: ${snapshot_url}"
    echo "Stopping services..."
    cmd_stop

    local tmp_file="${DATA_DIR}/snapshot.tar.gz"
    echo "Downloading snapshot..."
    curl -L --progress-bar -o "${tmp_file}" "${snapshot_url}"

    # Verify checksum
    local checksum_url="${snapshot_url}.sha256"
    local checksum_file=$(mktemp)
    if curl -sL --connect-timeout 10 "${checksum_url}" -o "${checksum_file}" 2>/dev/null; then
        echo "Verifying checksum..."
        local expected=$(awk '{print $1}' "${checksum_file}")
        local actual=$(sha256sum "${tmp_file}" | awk '{print $1}')
        if [ "${expected}" != "${actual}" ]; then
            echo "Error: Checksum mismatch! expected=${expected} actual=${actual}"
            rm -f "${tmp_file}" "${checksum_file}"
            exit 1
        fi
        echo "Checksum OK"
    fi
    rm -f "${checksum_file}"

    echo "Clearing existing chain data..."
    rm -rf "${DATA_DIR}/reth" "${DATA_DIR}/cometbft/data" "${DATA_DIR}/orqusbft"

    echo "Extracting snapshot to ${DATA_DIR}..."
    tar -xzf "${tmp_file}" -C "${DATA_DIR}"
    rm -f "${tmp_file}"

    # Restore node-specific files overwritten by snapshot
    cp "${CONFIG_DIR}/priv_validator_key.json" "${DATA_DIR}/cometbft/config/priv_validator_key.json" 2>/dev/null || true
    cp "${CONFIG_DIR}/node_key.json" "${DATA_DIR}/cometbft/config/node_key.json" 2>/dev/null || true
    cp "${CONFIG_DIR}/cometbft-config.toml" "${DATA_DIR}/cometbft/config/config.toml" 2>/dev/null || true

    # Ensure priv_validator_state.json exists (snapshot may not include it)
    mkdir -p "${DATA_DIR}/cometbft/data"
    if [ ! -f "${DATA_DIR}/cometbft/data/priv_validator_state.json" ]; then
        echo '{"height":"0","round":0,"step":0}' > "${DATA_DIR}/cometbft/data/priv_validator_state.json"
    fi

    echo ""
    echo "Snapshot restored. Start the chain with:"
    echo "  $(basename $0) start"
}

cmd_reset() {
    echo "WARNING: This will delete all chain data and start fresh from genesis!"
    read -p "Are you sure? (yes/no): " confirm
    if [ "${confirm}" != "yes" ]; then
        echo "Aborted."
        exit 0
    fi

    echo "Stopping services..."
    cmd_stop

    echo "Wiping chain data..."
    rm -rf "${DATA_DIR}/reth"
    rm -rf "${DATA_DIR}/cometbft/data"
    rm -rf "${DATA_DIR}/orqusbft"   # must reset together with cometbft to keep app hash in sync

    echo "Re-initializing reth..."
    mkdir -p "${DATA_DIR}/reth"
    "${BIN_DIR}/orqus-reth" init \
        --datadir "${DATA_DIR}/reth" \
        --chain "${CONFIG_DIR}/reth-genesis.json" \
        2>/dev/null || true

    echo "Re-initializing cometbft data..."
    mkdir -p "${DATA_DIR}/cometbft/config" "${DATA_DIR}/cometbft/data"
    cp "${CONFIG_DIR}/genesis.json" "${DATA_DIR}/cometbft/config/genesis.json"
    cp "${CONFIG_DIR}/cometbft-config.toml" "${DATA_DIR}/cometbft/config/config.toml"
    cp "${CONFIG_DIR}/priv_validator_key.json" "${DATA_DIR}/cometbft/config/priv_validator_key.json"
    cp "${CONFIG_DIR}/node_key.json" "${DATA_DIR}/cometbft/config/node_key.json"
    echo '{"height":"0","round":0,"step":0}' > "${DATA_DIR}/cometbft/data/priv_validator_state.json"

    echo ""
    echo "Reset complete. Start the chain with:"
    echo "  $(basename $0) start"
}

case "${1:-}" in
    start)    cmd_start "${2:-}" ;;
    stop)     cmd_stop "${2:-}" ;;
    restart)  cmd_stop "${2:-}"; cmd_start "${2:-}" ;;
    status)   cmd_status ;;
    logs)     cmd_logs "${2:-}" ;;
    download) cmd_download ;;
    reset)    cmd_reset ;;
    *)
        echo "Usage: $(basename $0) <command> [component]"
        echo ""
        echo "Commands:"
        echo "  start     [reth|orqusbft|cometbft]  Start all or a specific service"
        echo "  stop      [reth|orqusbft|cometbft]  Stop all or a specific service"
        echo "  restart   [reth|orqusbft|cometbft]  Restart all or a specific service"
        echo "  status    Show process status"
        echo "  logs      [reth|orqusbft|cometbft]  Tail logs"
        echo "  download  Download latest snapshot and restore"
        echo "  reset     Wipe data and re-initialize from genesis"
        exit 1
        ;;
esac
SCRIPT
    chmod +x "${ctl_script}"
    log_ok "orqusctl.sh generated"
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
export NETWORK="${NETWORK}"
export NODE_TYPE="${NODE_TYPE}"
export MONIKER="${MONIKER}"

# P2P peers
export SEEDS="${SEEDS}"
export PERSISTENT_PEERS="${PERSISTENT_PEERS}"
export RETH_TRUSTED_PEERS="${RETH_TRUSTED_PEERS}"

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

# Snapshot
export SNAPSHOT_BASE_URL="${SNAPSHOT_BASE_URL}"

# Genesis (informational, immutable after reth init)
export GENESIS_GAS_LIMIT="${GENESIS_GAS_LIMIT}"

# Log level
export LOG_LEVEL="${LOG_LEVEL}"

# Reth performance tuning
export RETH_RPC_MAX_CONNECTIONS="${RETH_RPC_MAX_CONNECTIONS}"
export RETH_BUILDER_GAS_LIMIT="${RETH_BUILDER_GAS_LIMIT}"
export RETH_TXPOOL_MAX_PENDING="${RETH_TXPOOL_MAX_PENDING}"
export RETH_TXPOOL_MAX_QUEUED="${RETH_TXPOOL_MAX_QUEUED}"
export RETH_TXPOOL_MAX_ACCOUNT_SLOTS="${RETH_TXPOOL_MAX_ACCOUNT_SLOTS}"
export RETH_TXPOOL_MAX_PENDING_TXNS="${RETH_TXPOOL_MAX_PENDING_TXNS}"
export RETH_TXPOOL_MAX_NEW_TXNS="${RETH_TXPOOL_MAX_NEW_TXNS}"

# Add bin to PATH
export PATH="\${BIN_DIR}:\${PATH}"
EOF
}

# Reconfigure existing installation (regenerate configs without touching data/binaries)
do_reconfigure() {
    echo ""
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║           Orqus Chain - Reconfigure                       ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""

    if [ ! -d "${INSTALL_DIR}" ]; then
        log_error "No existing installation found at ${INSTALL_DIR}"
        log_error "Run install first"
        exit 1
    fi

    if [ -f "${INSTALL_DIR}/docker-compose.yml" ]; then
        log_error "reconfigure is not supported in docker mode"
        log_error "Edit docker-compose.yml manually and run: docker compose up -d"
        exit 1
    fi

    # Load stored settings from env.sh, then re-apply any user-provided overrides
    if [ -f "${INSTALL_DIR}/env.sh" ]; then
        source "${INSTALL_DIR}/env.sh"
    fi

    [ -n "${_USER_NODE_TYPE}" ]          && NODE_TYPE="${_USER_NODE_TYPE}"
    [ -n "${_USER_MONIKER}" ]            && MONIKER="${_USER_MONIKER}"
    [ -n "${_USER_SEEDS}" ]              && SEEDS="${_USER_SEEDS}"
    [ -n "${_USER_PERSISTENT_PEERS}" ]   && PERSISTENT_PEERS="${_USER_PERSISTENT_PEERS}"
    [ -n "${_USER_RETH_TRUSTED_PEERS}" ] && RETH_TRUSTED_PEERS="${_USER_RETH_TRUSTED_PEERS}"
    [ -n "${_USER_NETWORK}" ]            && NETWORK="${_USER_NETWORK}"
    [ -n "${_USER_SNAPSHOT_BASE_URL}" ]  && SNAPSHOT_BASE_URL="${_USER_SNAPSHOT_BASE_URL}"

    # Apply PROFILE preset (before individual overrides so explicit vars still win)
    case "${_USER_PROFILE}" in
        benchmark)
            log_info "Applying benchmark profile..."
            LOG_LEVEL=error
            RETH_RPC_MAX_CONNECTIONS=100000
            RETH_TXPOOL_MAX_PENDING=500000
            RETH_TXPOOL_MAX_QUEUED=500000
            RETH_TXPOOL_MAX_ACCOUNT_SLOTS=10000
            RETH_TXPOOL_MAX_PENDING_TXNS=1000000
            RETH_TXPOOL_MAX_NEW_TXNS=500000
            # Note: GENESIS_GAS_LIMIT is not set here because genesis is immutable after init.
            # Set GENESIS_GAS_LIMIT during first install, not reconfigure.
            ;;
        default|"")
            ;;
        *)
            log_error "Unknown PROFILE: ${_USER_PROFILE} (valid: benchmark, default)"
            exit 1
            ;;
    esac

    # Individual perf overrides (win over profile preset)
    [ -n "${_USER_RETH_RPC_MAX_CONNECTIONS}" ]    && RETH_RPC_MAX_CONNECTIONS="${_USER_RETH_RPC_MAX_CONNECTIONS}"
    [ -n "${_USER_RETH_BUILDER_GAS_LIMIT}" ]      && RETH_BUILDER_GAS_LIMIT="${_USER_RETH_BUILDER_GAS_LIMIT}"
    [ -n "${_USER_RETH_TXPOOL_MAX_PENDING}" ]     && RETH_TXPOOL_MAX_PENDING="${_USER_RETH_TXPOOL_MAX_PENDING}"
    [ -n "${_USER_RETH_TXPOOL_MAX_QUEUED}" ]      && RETH_TXPOOL_MAX_QUEUED="${_USER_RETH_TXPOOL_MAX_QUEUED}"
    [ -n "${_USER_RETH_TXPOOL_MAX_ACCOUNT_SLOTS}" ] && RETH_TXPOOL_MAX_ACCOUNT_SLOTS="${_USER_RETH_TXPOOL_MAX_ACCOUNT_SLOTS}"
    [ -n "${_USER_RETH_TXPOOL_MAX_PENDING_TXNS}" ] && RETH_TXPOOL_MAX_PENDING_TXNS="${_USER_RETH_TXPOOL_MAX_PENDING_TXNS}"
    [ -n "${_USER_RETH_TXPOOL_MAX_NEW_TXNS}" ]    && RETH_TXPOOL_MAX_NEW_TXNS="${_USER_RETH_TXPOOL_MAX_NEW_TXNS}"
    [ -n "${_USER_LOG_LEVEL}" ]                   && LOG_LEVEL="${_USER_LOG_LEVEL}"

    # Auto-derive RETH_BUILDER_GAS_LIMIT from GENESIS_GAS_LIMIT when:
    # - GENESIS_GAS_LIMIT is set (non-default genesis), AND
    # - RETH_BUILDER_GAS_LIMIT was NOT explicitly provided by the user
    # This ensures reth targets the same gas limit as genesis instead of drifting back to default.
    if [ -n "${GENESIS_GAS_LIMIT}" ] && [ -z "${_USER_RETH_BUILDER_GAS_LIMIT}" ]; then
        RETH_BUILDER_GAS_LIMIT="${GENESIS_GAS_LIMIT}"
    fi

    log_info "Applying configuration:"
    log_info "  Node type:        ${NODE_TYPE}"
    log_info "  Moniker:          ${MONIKER}"
    log_info "  Seeds:            ${SEEDS:-<none>}"
    log_info "  Persistent peers: ${PERSISTENT_PEERS:-<none>}"
    log_info "  Reth peers:       ${RETH_TRUSTED_PEERS:-<none>}"
    log_info "  Network:          ${NETWORK}"
    if [ -n "${_USER_PROFILE}" ]; then
        log_info "  Profile:          ${_USER_PROFILE}"
        log_info "  Log level:        ${LOG_LEVEL}"
        log_info "  Builder gas:      ${RETH_BUILDER_GAS_LIMIT}"
        log_info "  RPC max conn:     ${RETH_RPC_MAX_CONNECTIONS}"
        log_info "  Txpool pending:   ${RETH_TXPOOL_MAX_PENDING_TXNS}"
    fi

    log_info "Stopping services..."
    "${INSTALL_DIR}/orqusctl.sh" stop 2>/dev/null || true
    sleep 2

    log_info "Regenerating configuration files..."
    generate_env_file
    generate_cometbft_config
    generate_orqusbft_config
    generate_reth_config
    generate_orqusctl_script

    # Apply cometbft config to live data directory
    if [ -d "${DATA_DIR}/cometbft/config" ]; then
        cp "${CONFIG_DIR}/cometbft-config.toml" "${DATA_DIR}/cometbft/config/config.toml"
        log_ok "CometBFT live config updated"
    fi

    echo ""
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║               Reconfiguration Complete!                   ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""
    echo "Node type: ${NODE_TYPE}"
    echo ""
    echo "To start the chain:"
    echo "  ${INSTALL_DIR}/orqusctl.sh start"
    echo ""
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
        sed -i.bak "s|cometbft/cometbft:[^[:space:]]*|cometbft/cometbft:${COMETBFT_VERSION}|g" "${INSTALL_DIR}/docker-compose.yml"
        rm -f "${INSTALL_DIR}/docker-compose.yml.bak"

        log_info "Starting containers with new images..."
        docker compose up -d

    else
        # ==================== Binary Mode Upgrade ====================

        # Check if binary needs updating by comparing sha256 with release
        # Returns 0 (needs update) or 1 (already up to date)
        binary_needs_update() {
            local name=$1
            local remote_url=$2
            local local_bin="${BIN_DIR}/${name}"

            # No local binary → always download
            [ -f "${local_bin}" ] || return 0

            # Download remote sha256 (tiny file, ~89 bytes)
            local remote_sha256
            remote_sha256=$(curl -fsSL "${remote_url}.sha256" 2>/dev/null | awk '{print $1}')
            [ -z "${remote_sha256}" ] && return 0   # can't fetch → assume update needed

            local local_sha256
            local_sha256=$(sha256sum "${local_bin}" | awk '{print $1}')

            [ "${local_sha256}" != "${remote_sha256}" ]
        }

        if [ "${OS}" != "linux" ] || [ "${ARCH}" != "amd64" ]; then
            log_error "Binary upgrade only available for linux-amd64"
            exit 1
        fi

        RETH_URL="${RELEASE_URL}/orqus-reth-linux-amd64"
        ORQUSBFT_URL="${RELEASE_URL}/orqusbft-linux-amd64"
        COMETBFT_URL="${RELEASE_URL}/cometbft-linux-amd64"

        needs_reth=$(binary_needs_update "orqus-reth" "${RETH_URL}" && echo yes || echo no)
        needs_orqusbft=$(binary_needs_update "orqusbft" "${ORQUSBFT_URL}" && echo yes || echo no)
        needs_cometbft=$(binary_needs_update "cometbft" "${COMETBFT_URL}" && echo yes || echo no)

        if [ "${needs_reth}" = no ] && [ "${needs_orqusbft}" = no ] && [ "${needs_cometbft}" = no ]; then
            log_ok "All binaries already up to date (${LATEST_VERSION}), nothing to do."
        else
            log_info "Stopping services..."
            "${INSTALL_DIR}/orqusctl.sh" stop 2>/dev/null || true
            sleep 2

            # Backup and download only changed binaries
            for bin in orqus-reth orqusbft cometbft; do
                [ -f "${BIN_DIR}/${bin}" ] && mv "${BIN_DIR}/${bin}" "${BIN_DIR}/${bin}.bak"
            done

            if [ "${needs_reth}" = yes ]; then
                log_info "Updating orqus-reth..."
                download_binary "orqus-reth" "${RETH_URL}"
            else
                log_info "orqus-reth unchanged, skipping"
                mv "${BIN_DIR}/orqus-reth.bak" "${BIN_DIR}/orqus-reth"
            fi

            if [ "${needs_orqusbft}" = yes ]; then
                log_info "Updating orqusbft..."
                download_binary "orqusbft" "${ORQUSBFT_URL}"
            else
                log_info "orqusbft unchanged, skipping"
                mv "${BIN_DIR}/orqusbft.bak" "${BIN_DIR}/orqusbft"
            fi

            if [ "${needs_cometbft}" = yes ]; then
                log_info "Updating cometbft..."
                download_binary "cometbft" "${COMETBFT_URL}"
            else
                log_info "cometbft unchanged, skipping"
                mv "${BIN_DIR}/cometbft.bak" "${BIN_DIR}/cometbft"
            fi

            # Clean up any remaining backups
            for bin in orqus-reth orqusbft cometbft; do
                rm -f "${BIN_DIR}/${bin}.bak"
            done

            log_info "Upgrade complete. Start the chain with:"
            log_info "  ${INSTALL_DIR}/orqusctl.sh start"
        fi
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
        echo "  ${INSTALL_DIR}/orqusctl.sh start"
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
        validator|rpc) ;;
        *)
            log_error "Invalid NODE_TYPE: ${NODE_TYPE}"
            log_error "Valid options: rpc, validator"
            exit 1
            ;;
    esac

    log_info "Installation mode: ${INSTALL_MODE}"
    log_info "Node type: ${NODE_TYPE}"

    detect_platform

    # Check Docker for docker mode
    if [ "${INSTALL_MODE}" = "docker" ]; then
        if ! command -v docker &> /dev/null; then
            install_docker
        fi
        if ! docker compose version &> /dev/null && ! docker-compose version &> /dev/null; then
            log_error "Docker Compose is not installed (expected to be bundled with Docker CE)."
            log_error "Please install Docker manually: https://docs.docker.com/engine/install/"
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

        # Auto-fetch peers if not explicitly set
        fetch_peers

        # Generate configurations
        generate_jwt_secret
        generate_validator_key
        generate_cometbft_genesis
        generate_cometbft_config
        generate_orqusbft_config
        download_reth_genesis
        generate_reth_config

        # Initialize from genesis (use 'orqusctl.sh download' to restore from snapshot instead)
        setup_cometbft
        init_reth

        # Generate scripts
        generate_env_file
        generate_orqusctl_script

    else
        # ==================== Docker Mode ====================
        # Pull Docker images
        pull_docker_images

        # Auto-fetch peers if not explicitly set
        fetch_peers

        # Generate configurations
        generate_jwt_secret
        generate_validator_key_docker
        generate_cometbft_genesis
        generate_cometbft_config
        generate_orqusbft_config_docker
        download_reth_genesis
        generate_reth_config

        # Initialize from genesis (use 'orqusctl.sh download' to restore from snapshot instead)
        setup_cometbft

        # Generate Docker files
        generate_docker_compose
        generate_env_file
        generate_docker_orqusctl_script
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
    echo "Data source: Genesis (full sync)"
    echo ""
    echo "To start the chain:"
    echo "  ${INSTALL_DIR}/orqusctl.sh start"
    echo ""
    echo "To fast-sync from snapshot instead (recommended for RPC nodes):"
    echo "  ${INSTALL_DIR}/orqusctl.sh download"
    echo ""
    echo "To stop the chain:"
    echo "  ${INSTALL_DIR}/orqusctl.sh stop"
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
    reconfigure)
        do_reconfigure
        ;;
    install|"")
        main
        ;;
    *)
        echo "Usage: $0 [install|upgrade|reconfigure]"
        echo ""
        echo "Commands:"
        echo "  install       Install Orqus Chain (default)"
        echo "  upgrade       Upgrade binaries to latest version"
        echo "  reconfigure   Regenerate configs from environment variables"
        echo "                Example: NODE_TYPE=validator ~/.orqus/install.sh reconfigure"
        echo "                Example: PROFILE=benchmark ~/.orqus/install.sh reconfigure"
        exit 1
        ;;
esac
