#!/usr/bin/env bash
# ==============================================================================
# Script: install.sh
# Description: Installs and registers the Forgejo Model Context Protocol (MCP) server
#              for Antigravity (agy) / Gemini CLI and OpenCode.
#              Uses `jq` to parse existing configurations and safely merge
#              the new MCP entry without overwriting existing servers.
#
# Upstream: https://git.b4mad.industries/agentic-forges/forgejo-mcp
# Mirrors:  https://codeberg.org/goern/forgejo-mcp
#           https://github.com/goern/forgejo-mcp
# ==============================================================================

set -euo pipefail

# Configuration defaults
DEFAULT_AGY_CONFIG="${HOME}/.gemini/config/mcp_config.json"
DEFAULT_OPENCODE_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/opencode.json"
DEFAULT_BIN_DIR="${HOME}/.local/bin"
DEFAULT_FORGEJO_VERSION="3.3.0"

AGY_CONFIG_FILE="${AGY_CONFIG_FILE:-${MCP_CONFIG_FILE:-$DEFAULT_AGY_CONFIG}}"
OPENCODE_CONFIG_FILE="${OPENCODE_CONFIG_FILE:-$DEFAULT_OPENCODE_CONFIG}"
BIN_DIR="${BIN_DIR:-$DEFAULT_BIN_DIR}"
FORGEJO_VERSION="${FORGEJO_VERSION:-$DEFAULT_FORGEJO_VERSION}"

TARGET="all" # all | agy | opencode
SERVER_NAME="forgejo"
FORGEJO_URL="${FORGEJO_URL:-https://git.home.0101.party}"
FORGEJO_ACCESS_TOKEN="${FORGEJO_ACCESS_TOKEN:-}"
TRANSPORT="stdio" # stdio | http | sse
HTTP_PORT="8080"
SSE_PORT="8080"
USER_AGENT="forgejo-mcp/${FORGEJO_VERSION}"
BIN_PATH=""
ALLOW_DOWNLOAD="true"

# Script modes
DRY_RUN="false"
REMOVE_MODE="false"
LIST_MODE="false"
VERIFY_MODE="false"

# Terminal styling
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

print_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

print_warn() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

print_step() {
    echo -e "\n${BOLD}${CYAN}==>${NC} ${BOLD}$*${NC}"
}

