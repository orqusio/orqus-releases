#!/bin/bash
#
# Orqus Chain - One-click Install & Upgrade Script (Simplex Architecture)
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
#
#   # Join testnet (peers are auto-fetched from GitHub)
#   curl -sSL https://raw.githubusercontent.com/orqusio/orqus-releases/main/install.sh | NETWORK=testnet bash
#
#   # Join as RPC node with snapshot (recommended)
#   curl -sSL https://raw.githubusercontent.com/orqusio/orqus-releases/main/install.sh | NODE_TYPE=rpc NETWORK=testnet bash
#
#   # Join as RPC follower (explicit follow source)
#   curl -sSL https://raw.githubusercontent.com/orqusio/orqus-releases/main/install.sh | NODE_TYPE=rpc FOLLOW_URL=ws://10.100.82.145:8546 NETWORK=testnet bash
#
#   # Override peers manually (skips auto-fetch)
#   export BOOTSTRAP_PEERS="/dns4/node1.orqus.io/tcp/26600/p2p/PUBKEY"
#   export RETH_TRUSTED_PEERS="enode://pubkey@sentry1.orqus.io:30303"
#   curl -sSL https://raw.githubusercontent.com/orqusio/orqus-releases/main/install.sh | bash
#
#   # Upgrade existing installation
#   ~/.orqus/install.sh upgrade
#   # Or:
#   curl -sSL https://raw.githubusercontent.com/orqusio/orqus-releases/main/install.sh | bash -s -- upgrade
#
# Architecture: Single process (orqus-reth with embedded Simplex consensus)
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
_USER_BOOTSTRAP_PEERS="${BOOTSTRAP_PEERS:-}"
_USER_RETH_TRUSTED_PEERS="${RETH_TRUSTED_PEERS:-}"
_USER_NETWORK="${NETWORK:-}"
_USER_SNAPSHOT_BASE_URL="${SNAPSHOT_BASE_URL:-}"
_USER_PROFILE="${PROFILE:-}"
_USER_FEE_RECIPIENT="${FEE_RECIPIENT:-}"
_USER_RETH_RPC_MAX_CONNECTIONS="${RETH_RPC_MAX_CONNECTIONS:-}"
_USER_RETH_BUILDER_GAS_LIMIT="${RETH_BUILDER_GAS_LIMIT:-}"
_USER_RETH_TXPOOL_MAX_PENDING="${RETH_TXPOOL_MAX_PENDING:-}"
_USER_RETH_TXPOOL_MAX_QUEUED="${RETH_TXPOOL_MAX_QUEUED:-}"
_USER_RETH_TXPOOL_MAX_ACCOUNT_SLOTS="${RETH_TXPOOL_MAX_ACCOUNT_SLOTS:-}"
_USER_RETH_TXPOOL_MAX_PENDING_TXNS="${RETH_TXPOOL_MAX_PENDING_TXNS:-}"
_USER_RETH_TXPOOL_MAX_NEW_TXNS="${RETH_TXPOOL_MAX_NEW_TXNS:-}"
_USER_LOG_LEVEL="${LOG_LEVEL:-}"
_USER_FOLLOW_URL="${FOLLOW_URL:-}"

# Docker image registry
DOCKER_REGISTRY="${DOCKER_REGISTRY:-ghcr.io/orqusio}"

# Chain parameters
CHAIN_ID="${ORQUS_CHAIN_ID:-888888}"
MONIKER="${ORQUS_MONIKER:-orqus-node}"

# GitHub repository for releases and peer discovery
GITHUB_REPO="${GITHUB_REPO:-orqusio/orqus-releases}"

# Node type: validator, rpc
NODE_TYPE="${NODE_TYPE:-validator}"

# Consensus bootstrap peers (Simplex multiaddr format)
BOOTSTRAP_PEERS="${BOOTSTRAP_PEERS:-}"

# Reth P2P peers - Format: "enode://pubkey@ip:port,enode://pubkey@ip:port"
RETH_TRUSTED_PEERS="${RETH_TRUSTED_PEERS:-}"

# Optional RPC follower source (recommended for NODE_TYPE=rpc)
# Example: ws://10.100.82.145:8546
FOLLOW_URL="${FOLLOW_URL:-}"

# Peers URL: auto-constructed from GitHub raw URL based on NETWORK
PEERS_URL="${PEERS_URL:-}"

# Fee recipient address for block rewards (ETH address)
FEE_RECIPIENT="${FEE_RECIPIENT:-0x0000000000000000000000000000000000000000}"

# Genesis URL (for joining existing network)
GENESIS_URL="${GENESIS_URL:-}"

# Override genesis gasLimit after download (decimal or hex, e.g. 70000000 or 0x42C1D80)
GENESIS_GAS_LIMIT="${GENESIS_GAS_LIMIT:-}"

# Snapshot configuration
SNAPSHOT_URL="${SNAPSHOT_URL:-}"
SNAPSHOT_BASE_URL="${SNAPSHOT_BASE_URL:-https://orqus-snapshots.oss-cn-hongkong.aliyuncs.com}"
NETWORK="${NETWORK:-testnet}"

