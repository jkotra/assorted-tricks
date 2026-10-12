# Firefox DevTools MCP for Antigravity (agy) & OpenCode

Automated installer and configurator for the Mozilla [Firefox DevTools MCP server](https://github.com/mozilla/firefox-devtools-mcp) in Google Antigravity (`agy`), Gemini CLI, and [OpenCode](https://github.com/opencode-ai/opencode).

This tool safely parses your configuration files using **`jq`**, preserving all previously configured MCP servers (such as terminal controllers, database connectors, or custom services), and adds or updates the `firefox-devtools` server definition across either or both platforms.

---

## Supported Clients & Configuration Paths

| Client | Default Configuration Path | Configuration Structure |
| :--- | :--- | :--- |
| **Antigravity (`agy`) / Gemini CLI** | `~/.gemini/config/mcp_config.json` | `.mcpServers["firefox-devtools"]` (`command`, `args`, `env`) |
| **OpenCode** | `~/.config/opencode/opencode.json` | `.mcp.servers["firefox-devtools"]` (`type: "local"`, `command: [...]`, `environment`) |

---

## Prerequisites

- **Node.js**: `v20.19.0+`
- **npm / npx**: installed with Node.js
- **jq**: command-line JSON processor (`jq-1.6+` or higher)
- **Mozilla Firefox**: Firefox 100+ installed on the host system

---

## Quick Start

Run the installer directly from this folder to configure both Antigravity and OpenCode:

```bash
./install.sh
```

To configure only one specific client:

```bash
# Antigravity / Gemini CLI only
./install.sh --target agy

# OpenCode only
./install.sh --target opencode
```

To verify your installation:

```bash
# Verify Antigravity registration
agy mcp list

# Verify OpenCode registration
opencode debug config
```

---

## Features

- **Multi-Client Support**: Seamlessly configure Antigravity (`agy`) and OpenCode with a single command or target individual clients.
- **Safe JSON Merging with `jq`**: Reads existing MCP configurations, safely appends or updates the `firefox-devtools` entry, and validates JSON integrity before applying.
- **Automatic Backups**: Creates timestamped `.bak` copies of config files prior to any modifications.
- **Configurable Modes**:
  - Headless mode (default, runs in the background without opening a browser window)
  - GUI mode (`--gui`, opens an interactive Firefox window)
  - Tool presets (`--tool-preset` with `slim`, `basic`, `developer`, `mozilla`, or `all`)
  - Custom viewport resolution, start URL, and persistent profiles
- **Dry-run Mode**: Inspect the generated JSON structure with `--dry-run` without touching your configuration file.
- **Clean Uninstallation**: Safely remove the server entry from all or selected clients with `--remove`.

---

## Usage & CLI Options

```text
Usage: ./install.sh [OPTIONS]

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
```

---

## Examples

### 1. Standard Installation for Both Clients
```bash
./install.sh
```

### 2. Configure for OpenCode Only
```bash
./install.sh --target opencode
```

### 3. Visible GUI Window with Developer Preset
```bash
./install.sh --gui --tool-preset developer --viewport 1920x1080
```

### 4. Persistent Profile & Custom Start URL
```bash
./install.sh --auto-profile --start-url https://google.com
```

### 5. Preview Changes (Dry Run)
```bash
./install.sh --dry-run
```

### 6. List Configured Servers
```bash
./install.sh --list
```

### 7. Check Requirements & Test npx Package
```bash
./install.sh --verify
```

### 8. Remove Server from Both Clients
```bash
./install.sh --remove
```

---

## Technical Details

### Antigravity (`agy`) JSON Schema
The script registers the server in `~/.gemini/config/mcp_config.json` under `.mcpServers`:

```json
{
  "mcpServers": {
    "firefox-devtools": {
      "command": "npx",
      "args": [
        "-y",
        "@mozilla/firefox-devtools-mcp@latest",
        "--headless",
        "--viewport",
        "1280x720",
        "--start-url",
        "about:blank"
      ],
      "env": {
        "START_URL": "about:blank"
      }
    }
  }
}
```

### OpenCode JSON Schema
The script registers the server in `~/.config/opencode/opencode.json` under `.mcp.servers`:

```json
{
  "mcp": {
    "servers": {
      "firefox-devtools": {
        "type": "local",
        "command": [
          "npx",
          "-y",
          "@mozilla/firefox-devtools-mcp@latest",
          "--headless",
          "--viewport",
          "1280x720",
          "--start-url",
          "about:blank"
        ],
        "environment": {
          "START_URL": "about:blank"
        }
      }
    }
  }
}
```

The resulting JSON is checked with `jq empty` to guarantee syntactic validity before being atomically moved into place using temporary files (`mktemp` + `mv`).

---

## Available Tools Provided by Firefox DevTools MCP

When active in an `agy` or OpenCode session, the model gains access to tools such as:

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