usage() {
    cat << 'EOF'
Usage: ./install.sh [OPTIONS]

Installs and registers the Forgejo MCP server into Antigravity (agy),
Gemini CLI, and OpenCode configurations using jq.

Target Selection:
  -t, --target <all|agy|opencode> Target client(s) to configure (default: all)
      --agy-only                 Configure only Antigravity (agy) / Gemini CLI
      --opencode-only            Configure only OpenCode

Configuration Paths:
  -c, --config <path>          Path to configuration file (overrides primary target config)
      --agy-config <path>      Path to agy mcp_config.json
                               (default: ~/.gemini/config/mcp_config.json)
      --opencode-config <path> Path to opencode.json
                               (default: ~/.config/opencode/opencode.json)

Forgejo Server Options:
  -u, --url <url>              Forgejo instance base URL (default: https://git.home.0101.party)
  -k, --token <token>          Forgejo personal access token (or set FORGEJO_ACCESS_TOKEN)
  -n, --name <name>            Server identifier in client configs (default: forgejo)
      --transport <mode>       Transport mode: stdio | http | sse (default: stdio)
      --http-port <port>       Port for HTTP transport mode (default: 8080)
      --sse-port <port>        Port for SSE transport mode (default: 8080)
      --user-agent <str>       Custom User-Agent header (default: forgejo-mcp/<version>)
      --bin-path <path>        Path to existing forgejo-mcp binary
      --bin-dir <dir>          Target directory for binary download (default: ~/.local/bin)
      --version <ver>          Binary release version to download (default: 3.3.0)
      --no-download            Disable automatic binary download if binary is missing

Script Modes:
      --dry-run                Print the generated JSON configuration without writing to file
      --remove, --uninstall    Remove the server entry from target configuration(s)
      --verify                 Check dependencies, binary execution, and Forgejo API connection
  -l, --list                   List configured MCP servers in target configuration(s)
  -h, --help                   Display this help message and exit

Examples:
  # Install for both Antigravity (agy) and OpenCode with default URL and token
  ./install.sh --token "<your-token>"

  # Specify a custom Forgejo instance URL and token
  ./install.sh --url "https://forgejo.example.org" --token "<token>"

  # Configure OpenCode only
  ./install.sh --target opencode --token "<token>"

  # Configure Antigravity only
  ./install.sh --target agy --token "<token>"

  # Preview JSON changes without modifying any files
  ./install.sh --dry-run --token "<token>"

  # Verify environment, binary, and Forgejo API connectivity
  ./install.sh --verify --token "<token>"

  # Remove Forgejo server from all client configurations
  ./install.sh --remove
EOF
}

check_dependencies() {
    print_step "Verifying prerequisite system utilities..."
    local missing=0

    if command -v jq &>/dev/null; then
        print_success "jq: $(jq --version) found at $(command -v jq)"
    else
        print_error "'jq' command is required but not installed."
        echo "  Please install jq via your package manager:"
        echo "    - Debian/Ubuntu: sudo apt-get install jq"
        echo "    - Arch Linux:    sudo pacman -S jq"
        echo "    - Fedora:        sudo dnf install jq"
        missing=1
    fi

    if command -v curl &>/dev/null; then
        print_success "curl found at $(command -v curl)"
    else
        print_error "'curl' command is required but not installed."
        missing=1
    fi

    if command -v tar &>/dev/null; then
        print_success "tar found at $(command -v tar)"
    else
        print_error "'tar' command is required but not installed."
        missing=1
    fi

    if [ "$missing" -ne 0 ]; then
        print_error "Missing required dependencies. Please install them and try again."
        exit 1
    fi
}

detect_binary() {
    if [ -n "$BIN_PATH" ] && [ -x "$BIN_PATH" ]; then
        print_success "Using explicitly specified binary: $BIN_PATH"
        return 0
    fi

    if command -v forgejo-mcp &>/dev/null; then
        BIN_PATH="$(command -v forgejo-mcp)"
        print_success "Found forgejo-mcp in PATH: $BIN_PATH"
        return 0
    fi

    if [ -x "${BIN_DIR}/forgejo-mcp" ]; then
        BIN_PATH="${BIN_DIR}/forgejo-mcp"
        print_success "Found forgejo-mcp at: $BIN_PATH"
        return 0
    fi

    return 1
}

download_binary() {
    print_step "Downloading pre-compiled forgejo-mcp binary (v${FORGEJO_VERSION})..."

    local os arch arch_tag
    os="$(uname -s | tr '[:upper:]' '[:lower:]')"
    arch="$(uname -m)"

    case "$arch" in
        x86_64)
            arch_tag="amd64"
            ;;
        aarch64|arm64)
            arch_tag="arm64"
            ;;
        *)
            print_error "Unsupported architecture: $arch. Please compile forgejo-mcp from source using 'go install'."
            exit 1
            ;;
    esac

    local asset_name="forgejo-mcp_${FORGEJO_VERSION}_${os}_${arch_tag}.tar.gz"
    local download_url="https://git.b4mad.industries/agentic-forges/forgejo-mcp/releases/download/v${FORGEJO_VERSION}/${asset_name}"
    local fallback_url="https://codeberg.org/goern/forgejo-mcp/releases/download/v2.30.2/forgejo-mcp_2.30.2_${os}_${arch_tag}.tar.gz"

    mkdir -p "$BIN_DIR"
    local temp_dir
    temp_dir=$(mktemp -d "/tmp/forgejo-mcp.XXXXXX")

    print_info "Fetching from: $download_url"
    local http_status
    if curl -sSL -f -o "${temp_dir}/${asset_name}" "$download_url"; then
        print_success "Downloaded release asset successfully."
    else
        print_warn "Primary release download failed, attempting fallback release: $fallback_url"
        if curl -sSL -f -o "${temp_dir}/fallback.tar.gz" "$fallback_url"; then
            asset_name="fallback.tar.gz"
            print_success "Downloaded fallback release asset successfully."
        else
            rm -rf "$temp_dir"
            print_error "Failed to download forgejo-mcp binary."
            exit 1
        fi
    fi

    print_info "Extracting archive..."
    tar -xzf "${temp_dir}/${asset_name}" -C "$temp_dir"

    local extracted_bin
    extracted_bin=$(find "$temp_dir" -type f -name "forgejo-mcp" -perm /111 -o -type f -name "forgejo-mcp" | head -n 1)

    if [ -z "$extracted_bin" ] || [ ! -f "$extracted_bin" ]; then
        rm -rf "$temp_dir"
        print_error "Extracted archive did not contain 'forgejo-mcp' executable."
        exit 1
    fi

    cp "$extracted_bin" "${BIN_DIR}/forgejo-mcp"
    chmod +x "${BIN_DIR}/forgejo-mcp"
    rm -rf "$temp_dir"
    BIN_PATH="${BIN_DIR}/forgejo-mcp"
    print_success "Installed binary to: $BIN_PATH"
}

