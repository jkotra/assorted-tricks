#!/usr/bin/env bash
# ==============================================================================
# Script: install.sh
# Description: Installs and registers the Mozilla Firefox DevTools MCP server
#              for the Antigravity (agy) / Gemini CLI.
#              Uses `jq` to parse existing configurations and safely merge
#              the new MCP entry without overwriting existing servers.
#
# Upstream: https://github.com/mozilla/firefox-devtools-mcp
# ==============================================================================

set -euo pipefail

# Configuration defaults
DEFAULT_CONFIG_FILE="${HOME}/.gemini/config/mcp_config.json"
CONFIG_FILE="${MCP_CONFIG_FILE:-$DEFAULT_CONFIG_FILE}"
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

Installs and registers the Mozilla Firefox DevTools MCP server into Antigravity (agy)
or Gemini CLI's mcp_config.json using jq.

Options:
  -c, --config <path>          Path to mcp_config.json
                               (default: ~/.gemini/config/mcp_config.json)
  -n, --name <name>            Server identifier in mcp_config.json (default: firefox-devtools)
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
      --dry-run                Print the generated JSON configuration without writing to file
      --remove, --uninstall    Remove the server entry from mcp_config.json
      --verify                 Check environment prerequisites and test npx execution
  -l, --list                   List configured MCP servers in mcp_config.json
  -h, --help                   Display this help message and exit

Examples:
  # Standard installation (headless mode)
  ./install.sh

  # Install with visible browser GUI window
  ./install.sh --gui

  # Install with developer tool preset and custom viewport
  ./install.sh --tool-preset developer --viewport 1920x1080

  # Preview JSON changes without modifying config
  ./install.sh --dry-run

  # Check if requirements and package are working
  ./install.sh --verify

  # Remove server from configuration
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
        echo "    - Debian/Ubuntu: sudo apt-get install jq"
        echo "    - Arch Linux:    sudo pacman -S jq"
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

list_servers() {
    print_step "Configured MCP servers in: $CONFIG_FILE"
    if [ ! -f "$CONFIG_FILE" ]; then
        print_warn "Configuration file does not exist yet: $CONFIG_FILE"
        exit 0
    fi

    if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
        print_error "Configuration file is not valid JSON: $CONFIG_FILE"
        exit 1
    fi

    local server_count
    server_count=$(jq '.mcpServers // {} | length' "$CONFIG_FILE")
    print_info "Total servers configured: $server_count"

    if [ "$server_count" -gt 0 ]; then
        jq -r '.mcpServers // {} | to_entries[] | "  - \(.key): [command: \(.value.command // "N/A"), url: \(.value.serverUrl // "N/A")]"' "$CONFIG_FILE"
    fi
}

remove_server() {
    print_step "Removing MCP server '$SERVER_NAME'..."
    if [ ! -f "$CONFIG_FILE" ]; then
        print_warn "Configuration file does not exist: $CONFIG_FILE. Nothing to remove."
        exit 0
    fi

    if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
        print_error "Configuration file is not valid JSON: $CONFIG_FILE"
        exit 1
    fi

    local exists
    exists=$(jq --arg name "$SERVER_NAME" '.mcpServers // {} | has($name)' "$CONFIG_FILE")
    if [ "$exists" != "true" ]; then
        print_warn "Server '$SERVER_NAME' is not present in $CONFIG_FILE."
        exit 0
    fi

    if [ "$DRY_RUN" = "true" ]; then
        print_info "Dry run enabled. Updated JSON output without '$SERVER_NAME':"
        jq --arg name "$SERVER_NAME" 'del(.mcpServers[$name])' "$CONFIG_FILE"
        exit 0
    fi

    local backup_file="${CONFIG_FILE}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$CONFIG_FILE" "$backup_file"
    print_info "Created backup at: $backup_file"

    local temp_file
    temp_file=$(mktemp "${CONFIG_FILE}.tmp.XXXXXX")
    jq --arg name "$SERVER_NAME" 'del(.mcpServers[$name])' "$CONFIG_FILE" > "$temp_file"
    mv "$temp_file" "$CONFIG_FILE"

    print_success "Removed server '$SERVER_NAME' from $CONFIG_FILE."
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
        -c|--config)
            CONFIG_FILE="$2"
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

# Execute single-purpose actions if selected
if [ "$LIST_MODE" = "true" ]; then
    list_servers
    exit 0
fi

if [ "$VERIFY_MODE" = "true" ]; then
    verify_environment
    exit 0
fi

if [ "$REMOVE_MODE" = "true" ]; then
    remove_server
    exit 0
fi

# Main installation flow
check_dependencies