# Ports
RETH_HTTP_PORT="${RETH_HTTP_PORT:-8545}"
RETH_WS_PORT="${RETH_WS_PORT:-8546}"
RETH_P2P_PORT="${RETH_P2P_PORT:-30303}"
RETH_METRICS_PORT="${RETH_METRICS_PORT:-9001}"
CONSENSUS_PORT="${CONSENSUS_PORT:-26600}"
CONSENSUS_METRICS_PORT="${CONSENSUS_METRICS_PORT:-26700}"

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
# Peers JSON format: { "consensus": { "bootstrap_peers": "..." }, "reth": { "trusted_peers": "..." } }
fetch_peers() {
    # Skip if both are already set by user
    if [ -n "${BOOTSTRAP_PEERS}" ] && [ -n "${RETH_TRUSTED_PEERS}" ]; then
        log_info "Peers already configured, skipping auto-fetch"
        return
    fi

    local peers_url="${PEERS_URL:-https://raw.githubusercontent.com/${GITHUB_REPO}/main/peers/${NETWORK}.json}"
    log_info "Fetching peers from ${peers_url}..."

    local peers_json
    peers_json=$(curl -fsSL --retry 2 --retry-delay 1 "${peers_url}" 2>/dev/null) || {
        log_warn "Could not fetch peers from ${peers_url}, continuing without auto-discovered peers"
        return
    }

    # Parse JSON (portable: use grep+sed, no jq dependency)
    if [ -z "${BOOTSTRAP_PEERS}" ]; then
        local consensus_peers
        consensus_peers=$(echo "${peers_json}" | grep '"bootstrap_peers"' | sed -E 's/.*"bootstrap_peers"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')
        if [ -n "${consensus_peers}" ]; then
            BOOTSTRAP_PEERS="${consensus_peers}"
            log_ok "Auto-discovered consensus bootstrap peers: ${BOOTSTRAP_PEERS}"
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

    if [ -z "${FOLLOW_URL}" ]; then
        local follow_url
        follow_url=$(echo "${peers_json}" | grep '"follow_url"' | sed -E 's/.*"follow_url"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')
        if [ -n "${follow_url}" ]; then
            FOLLOW_URL="${follow_url}"
            log_ok "Auto-discovered follow URL: ${FOLLOW_URL}"
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

# Check if snapshot is available
check_snapshot_available() {
    local url="$1"
    if curl -sI --connect-timeout 10 "${url}" 2>/dev/null | head -1 | grep -q "200"; then
        return 0
    fi
    return 1
}

# Get snapshot URL (direct URL or auto-discover from base URL)
get_snapshot_url() {
    if [ -n "${SNAPSHOT_URL}" ]; then
        echo "${SNAPSHOT_URL}"
        return
    fi
    if [ -n "${SNAPSHOT_BASE_URL}" ]; then
        echo "${SNAPSHOT_BASE_URL}/${NETWORK}/orqus-${NETWORK}-snapshot-latest.tar.gz"
        return
    fi
    echo ""
}

# Download and restore snapshot
download_snapshot() {
    local snapshot_url
    snapshot_url=$(get_snapshot_url)

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
    local metadata_file
    metadata_file=$(mktemp)
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
    local checksum_file
    checksum_file=$(mktemp)
    if curl -sL --connect-timeout 10 "${checksum_url}" -o "${checksum_file}" 2>/dev/null; then
        log_info "Verifying snapshot checksum..."
        local expected_hash
        expected_hash=$(awk '{print $1}' "${checksum_file}")
        local actual_hash
        actual_hash=$(sha256sum "${snapshot_file}" | awk '{print $1}')
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

    SNAPSHOT_RESTORED=true
    return 0
}

# Generate signing key (ed25519 private key for Simplex consensus)
generate_signing_key() {
    local signing_key_file="${CONFIG_DIR}/signing.key"

    if [ ! -f "${signing_key_file}" ]; then
        log_info "Generating ed25519 signing key..."
        python3 -c "
import os, sys
seed = os.urandom(32)
print('0x' + seed.hex())
" > "${signing_key_file}"
        chmod 600 "${signing_key_file}"
        log_ok "Signing key generated"
    else
        log_info "Signing key already exists"
    fi
}

# Generate enode key (secp256k1 private key for devp2p)
generate_enode_key() {
    local enode_key_file="${CONFIG_DIR}/enode.key"

    if [ ! -f "${enode_key_file}" ]; then
        log_info "Generating enode key (secp256k1)..."
        # openssl ecparam generates a valid secp256k1 private key
        # reth expects a raw 32-byte hex file
        python3 -c "
import os, hashlib
while True:
    key = os.urandom(32)
    # secp256k1 order
    n = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
    if 0 < int.from_bytes(key, 'big') < n:
        print(key.hex())
        break
" > "${enode_key_file}"
        chmod 600 "${enode_key_file}"
        log_ok "Enode key generated"
    else
        log_info "Enode key already exists"
    fi
}

# Derive ETH address from signing key (for display / fee recipient default)
derive_eth_address() {
    local signing_key_file="${CONFIG_DIR}/signing.key"

    ETH_ADDRESS=$(python3 -c "
try:
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
    import hashlib
    key_hex = open('${signing_key_file}').read().strip()
    if key_hex.startswith('0x'):
        key_hex = key_hex[2:]
    seed = bytes.fromhex(key_hex)
    private_key = Ed25519PrivateKey.from_private_bytes(seed)
    pk = private_key.public_key()
    public_bytes = pk.public_bytes_raw() if hasattr(pk, 'public_bytes_raw') else pk.public_key_raw()
    # Derive address: keccak256(pubkey)[-20:]
    import hashlib as _hl
    try:
        from Crypto.Hash import keccak as _keccak
        h = _keccak.new(digest_bits=256)
        h.update(public_bytes)
        addr = h.digest()[-20:]
    except ImportError:
        try:
            h = _hl.new('sha3_256')
            h.update(public_bytes)
            addr = h.digest()[-20:]
        except Exception:
            addr = _hl.sha256(public_bytes).digest()[-20:]
    print('0x' + addr.hex())
except Exception:
    print('0x0000000000000000000000000000000000000000')
" 2>/dev/null || echo "0x0000000000000000000000000000000000000000")
}

# Derive ed25519 public key hex from signing key (for logging)
derive_signing_pubkey() {
    local signing_key_file="${CONFIG_DIR}/signing.key"

    SIGNING_PUBKEY=$(python3 -c "
try:
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
    key_hex = open('${signing_key_file}').read().strip()
    if key_hex.startswith('0x'):
        key_hex = key_hex[2:]
    seed = bytes.fromhex(key_hex)
    private_key = Ed25519PrivateKey.from_private_bytes(seed)
    pk = private_key.public_key()
    public_bytes = pk.public_bytes_raw() if hasattr(pk, 'public_bytes_raw') else pk.public_key_raw()
    print(public_bytes.hex())
except Exception:
    print('<unavailable>')
" 2>/dev/null || echo "<unavailable>")
}

# Download genesis.json from release or custom URL
download_genesis() {
    local genesis_file="${CONFIG_DIR}/genesis.json"

    if [ -f "${genesis_file}" ]; then
        log_info "Genesis file already exists, skipping download"
        # Still apply GENESIS_GAS_LIMIT patch if set
        if [ -n "${GENESIS_GAS_LIMIT}" ]; then
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
                mkdir -p "${DATA_DIR}/reth"
                log_ok "Chain data wiped"
            fi

            patch_genesis_gas_limit "${genesis_file}"
        fi
        return
    fi

    # Use GENESIS_URL if set, otherwise fall back to release URL
    local genesis_url
    if [ -n "${GENESIS_URL}" ]; then
        genesis_url="${GENESIS_URL}"
        log_info "Downloading genesis from custom URL..."
    else
        genesis_url="${RELEASE_URL}/genesis.json"
        log_info "Downloading genesis from release..."
    fi

    if ! curl -sL -o "${genesis_file}" "${genesis_url}"; then
        log_error "Failed to download genesis from ${genesis_url}"
        exit 1
    fi

    # Verify it's valid JSON
    if ! python3 -c "import json; json.load(open('${genesis_file}'))" 2>/dev/null; then
        log_error "Downloaded genesis is not valid JSON"
        rm -f "${genesis_file}"
        exit 1
    fi

    # Patch gasLimit if GENESIS_GAS_LIMIT is set
    if [ -n "${GENESIS_GAS_LIMIT}" ]; then
        patch_genesis_gas_limit "${genesis_file}"
    fi

    log_ok "Genesis downloaded from ${genesis_url}"
}

# Patch genesis gasLimit
patch_genesis_gas_limit() {
    local genesis_file="$1"
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
}

# Initialize orqus-reth database
init_reth() {
    local reth_datadir="${DATA_DIR}/reth"

    log_info "Initializing orqus-reth..."
    mkdir -p "${reth_datadir}"

    "${BIN_DIR}/orqus-reth" init \
        --datadir "${reth_datadir}" \
        --chain "${CONFIG_DIR}/genesis.json" \
        2>/dev/null || true

    log_ok "orqus-reth initialized"
}

# Pull Docker image
pull_docker_image() {
    log_info "Pulling Docker image..."

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

    log_ok "Docker image pulled"
}

# Generate docker-compose.yml (single container)
generate_docker_compose() {
    local compose_file="${INSTALL_DIR}/docker-compose.yml"

    # Build consensus args
    local consensus_args=""
    local follow_arg=""
    if [ "${NODE_TYPE}" = "validator" ]; then
        consensus_args="--consensus.signing-key /config/signing.key"
        consensus_args="${consensus_args} --consensus.fee-recipient ${FEE_RECIPIENT}"
        consensus_args="${consensus_args} --consensus.listen-address 0.0.0.0:26600"
        consensus_args="${consensus_args} --consensus.metrics-address 0.0.0.0:26700"
        consensus_args="${consensus_args} --consensus.allow-private-ips"
    else
        if [ -n "${FOLLOW_URL}" ]; then
            follow_arg="--follow ${FOLLOW_URL}"
        fi
    fi

    local bootstrap_arg=""
    if [ -n "${BOOTSTRAP_PEERS}" ]; then
        bootstrap_arg="--consensus.bootstrap-peers ${BOOTSTRAP_PEERS}"
    fi

    local trusted_peers_arg=""
    if [ -n "${RETH_TRUSTED_PEERS}" ]; then
        trusted_peers_arg="--trusted-peers ${RETH_TRUSTED_PEERS}"
    fi

    log_info "Generating docker-compose.yml..."
    cat > "${compose_file}" << EOF
services:
  orqus-reth:
    image: ${DOCKER_REGISTRY}/orqus-reth:${DOCKER_TAG}
    container_name: orqus-reth
    restart: unless-stopped
    ports:
      - "${RETH_HTTP_PORT}:8545"
      - "${RETH_WS_PORT}:8546"
      - "${RETH_P2P_PORT}:30303/tcp"
      - "${RETH_P2P_PORT}:30303/udp"
      - "${RETH_METRICS_PORT}:9001"
      - "${CONSENSUS_PORT}:26600/tcp"
      - "${CONSENSUS_PORT}:26600/udp"
      - "${CONSENSUS_METRICS_PORT}:26700"
    volumes:
      - ${DATA_DIR}/reth:/data
      - ${CONFIG_DIR}/genesis.json:/genesis.json:ro
      - ${CONFIG_DIR}/signing.key:/config/signing.key:ro
      - ${CONFIG_DIR}/enode.key:/config/enode.key:ro
      - ${DATA_DIR}/logs:/logs
    command: >
      node
      --chain /genesis.json
      --datadir /data
      --log.file.directory /logs
      --log.file.filter ${LOG_LEVEL}
      --log.stdout.filter ${LOG_LEVEL}
      --http --http.addr 0.0.0.0 --http.port 8545
      --http.api eth,net,web3,debug,trace
      --ws --ws.addr 0.0.0.0 --ws.port 8546
      --port 30303
      --discovery.port 30303
      --p2p-secret-key /config/enode.key
      --metrics 0.0.0.0:9001
      --rpc.max-connections ${RETH_RPC_MAX_CONNECTIONS}
      --builder.gaslimit ${RETH_BUILDER_GAS_LIMIT}
      --txpool.pending-max-count ${RETH_TXPOOL_MAX_PENDING}
      --txpool.queued-max-count ${RETH_TXPOOL_MAX_QUEUED}
      --txpool.max-account-slots ${RETH_TXPOOL_MAX_ACCOUNT_SLOTS}
      --txpool.max-pending-txns ${RETH_TXPOOL_MAX_PENDING_TXNS}
      --txpool.max-new-txns ${RETH_TXPOOL_MAX_NEW_TXNS}
      ${consensus_args}
      ${bootstrap_arg}
      ${trusted_peers_arg}
      ${follow_arg}
    environment:
      - RUST_LOG=${LOG_LEVEL}
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://127.0.0.1:8545 --post-data '{\"jsonrpc\":\"2.0\",\"method\":\"net_version\",\"params\":[],\"id\":1}' || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 5
EOF
    log_ok "docker-compose.yml generated"
}

# Generate Docker orqusctl.sh
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
#   start     Start container (docker compose up -d)
#   stop      Stop container (docker compose down)
#   restart   Restart container
#   status    Show container status
#   logs      Tail logs
#   download  Download latest snapshot and restore
#   reset     Wipe chain data and re-initialize from genesis
#

INSTALL_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "${INSTALL_DIR}"
source "${INSTALL_DIR}/env.sh"

cmd_start() {
    echo "Starting Orqus Chain (Docker mode)..."
    docker compose up -d
    echo ""
    echo "Orqus Chain started!"
    echo "  JSON-RPC:  http://127.0.0.1:${RETH_HTTP_PORT}"
    echo "  WebSocket: ws://127.0.0.1:${RETH_WS_PORT}"
    echo ""
    echo "View logs: $(basename "$0") logs"
}

cmd_stop() {
    echo "Stopping Orqus Chain..."
    docker compose down
    echo "Stopped."
}

cmd_status() {
    docker compose ps
}

cmd_logs() {
    docker compose logs -f --tail 100
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
    echo "Stopping container..."
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
    rm -rf "${DATA_DIR}/reth"

    echo "Extracting snapshot to ${DATA_DIR}..."
    tar -xzf "${tmp_file}" -C "${DATA_DIR}"
    rm -f "${tmp_file}"

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

    echo "Stopping container..."
    docker compose down

    echo "Wiping chain data..."
    rm -rf "${DATA_DIR}/reth"

    echo ""
    echo "Reset complete. The node will re-initialize from genesis on next start."
    echo "  $(basename $0) start"
}

case "${1:-}" in
    start)    cmd_start ;;
    stop)     cmd_stop ;;
    restart)  cmd_stop; cmd_start ;;
    status)   cmd_status ;;
    logs)     cmd_logs ;;
    download) cmd_download ;;
    reset)    cmd_reset ;;
    *)
        echo "Usage: $(basename $0) <command>"
        echo ""
        echo "Commands:"
        echo "  start     Start orqus-reth container"
        echo "  stop      Stop container"
        echo "  restart   Restart container"
        echo "  status    Show container status"
        echo "  logs      Tail logs"
        echo "  download  Download latest snapshot and restore"
        echo "  reset     Wipe data and re-initialize from genesis"
        exit 1
        ;;