ensure_binary() {
    if detect_binary; then
        return 0
    fi

    if [ "$ALLOW_DOWNLOAD" = "true" ]; then
        download_binary
    else
        print_error "forgejo-mcp binary not found and automatic download is disabled (--no-download)."
        echo "  Install it via Go: go install git.b4mad.industries/agentic-forges/forgejo-mcp/v3@latest"
        echo "  Or provide an existing binary path: --bin-path /path/to/forgejo-mcp"
        exit 1
    fi
}

resolve_token() {
    if [ -n "$FORGEJO_ACCESS_TOKEN" ]; then
        return 0
    fi

    # Check if target configs already have an existing token configured
    if [ -f "$AGY_CONFIG_FILE" ] && jq empty "$AGY_CONFIG_FILE" 2>/dev/null; then
        local agy_tok
        agy_tok=$(jq -r --arg name "$SERVER_NAME" '.mcpServers[$name].env.FORGEJO_ACCESS_TOKEN // empty' "$AGY_CONFIG_FILE")
        if [ -n "$agy_tok" ]; then
            FORGEJO_ACCESS_TOKEN="$agy_tok"
            print_info "Reusing existing token from Antigravity configuration."
            return 0
        fi
    fi

    if [ -f "$OPENCODE_CONFIG_FILE" ] && jq empty "$OPENCODE_CONFIG_FILE" 2>/dev/null; then
        local opencode_tok
        opencode_tok=$(jq -r --arg name "$SERVER_NAME" '.mcp.servers[$name].environment.FORGEJO_ACCESS_TOKEN // empty' "$OPENCODE_CONFIG_FILE")
        if [ -n "$opencode_tok" ]; then
            FORGEJO_ACCESS_TOKEN="$opencode_tok"
            print_info "Reusing existing token from OpenCode configuration."
            return 0
        fi
    fi

    print_error "Forgejo access token is required."
    echo "  Please provide it via: --token <token>"
    echo "  Or set the environment variable: export FORGEJO_ACCESS_TOKEN=\"<token>\""
    exit 1
}

list_agy_servers() {
    print_step "Antigravity (agy) MCP servers in: $AGY_CONFIG_FILE"
    if [ ! -f "$AGY_CONFIG_FILE" ]; then
        print_warn "Configuration file does not exist yet: $AGY_CONFIG_FILE"
        return 0
    fi

    if ! jq empty "$AGY_CONFIG_FILE" 2>/dev/null; then
        print_error "Configuration file is not valid JSON: $AGY_CONFIG_FILE"
        return 1
    fi

    local server_count
    server_count=$(jq '.mcpServers // {} | length' "$AGY_CONFIG_FILE")
    print_info "Total servers configured: $server_count"

    if [ "$server_count" -gt 0 ]; then
        jq -r '.mcpServers // {} | to_entries[] | "  - \(.key): [command: \(.value.command // "N/A"), url: \(.value.serverUrl // "N/A")]"' "$AGY_CONFIG_FILE"
    fi
}

list_opencode_servers() {
    print_step "OpenCode MCP servers in: $OPENCODE_CONFIG_FILE"
    if [ ! -f "$OPENCODE_CONFIG_FILE" ]; then
        print_warn "Configuration file does not exist yet: $OPENCODE_CONFIG_FILE"
        return 0
    fi

    if ! jq empty "$OPENCODE_CONFIG_FILE" 2>/dev/null; then
        print_error "Configuration file is not valid JSON: $OPENCODE_CONFIG_FILE"
        return 1
    fi

    local server_count
    server_count=$(jq '.mcp.servers // {} | length' "$OPENCODE_CONFIG_FILE")
    print_info "Total servers configured: $server_count"

    if [ "$server_count" -gt 0 ]; then
        jq -r '.mcp.servers // {} | to_entries[] | "  - \(.key): [type: \(.value.type // "local"), command: \((.value.command // []) | join(" "))]"' "$OPENCODE_CONFIG_FILE"
    fi
}