print_step "Preparing Firefox DevTools MCP configuration..."
print_info "Server identifier : $SERVER_NAME"
print_info "Target config file: $CONFIG_FILE"
print_info "npm package       : $PACKAGE_SPEC"
print_info "Headless mode     : $HEADLESS"
print_info "Initial viewport  : $VIEWPORT"
print_info "Start URL         : $START_URL"
if [ -n "$TOOL_PRESET" ]; then
    print_info "Tool preset       : $TOOL_PRESET"
fi

# Assemble arguments array
ARGS=("-y" "$PACKAGE_SPEC")

if [ "$HEADLESS" = "true" ]; then
    ARGS+=("--headless")
fi

if [ -n "$VIEWPORT" ]; then
    ARGS+=("--viewport" "$VIEWPORT")
fi

if [ -n "$START_URL" ]; then
    ARGS+=("--start-url" "$START_URL")
fi

if [ -n "$TOOL_PRESET" ]; then
    ARGS+=("--tool-preset" "$TOOL_PRESET")
fi

if [ -n "$FIREFOX_PATH" ]; then
    ARGS+=("--firefox-path" "$FIREFOX_PATH")
fi

if [ -n "$PROFILE_PATH" ]; then
    ARGS+=("--profile-path" "$PROFILE_PATH")
fi

if [ "$AUTO_PROFILE" = "true" ]; then
    ARGS+=("--auto-profile")
fi

if [ "$ACCEPT_INSECURE_CERTS" = "true" ]; then
    ARGS+=("--accept-insecure-certs")
fi

if [ "$UNRESTRICTED_SAVE_PATHS" = "true" ]; then
    ARGS+=("--unrestricted-save-paths")
fi

# Convert bash array to JSON array using jq
ARGS_JSON=$(printf '%s\n' "${ARGS[@]}" | jq -R . | jq -s .)

# Prepare env JSON object
ENV_JSON=$(jq -n --arg url "$START_URL" '{ "START_URL": $url }')

# Read or initialize config JSON
if [ -f "$CONFIG_FILE" ]; then
    if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
        print_error "Existing configuration file '$CONFIG_FILE' is not valid JSON."
        exit 1
    fi
    CURRENT_JSON=$(cat "$CONFIG_FILE")
    print_info "Parsed existing configuration file."
else
    print_info "No existing configuration file found at $CONFIG_FILE. Initializing new structure."
    CURRENT_JSON='{"mcpServers": {}}'
fi

# Merge configuration with jq while preserving all existing mcpServers
UPDATED_JSON=$(echo "$CURRENT_JSON" | jq \
    --arg name "$SERVER_NAME" \
    --arg cmd "$COMMAND" \
    --argjson args "$ARGS_JSON" \
    --argjson env "$ENV_JSON" \
    '
    .mcpServers = (.mcpServers // {}) |
    .mcpServers[$name] = {
        "command": $cmd,
        "args": $args,
        "env": $env
    }
    ')

# Verify generated JSON is valid
if ! echo "$UPDATED_JSON" | jq empty 2>/dev/null; then
    print_error "Failed to generate valid JSON configuration."
    exit 1
fi

if [ "$DRY_RUN" = "true" ]; then
    print_step "Dry Run Result (not written to file):"
    echo "$UPDATED_JSON" | jq .
    exit 0
fi

# Ensure target directory exists
CONFIG_DIR=$(dirname "$CONFIG_FILE")
mkdir -p "$CONFIG_DIR"

# Backup existing configuration if present
if [ -f "$CONFIG_FILE" ]; then
    BACKUP_FILE="${CONFIG_FILE}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$CONFIG_FILE" "$BACKUP_FILE"
    print_info "Created backup: $BACKUP_FILE"
fi

# Write updated configuration atomically
TEMP_FILE=$(mktemp "${CONFIG_DIR}/mcp_config.tmp.XXXXXX")
echo "$UPDATED_JSON" | jq . > "$TEMP_FILE"
mv "$TEMP_FILE" "$CONFIG_FILE"

print_step "Installation Summary"
print_success "Firefox DevTools MCP server registered successfully in $CONFIG_FILE"
echo ""
echo -e "${BOLD}Configured Entry:${NC}"
jq --arg name "$SERVER_NAME" '.mcpServers[$name]' "$CONFIG_FILE"
echo ""

# Verify with agy CLI if installed
if command -v agy &>/dev/null; then
    print_step "Verifying registration via 'agy mcp list':"
    agy mcp list || true
fi

print_success "All done! Firefox DevTools MCP is now configured for your Antigravity / Gemini CLI sessions."