esac
SCRIPT
    chmod +x "${ctl_script}"
    log_ok "Docker orqusctl.sh generated"
}

# Generate binary mode orqusctl.sh
generate_orqusctl_script() {
    local ctl_script="${INSTALL_DIR}/orqusctl.sh"

    log_info "Generating orqusctl.sh..."
    cat > "${ctl_script}" << 'SCRIPT'
#!/bin/bash
#
# orqusctl.sh - Orqus Chain control script (Simplex)
# Usage: orqusctl.sh <command>
#
# Commands:
#   start     Start orqus-reth
#   stop      Stop orqus-reth
#   restart   Stop then start
#   status    Show running status
#   logs      Tail log file
#   download  Download latest snapshot and restore
#   reset     Wipe chain data and re-initialize from genesis
#

INSTALL_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${INSTALL_DIR}/env.sh"

cmd_start() {
    mkdir -p "${DATA_DIR}/logs"

    CONSENSUS_ARGS=""
    FOLLOW_ARG=""
    if [ "${NODE_TYPE}" = "validator" ]; then
        # Build validator consensus arguments
        CONSENSUS_ARGS="--consensus.signing-key ${CONFIG_DIR}/signing.key"
        CONSENSUS_ARGS="${CONSENSUS_ARGS} --consensus.fee-recipient ${FEE_RECIPIENT}"
        CONSENSUS_ARGS="${CONSENSUS_ARGS} --consensus.listen-address 0.0.0.0:${CONSENSUS_PORT}"
        CONSENSUS_ARGS="${CONSENSUS_ARGS} --consensus.metrics-address 0.0.0.0:${CONSENSUS_METRICS_PORT}"
        CONSENSUS_ARGS="${CONSENSUS_ARGS} --consensus.allow-private-ips"
        if [ -n "${BOOTSTRAP_PEERS}" ]; then
            CONSENSUS_ARGS="${CONSENSUS_ARGS} --consensus.bootstrap-peers ${BOOTSTRAP_PEERS}"
        fi
    else
        # RPC follower mode
        if [ -n "${FOLLOW_URL}" ]; then
            FOLLOW_ARG="--follow ${FOLLOW_URL}"
        else
            echo "WARN: NODE_TYPE=rpc but FOLLOW_URL is empty. Node will not actively follow a source."
        fi
    fi

    TRUSTED_PEERS_ARG=""
    if [ -n "${RETH_TRUSTED_PEERS}" ]; then
        TRUSTED_PEERS_ARG="--trusted-peers ${RETH_TRUSTED_PEERS}"
    fi

    echo "Starting orqus-reth..."
    RUST_LOG="${LOG_LEVEL}" "${BIN_DIR}/orqus-reth" node \
        --chain "${CONFIG_DIR}/genesis.json" \
        --datadir "${DATA_DIR}/reth" \
        --log.file.directory "${DATA_DIR}/logs" \
        --log.file.filter "${LOG_LEVEL}" \
        --http --http.addr 0.0.0.0 --http.port ${RETH_HTTP_PORT} \
        --http.api eth,net,web3,debug,trace \
        --ws --ws.addr 0.0.0.0 --ws.port ${RETH_WS_PORT} \
        --port ${RETH_P2P_PORT} \
        --p2p-secret-key "${CONFIG_DIR}/enode.key" \
        --metrics 0.0.0.0:${RETH_METRICS_PORT} \
        --rpc.max-connections ${RETH_RPC_MAX_CONNECTIONS} \
        --builder.gaslimit ${RETH_BUILDER_GAS_LIMIT} \
        --txpool.pending-max-count ${RETH_TXPOOL_MAX_PENDING} \
        --txpool.queued-max-count ${RETH_TXPOOL_MAX_QUEUED} \
        --txpool.max-account-slots ${RETH_TXPOOL_MAX_ACCOUNT_SLOTS} \
        --txpool.max-pending-txns ${RETH_TXPOOL_MAX_PENDING_TXNS} \
        --txpool.max-new-txns ${RETH_TXPOOL_MAX_NEW_TXNS} \
        ${CONSENSUS_ARGS} \
        ${TRUSTED_PEERS_ARG} \
        ${FOLLOW_ARG} \
        >> "${DATA_DIR}/logs/orqus-reth.log" 2>&1 &
    local pid=$!
    echo "  PID: ${pid}"

    printf "Waiting for RPC (port ${RETH_HTTP_PORT})"
    _elapsed=0
    while true; do
        if nc -z 127.0.0.1 "${RETH_HTTP_PORT}" 2>/dev/null; then
            printf " (${_elapsed}s)\n"
            break
        fi
        if ! kill -0 "${pid}" 2>/dev/null; then
            printf "\n"
            echo "ERROR: orqus-reth exited unexpectedly, check logs: ${DATA_DIR}/logs/orqus-reth.log"
            exit 1
        fi
        printf "."
        sleep 1
        _elapsed=$((_elapsed + 1))
        [ $((_elapsed % 30)) -eq 0 ] && printf "\n  (${_elapsed}s elapsed, still loading...)"
    done
    unset _elapsed

    echo ""
    echo "Orqus Chain started!"
    echo "  JSON-RPC:  http://127.0.0.1:${RETH_HTTP_PORT}"
    echo "  WebSocket: ws://127.0.0.1:${RETH_WS_PORT}"
}

cmd_stop() {
    echo "Stopping orqus-reth..."
    pkill -f "orqus-reth node" 2>/dev/null || true
    sleep 2
    echo "Stopped."
}

cmd_status() {
    echo "Orqus Chain Status:"
    if pgrep -f "orqus-reth node" > /dev/null 2>&1; then
        echo "  [UP]   orqus-reth (pid: $(pgrep -f 'orqus-reth node' | head -1))"
    else
        echo "  [DOWN] orqus-reth"
    fi
}

cmd_logs() {
    tail -n 100 -f "${DATA_DIR}/logs/orqus-reth.log"
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
    rm -rf "${DATA_DIR}/reth"

    echo "Extracting snapshot to ${DATA_DIR}..."
    tar -xzf "${tmp_file}" -C "${DATA_DIR}"
    rm -f "${tmp_file}"

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

    echo "Re-initializing reth..."
    mkdir -p "${DATA_DIR}/reth"
    "${BIN_DIR}/orqus-reth" init \
        --datadir "${DATA_DIR}/reth" \
        --chain "${CONFIG_DIR}/genesis.json" \
        2>/dev/null || true

    echo ""
    echo "Reset complete. Start the chain with:"
    echo "  $(basename $0) start"
}

case "${1:-}" in
    start)    cmd_start ;;
    stop)     cmd_stop ;;
    restart)  cmd_stop; cmd_start ;;
    status)   cmd_status ;;
    logs)     cmd_logs ;;
    download) cmd_download ;;
    reset)    cmd_reset ;;
    *)
        echo "Usage: $(basename $0) <command>"
        echo ""
        echo "Commands:"
        echo "  start     Start orqus-reth"
        echo "  stop      Stop orqus-reth"
        echo "  restart   Stop then start"
        echo "  status    Show process status"
        echo "  logs      Tail logs"
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
# Orqus Chain Environment (Simplex)
export INSTALL_DIR="${INSTALL_DIR}"
export DATA_DIR="${DATA_DIR}"
export BIN_DIR="${BIN_DIR}"
export CONFIG_DIR="${CONFIG_DIR}"
export CHAIN_ID="${CHAIN_ID}"
export NETWORK="${NETWORK}"
export NODE_TYPE="${NODE_TYPE}"
export MONIKER="${MONIKER}"