remove_agy_server() {
    print_step "Removing '$SERVER_NAME' from Antigravity (agy): $AGY_CONFIG_FILE"
    if [ ! -f "$AGY_CONFIG_FILE" ]; then
        print_warn "Configuration file does not exist: $AGY_CONFIG_FILE. Nothing to remove."
        return 0
    fi

    if ! jq empty "$AGY_CONFIG_FILE" 2>/dev/null; then
        print_error "Configuration file is not valid JSON: $AGY_CONFIG_FILE"
        return 1
    fi

    local exists
    exists=$(jq --arg name "$SERVER_NAME" '.mcpServers // {} | has($name)' "$AGY_CONFIG_FILE")
    if [ "$exists" != "true" ]; then
        print_warn "Server '$SERVER_NAME' is not present in $AGY_CONFIG_FILE."
        return 0
    fi

    if [ "$DRY_RUN" = "true" ]; then
        print_info "Dry run enabled. Updated agy JSON without '$SERVER_NAME':"
        jq --arg name "$SERVER_NAME" 'del(.mcpServers[$name])' "$AGY_CONFIG_FILE"
        return 0
    fi

    local backup_file="${AGY_CONFIG_FILE}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$AGY_CONFIG_FILE" "$backup_file"
    print_info "Created backup: $backup_file"

    local temp_file
    temp_file=$(mktemp "${AGY_CONFIG_FILE}.tmp.XXXXXX")
    jq --arg name "$SERVER_NAME" 'del(.mcpServers[$name])' "$AGY_CONFIG_FILE" > "$temp_file"
    mv "$temp_file" "$AGY_CONFIG_FILE"

    print_success "Removed server '$SERVER_NAME' from $AGY_CONFIG_FILE."
}

remove_opencode_server() {
    print_step "Removing '$SERVER_NAME' from OpenCode: $OPENCODE_CONFIG_FILE"
    if [ ! -f "$OPENCODE_CONFIG_FILE" ]; then
        print_warn "Configuration file does not exist: $OPENCODE_CONFIG_FILE. Nothing to remove."
        return 0
    fi

    if ! jq empty "$OPENCODE_CONFIG_FILE" 2>/dev/null; then
        print_error "Configuration file is not valid JSON: $OPENCODE_CONFIG_FILE"
        return 1
    fi

    local exists
    exists=$(jq --arg name "$SERVER_NAME" '.mcp.servers // {} | has($name)' "$OPENCODE_CONFIG_FILE")
    if [ "$exists" != "true" ]; then
        print_warn "Server '$SERVER_NAME' is not present in $OPENCODE_CONFIG_FILE."
        return 0
    fi

    if [ "$DRY_RUN" = "true" ]; then
        print_info "Dry run enabled. Updated OpenCode JSON without '$SERVER_NAME':"
        jq --arg name "$SERVER_NAME" 'del(.mcp.servers[$name])' "$OPENCODE_CONFIG_FILE"
        return 0
    fi

    local backup_file="${OPENCODE_CONFIG_FILE}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$OPENCODE_CONFIG_FILE" "$backup_file"
    print_info "Created backup: $backup_file"

    local temp_file
    temp_file=$(mktemp "${OPENCODE_CONFIG_FILE}.tmp.XXXXXX")
    jq --arg name "$SERVER_NAME" 'del(.mcp.servers[$name])' "$OPENCODE_CONFIG_FILE" > "$temp_file"
    mv "$temp_file" "$OPENCODE_CONFIG_FILE"

    print_success "Removed server '$SERVER_NAME' from $OPENCODE_CONFIG_FILE."
}

