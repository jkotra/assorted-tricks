#!/usr/bin/env bash
# ==============================================================================
# Script: install.sh
# Description: Installs and registers the Mozilla Firefox DevTools MCP server
#              for Antigravity (agy) / Gemini CLI and OpenCode.
#              Uses `jq` to parse existing configurations and safely merge
#              the new MCP entry without overwriting existing servers.
#
# Upstream: https://github.com/mozilla/firefox-devtools-mcp
# ==============================================================================

set -euo pipefail

# Configuration defaults
DEFAULT_AGY_CONFIG="${HOME}/.gemini/config/mcp_config.json"
DEFAULT_OPENCODE_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/opencode.json"

AGY_CONFIG_FILE="${AGY_CONFIG_FILE:-${MCP_CONFIG_FILE:-$DEFAULT_AGY_CONFIG}}"
OPENCODE_CONFIG_FILE="${OPENCODE_CONFIG_FILE:-$DEFAULT_OPENCODE_CONFIG}"

TARGET="all" # all | agy | opencode
SERVER_NAME="firefox-devtools"
PACKAGE_SPEC="@mozilla/firefox-devtools-mcp@latest"
COMMAND="npx"

# Server CLI flags
HEADLESS="true"
VIEWPORT="1280x720"
START_URL="about:blank"
TOOL_PRESET=""
FIREFOX_PATH=""
PROFILE_PATH=""
AUTO_PROFILE="false"
ACCEPT_INSECURE_CERTS="false"
UNRESTRICTED_SAVE_PATHS="false"

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

Installs and registers the Mozilla Firefox DevTools MCP server into Antigravity (agy),
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

Server Options:
  -n, --name <name>            Server identifier (default: firefox-devtools)
  -p, --package <spec>         npm package specifier (default: @mozilla/firefox-devtools-mcp@latest)
      --gui, --no-headless     Launch Firefox with GUI (visible browser window)
      --headless               Launch Firefox in headless mode (default: true)
      --viewport <WxH>         Initial viewport size (default: 1280x720)
      --start-url <url>        Initial URL to open (default: about:blank)
      --tool-preset <preset>   Tool preset: slim | basic | developer | mozilla | all
      --firefox-path <path>    Explicit path to Firefox executable binary
      --profile-path <path>    Explicit path to a dedicated Firefox profile directory
      --auto-profile           Use persistent profile in ~/.firefox-devtools-mcp/
      --accept-insecure-certs  Ignore TLS certificate errors
      --unrestricted-paths     Allow tools to save files anywhere on the system

Script Modes:
      --dry-run                Print the generated JSON configuration without writing to file
      --remove, --uninstall    Remove the server entry from target configuration(s)
      --verify                 Check environment prerequisites and test npx execution
  -l, --list                   List configured MCP servers in target configuration(s)
  -h, --help                   Display this help message and exit

Examples:
  # Install for both Antigravity (agy) and OpenCode (default, headless mode)
  ./install.sh

  # Install only for OpenCode
  ./install.sh --target opencode

  # Install only for Antigravity (agy)
  ./install.sh --target agy

  # Install with visible browser GUI window
  ./install.sh --gui

  # Install with developer tool preset and custom viewport
  ./install.sh --tool-preset developer --viewport 1920x1080

  # Preview JSON changes without modifying any files
  ./install.sh --dry-run

  # Check if requirements and package are working
  ./install.sh --verify

  # Remove server from all configurations
  ./install.sh --remove
EOF
}

check_dependencies() {
    print_step "Checking required dependencies..."
    local missing=0

    if command -v jq &>/dev/null; then
        print_success "jq: $(jq --version) found at $(command -v jq)"
    else
        print_error "'jq' command is required but not installed."
        echo "  Install via your package manager, e.g.:"
        echo "    - Arch Linux:    sudo pacman -S jq"
        echo "    - Debian/Ubuntu: sudo apt-get install jq"
        echo "    - Fedora:        sudo dnf install jq"
        missing=1
    fi

    if command -v node &>/dev/null; then
        print_success "node: $(node --version) found at $(command -v node)"
    else
        print_error "'node' command is required (Node.js >= 20.19.0)."
        missing=1
    fi

    if command -v npx &>/dev/null; then
        print_success "npx: $(npx --version) found at $(command -v npx)"
    else
        print_error "'npx' command is required but not installed."
        missing=1
    fi

    if [ -n "$FIREFOX_PATH" ]; then
        if [ -x "$FIREFOX_PATH" ]; then
            print_success "firefox: custom path '$FIREFOX_PATH' is executable"
        else
            print_warn "Specified Firefox binary '$FIREFOX_PATH' does not exist or is not executable."
        fi
    elif command -v firefox &>/dev/null; then
        print_success "firefox: $(firefox --version 2>/dev/null || echo 'installed') found at $(command -v firefox)"
    else
        print_warn "'firefox' binary was not found in PATH. You may need to pass --firefox-path."
    fi

    if [ "$missing" -ne 0 ]; then
        print_error "Missing required dependencies. Please install them and try again."
        exit 1
    fi
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
    print_step "Testing Firefox DevTools MCP package via npx..."
    if npx -y "$PACKAGE_SPEC" --version; then
        print_success "Successfully verified $PACKAGE_SPEC."
    else
        print_error "Failed to execute $PACKAGE_SPEC via npx."
        exit 1
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
            if [ "$TARGET" = "opencode" ]; then
                OPENCODE_CONFIG_FILE="$2"
            else
                AGY_CONFIG_FILE="$2"
            fi
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
        -n|--name)
            SERVER_NAME="$2"
            shift 2
            ;;
        -p|--package)
            PACKAGE_SPEC="$2"
            shift 2
            ;;
        --gui|--no-headless)
            HEADLESS="false"
            shift
            ;;
        --headless)
            HEADLESS="true"
            shift
            ;;
        --viewport)
            VIEWPORT="$2"
            shift 2
            ;;
        --start-url)
            START_URL="$2"
            shift 2
            ;;
        --tool-preset)
            TOOL_PRESET="$2"
            shift 2
            ;;
        --firefox-path)
            FIREFOX_PATH="$2"
            shift 2
            ;;
        --profile-path)
            PROFILE_PATH="$2"
            shift 2
            ;;
        --auto-profile)
            AUTO_PROFILE="true"
            shift
            ;;
        --accept-insecure-certs)
            ACCEPT_INSECURE_CERTS="true"
            shift
            ;;
        --unrestricted-paths)
            UNRESTRICTED_SAVE_PATHS="true"
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
            print_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate target selection