# Fee recipient
export FEE_RECIPIENT="${FEE_RECIPIENT}"

# Consensus peers
export BOOTSTRAP_PEERS="${BOOTSTRAP_PEERS}"

# Reth P2P peers
export RETH_TRUSTED_PEERS="${RETH_TRUSTED_PEERS}"
export FOLLOW_URL="${FOLLOW_URL}"

# Ports
export RETH_HTTP_PORT="${RETH_HTTP_PORT}"
export RETH_WS_PORT="${RETH_WS_PORT}"
export RETH_P2P_PORT="${RETH_P2P_PORT}"
export RETH_METRICS_PORT="${RETH_METRICS_PORT}"
export CONSENSUS_PORT="${CONSENSUS_PORT}"
export CONSENSUS_METRICS_PORT="${CONSENSUS_METRICS_PORT}"

# Snapshot
export SNAPSHOT_BASE_URL="${SNAPSHOT_BASE_URL}"
export SNAPSHOT_URL="${SNAPSHOT_URL}"

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

# Reconfigure existing installation
do_reconfigure() {
    echo ""
    echo "============================================================"
    echo "           Orqus Chain - Reconfigure                        "
    echo "============================================================"
    echo ""

    if [ ! -d "${INSTALL_DIR}" ]; then
        log_error "No existing installation found at ${INSTALL_DIR}"
        log_error "Run install first"
        exit 1
    fi

    # Load stored settings from env.sh, then re-apply any user-provided overrides
    if [ -f "${INSTALL_DIR}/env.sh" ]; then
        source "${INSTALL_DIR}/env.sh"
    fi

    [ -n "${_USER_NODE_TYPE}" ]          && NODE_TYPE="${_USER_NODE_TYPE}"
    [ -n "${_USER_MONIKER}" ]            && MONIKER="${_USER_MONIKER}"
    [ -n "${_USER_BOOTSTRAP_PEERS}" ]    && BOOTSTRAP_PEERS="${_USER_BOOTSTRAP_PEERS}"
    [ -n "${_USER_RETH_TRUSTED_PEERS}" ] && RETH_TRUSTED_PEERS="${_USER_RETH_TRUSTED_PEERS}"
    [ -n "${_USER_NETWORK}" ]            && NETWORK="${_USER_NETWORK}"
    [ -n "${_USER_SNAPSHOT_BASE_URL}" ]  && SNAPSHOT_BASE_URL="${_USER_SNAPSHOT_BASE_URL}"
    [ -n "${_USER_FEE_RECIPIENT}" ]      && FEE_RECIPIENT="${_USER_FEE_RECIPIENT}"

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
            ;;
        default|"")
            ;;
        *)
            log_error "Unknown PROFILE: ${_USER_PROFILE} (valid: benchmark, default)"
            exit 1
            ;;
    esac

    # Individual perf overrides (win over profile preset)
    [ -n "${_USER_RETH_RPC_MAX_CONNECTIONS}" ]      && RETH_RPC_MAX_CONNECTIONS="${_USER_RETH_RPC_MAX_CONNECTIONS}"
    [ -n "${_USER_RETH_BUILDER_GAS_LIMIT}" ]        && RETH_BUILDER_GAS_LIMIT="${_USER_RETH_BUILDER_GAS_LIMIT}"
    [ -n "${_USER_RETH_TXPOOL_MAX_PENDING}" ]       && RETH_TXPOOL_MAX_PENDING="${_USER_RETH_TXPOOL_MAX_PENDING}"
    [ -n "${_USER_RETH_TXPOOL_MAX_QUEUED}" ]        && RETH_TXPOOL_MAX_QUEUED="${_USER_RETH_TXPOOL_MAX_QUEUED}"
    [ -n "${_USER_RETH_TXPOOL_MAX_ACCOUNT_SLOTS}" ] && RETH_TXPOOL_MAX_ACCOUNT_SLOTS="${_USER_RETH_TXPOOL_MAX_ACCOUNT_SLOTS}"
    [ -n "${_USER_RETH_TXPOOL_MAX_PENDING_TXNS}" ]  && RETH_TXPOOL_MAX_PENDING_TXNS="${_USER_RETH_TXPOOL_MAX_PENDING_TXNS}"
    [ -n "${_USER_RETH_TXPOOL_MAX_NEW_TXNS}" ]      && RETH_TXPOOL_MAX_NEW_TXNS="${_USER_RETH_TXPOOL_MAX_NEW_TXNS}"
    [ -n "${_USER_LOG_LEVEL}" ]                     && LOG_LEVEL="${_USER_LOG_LEVEL}"
    [ -n "${_USER_FOLLOW_URL}" ]                    && FOLLOW_URL="${_USER_FOLLOW_URL}"

    # Auto-derive RETH_BUILDER_GAS_LIMIT from GENESIS_GAS_LIMIT
    if [ -n "${GENESIS_GAS_LIMIT}" ] && [ -z "${_USER_RETH_BUILDER_GAS_LIMIT}" ]; then
        RETH_BUILDER_GAS_LIMIT="${GENESIS_GAS_LIMIT}"
    fi

    log_info "Applying configuration:"
    log_info "  Node type:         ${NODE_TYPE}"
    log_info "  Moniker:           ${MONIKER}"
    log_info "  Fee recipient:     ${FEE_RECIPIENT}"
    log_info "  Bootstrap peers:   ${BOOTSTRAP_PEERS:-<none>}"
    log_info "  Reth peers:        ${RETH_TRUSTED_PEERS:-<none>}"
    log_info "  Follow URL:        ${FOLLOW_URL:-<none>}"
    log_info "  Network:           ${NETWORK}"
    if [ -n "${_USER_PROFILE}" ]; then
        log_info "  Profile:           ${_USER_PROFILE}"
        log_info "  Log level:         ${LOG_LEVEL}"
        log_info "  Builder gas:       ${RETH_BUILDER_GAS_LIMIT}"
        log_info "  RPC max conn:      ${RETH_RPC_MAX_CONNECTIONS}"
        log_info "  Txpool pending:    ${RETH_TXPOOL_MAX_PENDING_TXNS}"
    fi

    log_info "Stopping services..."
    "${INSTALL_DIR}/orqusctl.sh" stop 2>/dev/null || true
    sleep 2

    log_info "Regenerating configuration files..."
    generate_env_file

    if [ -f "${INSTALL_DIR}/docker-compose.yml" ]; then
        generate_docker_compose
        generate_docker_orqusctl_script
    else
        generate_orqusctl_script
    fi

    echo ""
    echo "============================================================"
    echo "               Reconfiguration Complete!                     "
    echo "============================================================"
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
    echo "============================================================"
    echo "              Orqus Chain - Upgrade                          "
    echo "============================================================"
    echo ""

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
    LATEST_VERSION=$(get_latest_version "${GITHUB_REPO}")

    if [ -z "${LATEST_VERSION}" ]; then
        log_error "Could not fetch latest version"
        exit 1
    fi

    log_info "Latest version: ${LATEST_VERSION}"
    RELEASE_URL="https://github.com/${GITHUB_REPO}/releases/download/${LATEST_VERSION}"
    DOCKER_TAG="${DOCKER_TAG:-${LATEST_VERSION}}"

    if [ "${INSTALL_MODE}" = "docker" ]; then
        # Docker Mode Upgrade
        log_info "Stopping container..."
        cd "${INSTALL_DIR}"
        docker compose down 2>/dev/null || true

        log_info "Pulling new Docker image..."
        pull_docker_image

        # Update docker-compose.yml with new image tag
        log_info "Updating docker-compose.yml..."
        sed -i.bak "s|${DOCKER_REGISTRY}/orqus-reth:[^[:space:]]*|${DOCKER_REGISTRY}/orqus-reth:${DOCKER_TAG}|g" "${INSTALL_DIR}/docker-compose.yml"
        rm -f "${INSTALL_DIR}/docker-compose.yml.bak"

        log_info "Starting container with new image..."
        docker compose up -d

    else
        # Binary Mode Upgrade
        binary_needs_update() {
            local name=$1
            local remote_url=$2
            local local_bin="${BIN_DIR}/${name}"

            [ -f "${local_bin}" ] || return 0

            local remote_sha256
            remote_sha256=$(curl -fsSL "${remote_url}.sha256" 2>/dev/null | awk '{print $1}')
            [ -z "${remote_sha256}" ] && return 0

            local local_sha256
            local_sha256=$(sha256sum "${local_bin}" | awk '{print $1}')

            [ "${local_sha256}" != "${remote_sha256}" ]
        }

        if [ "${OS}" != "linux" ] || [ "${ARCH}" != "amd64" ]; then
            log_error "Binary upgrade only available for linux-amd64"
            exit 1
        fi

        RETH_URL="${RELEASE_URL}/orqus-reth-linux-amd64"

        if binary_needs_update "orqus-reth" "${RETH_URL}"; then
            log_info "Stopping services..."
            "${INSTALL_DIR}/orqusctl.sh" stop 2>/dev/null || true
            sleep 2

            [ -f "${BIN_DIR}/orqus-reth" ] && mv "${BIN_DIR}/orqus-reth" "${BIN_DIR}/orqus-reth.bak"

            log_info "Updating orqus-reth..."
            download_binary "orqus-reth" "${RETH_URL}"

            rm -f "${BIN_DIR}/orqus-reth.bak"

            log_info "Upgrade complete. Start the chain with:"
            log_info "  ${INSTALL_DIR}/orqusctl.sh start"
        else
            log_ok "orqus-reth already up to date (${LATEST_VERSION}), nothing to do."
        fi
    fi

    # Update install script for future upgrades
    log_info "Updating install script..."
    SCRIPT_PATH="${BASH_SOURCE[0]}"
    if [ -f "${SCRIPT_PATH}" ]; then
        cp "${SCRIPT_PATH}" "${INSTALL_DIR}/install.sh"
        chmod +x "${INSTALL_DIR}/install.sh"
    else
        curl -sL -o "${INSTALL_DIR}/install.sh" \
            "https://raw.githubusercontent.com/${GITHUB_REPO}/main/install.sh"
        chmod +x "${INSTALL_DIR}/install.sh"
    fi

    echo ""
    echo "============================================================"
    echo "                   Upgrade Complete!                         "
    echo "============================================================"
    echo ""
    echo "Upgraded to version: ${LATEST_VERSION}"
    echo ""
    if [ "${INSTALL_MODE}" = "docker" ]; then
        echo "Container is now running with the new image."
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
    echo "============================================================"
    echo "        Orqus Chain - One-click Installer (Simplex)         "
    echo "============================================================"
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

    # Apply benchmark profile if requested
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
            # Individual overrides still win
            [ -n "${_USER_RETH_RPC_MAX_CONNECTIONS}" ]      && RETH_RPC_MAX_CONNECTIONS="${_USER_RETH_RPC_MAX_CONNECTIONS}"
            [ -n "${_USER_RETH_BUILDER_GAS_LIMIT}" ]        && RETH_BUILDER_GAS_LIMIT="${_USER_RETH_BUILDER_GAS_LIMIT}"
            [ -n "${_USER_RETH_TXPOOL_MAX_PENDING}" ]       && RETH_TXPOOL_MAX_PENDING="${_USER_RETH_TXPOOL_MAX_PENDING}"
            [ -n "${_USER_RETH_TXPOOL_MAX_QUEUED}" ]        && RETH_TXPOOL_MAX_QUEUED="${_USER_RETH_TXPOOL_MAX_QUEUED}"
            [ -n "${_USER_RETH_TXPOOL_MAX_ACCOUNT_SLOTS}" ] && RETH_TXPOOL_MAX_ACCOUNT_SLOTS="${_USER_RETH_TXPOOL_MAX_ACCOUNT_SLOTS}"
            [ -n "${_USER_RETH_TXPOOL_MAX_PENDING_TXNS}" ]  && RETH_TXPOOL_MAX_PENDING_TXNS="${_USER_RETH_TXPOOL_MAX_PENDING_TXNS}"
            [ -n "${_USER_RETH_TXPOOL_MAX_NEW_TXNS}" ]      && RETH_TXPOOL_MAX_NEW_TXNS="${_USER_RETH_TXPOOL_MAX_NEW_TXNS}"
            [ -n "${_USER_LOG_LEVEL}" ]                     && LOG_LEVEL="${_USER_LOG_LEVEL}"
            ;;
        default|"") ;;
        *)
            log_error "Unknown PROFILE: ${_USER_PROFILE} (valid: benchmark, default)"
            exit 1
            ;;
    esac

    # Auto-derive RETH_BUILDER_GAS_LIMIT from GENESIS_GAS_LIMIT
    if [ -n "${GENESIS_GAS_LIMIT}" ] && [ -z "${_USER_RETH_BUILDER_GAS_LIMIT}" ]; then
        RETH_BUILDER_GAS_LIMIT="${GENESIS_GAS_LIMIT}"
    fi

    log_info "Installation mode: ${INSTALL_MODE}"
    log_info "Node type: ${NODE_TYPE}"
    if [ "${NODE_TYPE}" = "rpc" ] && [ -z "${FOLLOW_URL}" ]; then
        log_warn "NODE_TYPE=rpc but FOLLOW_URL is empty (recommended to set FOLLOW_URL=ws://<source>:8546)"
    fi
    log_info "Network: ${NETWORK}"
    log_info "Chain ID: ${CHAIN_ID}"

    detect_platform

    # Check Docker for docker mode
    if [ "${INSTALL_MODE}" = "docker" ]; then
        if ! command -v docker &> /dev/null; then
            install_docker
        fi
        if ! docker compose version &> /dev/null && ! docker-compose version &> /dev/null; then
            log_error "Docker Compose is not installed."
            log_error "Please install Docker manually: https://docs.docker.com/engine/install/"
            exit 1
        fi
    fi

    # Check python3 is available (needed for key generation)
    if ! command -v python3 &>/dev/null; then
        log_error "python3 is required but not found."
        log_error "Please install python3 and try again."
        exit 1
    fi

    # Create directories
    log_info "Creating directories..."
    mkdir -p "${BIN_DIR}" "${CONFIG_DIR}" "${DATA_DIR}/logs" "${DATA_DIR}/reth"

    # Fetch latest release info
    log_info "Fetching latest release..."
    LATEST_VERSION=$(get_latest_version "${GITHUB_REPO}")

    if [ -z "${LATEST_VERSION}" ]; then
        log_warn "Could not fetch latest version, using 'latest' tag"
        LATEST_VERSION="latest"
    else
        log_info "Latest version: ${LATEST_VERSION}"
    fi

    RELEASE_URL="https://github.com/${GITHUB_REPO}/releases/download/${LATEST_VERSION}"
    DOCKER_TAG="${DOCKER_TAG:-${LATEST_VERSION}}"

    # Auto-fetch peers if not explicitly set
    fetch_peers

    # Generate keys (shared between binary and docker modes)
    generate_signing_key
    generate_enode_key

    # Derive and display node info
    derive_signing_pubkey
    derive_eth_address
    log_info "Node signing pubkey: ${SIGNING_PUBKEY}"
    log_info "Derived ETH address: ${ETH_ADDRESS}"

    # Set fee recipient to derived address if still default zero address
    if [ "${FEE_RECIPIENT}" = "0x0000000000000000000000000000000000000000" ] && [ "${ETH_ADDRESS}" != "0x0000000000000000000000000000000000000000" ]; then
        log_info "Setting fee recipient to derived address: ${ETH_ADDRESS}"
        FEE_RECIPIENT="${ETH_ADDRESS}"
    fi

    if [ "${INSTALL_MODE}" = "binary" ]; then
        # ==================== Binary Mode ====================
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

        # Download genesis and initialize
        download_genesis

        if [ "${SNAPSHOT_RESTORED:-false}" != "true" ]; then
            init_reth
        fi

        # Generate scripts and env
        generate_env_file
        generate_orqusctl_script

    else
        # ==================== Docker Mode ====================
        pull_docker_image

        # Download genesis
        download_genesis

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
        curl -sL -o "${INSTALL_DIR}/install.sh" \
            "https://raw.githubusercontent.com/${GITHUB_REPO}/main/install.sh"
        chmod +x "${INSTALL_DIR}/install.sh"
    fi

    echo ""
    echo "============================================================"
    echo "                  Installation Complete!                     "
    echo "============================================================"
    echo ""
    echo "Installation mode: ${INSTALL_MODE}"
    echo "Node type:         ${NODE_TYPE}"
    echo "Install dir:       ${INSTALL_DIR}"
    echo "Chain ID:          ${CHAIN_ID}"
    echo "Fee recipient:     ${FEE_RECIPIENT}"
    echo "Signing pubkey:    ${SIGNING_PUBKEY}"
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
    echo "RPC endpoint: http://127.0.0.1:${RETH_HTTP_PORT}"
    echo "Consensus port: ${CONSENSUS_PORT}"
    echo ""
    if [ -n "${BOOTSTRAP_PEERS}" ]; then
        echo "Bootstrap peers: ${BOOTSTRAP_PEERS}"
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
        echo "  upgrade       Upgrade binary to latest version"
        echo "  reconfigure   Regenerate configs from environment variables"
        echo "                Example: FEE_RECIPIENT=0x... ~/.orqus/install.sh reconfigure"
        echo "                Example: PROFILE=benchmark ~/.orqus/install.sh reconfigure"
        exit 1
        ;;
esac