verify_environment() {
    check_dependencies
    ensure_binary

    print_step "Verifying forgejo-mcp binary execution..."
    local ver_out
    ver_out=$("$BIN_PATH" --help 2>&1 | head -n 1 || true)
    print_success "Binary executable confirmed: $BIN_PATH"

    if [ -n "$FORGEJO_URL" ]; then
        print_step "Testing Forgejo instance reachability at: $FORGEJO_URL..."
        local version_endpoint="${FORGEJO_URL%/}/api/v1/version"
        local http_code
        http_code=$(curl -s -o /dev/null -w "%{http_code}" "$version_endpoint" || echo "failed")
        if [ "$http_code" = "200" ]; then
            local instance_ver
            instance_ver=$(curl -s "$version_endpoint" | jq -r '.version // "unknown"')
            print_success "Instance reachable! Forgejo version: $instance_ver"
        else
            print_warn "Instance returned HTTP status: $http_code for $version_endpoint"
        fi

        if [ -n "$FORGEJO_ACCESS_TOKEN" ]; then
            print_step "Verifying authentication token..."
            local token_code
            token_code=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: token $FORGEJO_ACCESS_TOKEN" "${FORGEJO_URL%/}/api/v1/repos/search?limit=1" || echo "failed")
            if [ "$token_code" = "200" ]; then
                print_success "Authentication successful (repository access confirmed)."
            else
                print_warn "Token verification returned HTTP code: $token_code"
            fi
        fi
    fi
}

# Parse command line options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -t|--target)
            TARGET="$2"
            shift 2
            ;;
        --agy-only)
            TARGET="agy"
            shift
            ;;
        --opencode-only)
            TARGET="opencode"
            shift
            ;;
        -c|--config)
            AGY_CONFIG_FILE="$2"
            OPENCODE_CONFIG_FILE="$2"
            shift 2
            ;;
        --agy-config)
            AGY_CONFIG_FILE="$2"
            shift 2
            ;;
        --opencode-config)
            OPENCODE_CONFIG_FILE="$2"
            shift 2
            ;;
        -u|--url)
            FORGEJO_URL="$2"
            shift 2
            ;;
        -k|--token)
            FORGEJO_ACCESS_TOKEN="$2"
            shift 2
            ;;
        -n|--name)
            SERVER_NAME="$2"
            shift 2
            ;;
        --transport)
            TRANSPORT="$2"
            shift 2
            ;;
        --http-port)
            HTTP_PORT="$2"
            shift 2
            ;;
        --sse-port)
            SSE_PORT="$2"
            shift 2
            ;;
        --user-agent)
            USER_AGENT="$2"
            shift 2
            ;;
        --bin-path)
            BIN_PATH="$2"
            shift 2
            ;;
        --bin-dir)
            BIN_DIR="$2"
            shift 2
            ;;
        --version)
            FORGEJO_VERSION="$2"
            USER_AGENT="forgejo-mcp/${FORGEJO_VERSION}"
            shift 2
            ;;
        --no-download)
            ALLOW_DOWNLOAD="false"
            shift
            ;;
        --dry-run)
            DRY_RUN="true"
            shift
            ;;
        --remove|--uninstall)
            REMOVE_MODE="true"
            shift
            ;;
        -l|--list)
            LIST_MODE="true"
            shift
            ;;
        --verify)
            VERIFY_MODE="true"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            print_error "Unknown argument: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate target selection
case "$TARGET" in
    all|agy|opencode)
        ;;
    *)
        print_error "Invalid target '$TARGET'. Must be one of: all, agy, opencode."
        exit 1
        ;;
esac

# Execute single-purpose actions if selected
if [ "$LIST_MODE" = "true" ]; then
    if [ "$TARGET" = "all" ] || [ "$TARGET" = "agy" ]; then
        list_agy_servers
    fi
    if [ "$TARGET" = "all" ] || [ "$TARGET" = "opencode" ]; then
        list_opencode_servers
    fi
    exit 0
fi

if [ "$VERIFY_MODE" = "true" ]; then
    verify_environment
    exit 0
fi

if [ "$REMOVE_MODE" = "true" ]; then
    if [ "$TARGET" = "all" ] || [ "$TARGET" = "agy" ]; then
        remove_agy_server
    fi
    if [ "$TARGET" = "all" ] || [ "$TARGET" = "opencode" ]; then
        remove_opencode_server
    fi
    exit 0
fi

# Main installation flow
check_dependencies
ensure_binary
resolve_token