case "$TARGET" in
    all|both)
        TARGET="all"
        ;;
    agy|gemini)
        TARGET="agy"
        ;;
    opencode)
        TARGET="opencode"
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

print_step "Preparing Firefox DevTools MCP configuration..."
print_info "Target(s)         : $TARGET"
print_info "Server identifier : $SERVER_NAME"
if [ "$TARGET" = "all" ] || [ "$TARGET" = "agy" ]; then
    print_info "Antigravity config: $AGY_CONFIG_FILE"
fi
if [ "$TARGET" = "all" ] || [ "$TARGET" = "opencode" ]; then
    print_info "OpenCode config   : $OPENCODE_CONFIG_FILE"
fi
print_info "npm package       : $PACKAGE_SPEC"
print_info "Headless mode     : $HEADLESS"
print_info "Initial viewport  : $VIEWPORT"
print_info "Start URL         : $START_URL"
if [ -n "$TOOL_PRESET" ]; then
    print_info "Tool preset       : $TOOL_PRESET"
fi

# Assemble arguments array (for agy)
AGY_ARGS=("-y" "$PACKAGE_SPEC")

if [ "$HEADLESS" = "true" ]; then
    AGY_ARGS+=("--headless")
fi

if [ -n "$VIEWPORT" ]; then
    AGY_ARGS+=("--viewport" "$VIEWPORT")
fi

if [ -n "$START_URL" ]; then
    AGY_ARGS+=("--start-url" "$START_URL")
fi

if [ -n "$TOOL_PRESET" ]; then
    AGY_ARGS+=("--tool-preset" "$TOOL_PRESET")
fi

if [ -n "$FIREFOX_PATH" ]; then
    AGY_ARGS+=("--firefox-path" "$FIREFOX_PATH")
fi

if [ -n "$PROFILE_PATH" ]; then
    AGY_ARGS+=("--profile-path" "$PROFILE_PATH")
fi

if [ "$AUTO_PROFILE" = "true" ]; then
    AGY_ARGS+=("--auto-profile")
fi

if [ "$ACCEPT_INSECURE_CERTS" = "true" ]; then
    AGY_ARGS+=("--accept-insecure-certs")
fi

if [ "$UNRESTRICTED_SAVE_PATHS" = "true" ]; then
    AGY_ARGS+=("--unrestricted-save-paths")
fi

# For OpenCode, full command array includes the binary as first element
OPENCODE_CMD=("$COMMAND" "${AGY_ARGS[@]}")

# Convert bash arrays to JSON arrays using jq
AGY_ARGS_JSON=$(printf '%s\n' "${AGY_ARGS[@]}" | jq -R . | jq -s .)
OPENCODE_CMD_JSON=$(printf '%s\n' "${OPENCODE_CMD[@]}" | jq -R . | jq -s .)

# Prepare env JSON object
ENV_JSON=$(jq -n --arg url "$START_URL" '{ "START_URL": $url }')

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
        --arg cmd "$COMMAND" \
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
    jq --arg name "$SERVER_NAME" '.mcpServers[$name]' "$AGY_CONFIG_FILE"
    echo ""
    if command -v agy &>/dev/null; then
        print_info "Verifying with 'agy mcp list':"
        agy mcp list || true
    fi
fi

if [ "$TARGET" = "all" ] || [ "$TARGET" = "opencode" ]; then
    echo -e "${BOLD}OpenCode entry ($OPENCODE_CONFIG_FILE):${NC}"
    jq --arg name "$SERVER_NAME" '.mcp.servers[$name]' "$OPENCODE_CONFIG_FILE"
    echo ""
    if command -v opencode &>/dev/null; then
        print_info "Verifying with 'opencode debug config':"
        opencode debug config 2>&1 | grep -A 10 "$SERVER_NAME" || true
    fi
fi

print_success "Firefox DevTools MCP is now configured!"
