# Firefox DevTools MCP for Antigravity (agy) / Gemini CLI

Automated installer and configurator for the Mozilla [Firefox DevTools MCP server](https://github.com/mozilla/firefox-devtools-mcp) in Google Antigravity (`agy`) and Gemini CLI.

This tool safely parses your existing `~/.gemini/config/mcp_config.json` using **`jq`**, preserving all previously configured MCP servers (such as terminal controllers, database connectors, or custom services), and adds or updates the `firefox-devtools` server definition.

---

## Prerequisites

- **Node.js**: `v20.19.0+`
- **npm / npx**: installed with Node.js
- **jq**: command-line JSON processor (`jq-1.6+` or higher)
- **Mozilla Firefox**: Firefox 100+ installed on the host system

---

## Quick Start

Run the installer directly from this folder:

```bash
./install.sh
```

To verify your installation with `agy`:

```bash
agy mcp list
```

---

## Features

- **Safe JSON Merging with `jq`**: Reads existing MCP configurations, safely appends or updates the `firefox-devtools` entry, and validates JSON integrity before applying.
- **Automatic Backups**: Creates a timestamped `.bak` copy of `mcp_config.json` prior to any modifications.
- **Configurable Modes**:
  - Headless mode (default, runs in the background without opening a browser window)
  - GUI mode (`--gui`, opens an interactive Firefox window)
  - Tool presets (`--tool-preset` with `slim`, `basic`, `developer`, `mozilla`, or `all`)
  - Custom viewport resolution, start URL, and persistent profiles
- **Dry-run Mode**: Inspect the generated JSON structure with `--dry-run` without touching your configuration file.
- **Clean Uninstallation**: Safely remove the server entry with `--remove`.

---

## Usage & CLI Options

```text
Usage: ./install.sh [OPTIONS]

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
```

---

## Examples

### 1. Standard Headless Installation
```bash
./install.sh
```

### 2. Visible GUI Window with Developer Preset
```bash
./install.sh --gui --tool-preset developer --viewport 1920x1080
```

### 3. Persistent Profile & Custom Start URL
```bash
./install.sh --auto-profile --start-url https://google.com
```

### 4. Preview Changes (Dry Run)
```bash
./install.sh --dry-run
```

### 5. Check Requirements & Test npx Package
```bash
./install.sh --verify
```

### 6. Remove Server
```bash
./install.sh --remove
```

---

## How It Works Under the Hood

The script reads the existing configuration from `~/.gemini/config/mcp_config.json` (or initializes a blank configuration if none exists). It then passes the parsed parameters to `jq`:

```bash
jq \
  --arg name "$SERVER_NAME" \
  --arg cmd "npx" \
  --argjson args "$ARGS_JSON" \
  --argjson env "$ENV_JSON" \
  '
  .mcpServers = (.mcpServers // {}) |
  .mcpServers[$name] = {
      "command": $cmd,
      "args": $args,
      "env": $env
  }
  ' "$CONFIG_FILE"
```

The resulting JSON is checked with `jq empty` to guarantee syntactic validity before being atomically moved into place.

---

## Available Tools Provided by Firefox DevTools MCP

When active in an `agy` or Gemini session, the model gains access to tools such as:

| Tool | Purpose |
| :--- | :--- |
| `list_pages` | List active browser tabs/pages |
| `select_page` | Switch active tab context |
| `navigate_page` | Navigate current page to a URL |
| `take_snapshot` | Inspect the page accessibility tree and DOM elements with UID handles |
| `click_by_uid` | Click an element identified by UID |
| `fill_by_uid` | Type text into an input element |
| `screenshot_page` | Capture a screenshot of the current page |
| `list_network_requests` | Inspect ongoing and completed HTTP network requests |
| `list_console_messages` | View JavaScript console logs, errors, and warnings |
| `evaluate_script` | Run JavaScript directly in the page context |