print_step "Preparing Forgejo MCP configuration..."
print_info "Target(s)         : $TARGET"
print_info "Server identifier : $SERVER_NAME"
print_info "Forgejo URL       : $FORGEJO_URL"
print_info "Transport         : $TRANSPORT"
print_info "Binary executable : $BIN_PATH"
if [ "$TARGET" = "all" ] || [ "$TARGET" = "agy" ]; then
    print_info "Antigravity config: $AGY_CONFIG_FILE"
fi
if [ "$TARGET" = "all" ] || [ "$TARGET" = "opencode" ]; then
    print_info "OpenCode config   : $OPENCODE_CONFIG_FILE"
fi

# Build arguments array
ARGS=("--transport" "$TRANSPORT" "--url" "$FORGEJO_URL")

if [ "$TRANSPORT" = "http" ]; then
    ARGS+=("--http-port" "$HTTP_PORT")
elif [ "$TRANSPORT" = "sse" ]; then
    ARGS+=("--sse-port" "$SSE_PORT")
fi

# For OpenCode, full command array includes the binary as the first element
OPENCODE_CMD=("$BIN_PATH" "${ARGS[@]}")

# Convert bash arrays to JSON arrays using jq
AGY_ARGS_JSON=$(printf '%s\n' "${ARGS[@]}" | jq -R . | jq -s .)
OPENCODE_CMD_JSON=$(printf '%s\n' "${OPENCODE_CMD[@]}" | jq -R . | jq -s .)

# Prepare env JSON object
ENV_JSON=$(jq -n \
    --arg token "$FORGEJO_ACCESS_TOKEN" \
    --arg url "$FORGEJO_URL" \
    --arg ua "$USER_AGENT" \
    '{
        "FORGEJO_ACCESS_TOKEN": $token,
        "FORGEJO_URL": $url,
        "FORGEJO_USER_AGENT": $ua
    }')

# ------------------------------------------------------------------------------
# 1. Install to Antigravity (agy)
# ------------------------------------------------------------------------------
if [ "$TARGET" = "all" ] || [ "$TARGET" = "agy" ]; then
    print_step "Registering server in Antigravity (agy)..."

    if [ -f "$AGY_CONFIG_FILE" ]; then
        if ! jq empty "$AGY_CONFIG_FILE" 2>/dev/null; then
            print_error "Existing configuration file '$AGY_CONFIG_FILE' is not valid JSON."
            exit 1
        fi
        CURRENT_AGY_JSON=$(cat "$AGY_CONFIG_FILE")
    else
        print_info "No existing configuration file found at $AGY_CONFIG_FILE. Initializing new structure."
        CURRENT_AGY_JSON='{"mcpServers": {}}'
    fi

    UPDATED_AGY_JSON=$(echo "$CURRENT_AGY_JSON" | jq \
        --arg name "$SERVER_NAME" \
        --arg cmd "$BIN_PATH" \
        --argjson args "$AGY_ARGS_JSON" \
        --argjson env "$ENV_JSON" \
        '
        .mcpServers = (.mcpServers // {}) |
        .mcpServers[$name] = {
            "command": $cmd,
            "args": $args,
            "env": $env
        }
        ')

    if ! echo "$UPDATED_AGY_JSON" | jq empty 2>/dev/null; then
        print_error "Failed to generate valid JSON configuration for Antigravity."
        exit 1
    fi

    if [ "$DRY_RUN" = "true" ]; then
        print_info "Dry Run - Antigravity (agy) JSON output:"
        echo "$UPDATED_AGY_JSON" | jq .
    else
        CONFIG_DIR=$(dirname "$AGY_CONFIG_FILE")
        mkdir -p "$CONFIG_DIR"

        if [ -f "$AGY_CONFIG_FILE" ]; then
            BACKUP_FILE="${AGY_CONFIG_FILE}.bak.$(date +%Y%m%d%H%M%S)"
            cp "$AGY_CONFIG_FILE" "$BACKUP_FILE"
            print_info "Created backup: $BACKUP_FILE"
        fi

        TEMP_FILE=$(mktemp "${CONFIG_DIR}/mcp_config.tmp.XXXXXX")
        echo "$UPDATED_AGY_JSON" | jq . > "$TEMP_FILE"
        mv "$TEMP_FILE" "$AGY_CONFIG_FILE"
        print_success "Registered in Antigravity: $AGY_CONFIG_FILE"
    fi
fi

# ------------------------------------------------------------------------------
# 2. Install to OpenCode
# ------------------------------------------------------------------------------
if [ "$TARGET" = "all" ] || [ "$TARGET" = "opencode" ]; then
    print_step "Registering server in OpenCode..."

    if [ -f "$OPENCODE_CONFIG_FILE" ]; then
        if ! jq empty "$OPENCODE_CONFIG_FILE" 2>/dev/null; then
            print_error "Existing configuration file '$OPENCODE_CONFIG_FILE' is not valid JSON."
            exit 1
        fi
        CURRENT_OPENCODE_JSON=$(cat "$OPENCODE_CONFIG_FILE")
    else
        print_info "No existing configuration file found at $OPENCODE_CONFIG_FILE. Initializing new structure."
        CURRENT_OPENCODE_JSON='{"mcp": {"servers": {}}}'
    fi

    UPDATED_OPENCODE_JSON=$(echo "$CURRENT_OPENCODE_JSON" | jq \
        --arg name "$SERVER_NAME" \
        --argjson cmd "$OPENCODE_CMD_JSON" \
        --argjson env "$ENV_JSON" \
        '
        .mcp = (.mcp // {}) |
        .mcp.servers = (.mcp.servers // {}) |
        .mcp.servers[$name] = {
            "type": "local",
            "command": $cmd,
            "environment": $env
        }
        ')

    if ! echo "$UPDATED_OPENCODE_JSON" | jq empty 2>/dev/null; then
        print_error "Failed to generate valid JSON configuration for OpenCode."
        exit 1
    fi

    if [ "$DRY_RUN" = "true" ]; then
        print_info "Dry Run - OpenCode JSON output:"
        echo "$UPDATED_OPENCODE_JSON" | jq .
    else
        CONFIG_DIR=$(dirname "$OPENCODE_CONFIG_FILE")
        mkdir -p "$CONFIG_DIR"

        if [ -f "$OPENCODE_CONFIG_FILE" ]; then
            BACKUP_FILE="${OPENCODE_CONFIG_FILE}.bak.$(date +%Y%m%d%H%M%S)"
            cp "$OPENCODE_CONFIG_FILE" "$BACKUP_FILE"
            print_info "Created backup: $BACKUP_FILE"
        fi

        TEMP_FILE=$(mktemp "${CONFIG_DIR}/opencode.tmp.XXXXXX")
        echo "$UPDATED_OPENCODE_JSON" | jq . > "$TEMP_FILE"
        mv "$TEMP_FILE" "$OPENCODE_CONFIG_FILE"
        print_success "Registered in OpenCode: $OPENCODE_CONFIG_FILE"
    fi
fi

if [ "$DRY_RUN" = "true" ]; then
    print_step "Dry Run Complete (no files were modified)."
    exit 0
fi

# Verification steps
print_step "Installation Summary"
if [ "$TARGET" = "all" ] || [ "$TARGET" = "agy" ]; then
    echo -e "${BOLD}Antigravity entry ($AGY_CONFIG_FILE):${NC}"
    jq --arg name "$SERVER_NAME" '.mcpServers[$name] | {command, args, env: {FORGEJO_URL: .env.FORGEJO_URL, FORGEJO_USER_AGENT: .env.FORGEJO_USER_AGENT, FORGEJO_ACCESS_TOKEN: "***"}}' "$AGY_CONFIG_FILE"
    echo ""
    if command -v agy &>/dev/null; then
        print_info "Verifying with 'agy mcp list':"
        agy mcp list || true
    fi
fi

if [ "$TARGET" = "all" ] || [ "$TARGET" = "opencode" ]; then
    echo -e "${BOLD}OpenCode entry ($OPENCODE_CONFIG_FILE):${NC}"
    jq --arg name "$SERVER_NAME" '.mcp.servers[$name] | {type, command, environment: {FORGEJO_URL: .environment.FORGEJO_URL, FORGEJO_USER_AGENT: .environment.FORGEJO_USER_AGENT, FORGEJO_ACCESS_TOKEN: "***"}}' "$OPENCODE_CONFIG_FILE"
    echo ""
    if command -v opencode &>/dev/null; then
        print_info "Verifying with 'opencode debug config':"
        opencode debug config 2>&1 | grep -A 10 "$SERVER_NAME" || true
    fi
fi

print_success "Forgejo MCP is now configured!"
