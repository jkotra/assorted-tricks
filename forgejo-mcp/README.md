# Forgejo Model Context Protocol (MCP) Integration

A robust Bash installer and configurator that sets up and registers the **Forgejo MCP Server** with both **Antigravity (`agy`) / Gemini CLI** and **OpenCode**.

The Forgejo MCP Server connects AI coding assistants directly to Forgejo (and Gitea/Codeberg) instances, enabling AI agents to read repositories, create issues, submit pull requests, manage branch files, inspect commit logs, and monitor CI/CD Actions workflows using natural language.

---

## Upstream & Project References

- **Canonical Repository**: [git.b4mad.industries/agentic-forges/forgejo-mcp](https://git.b4mad.industries/agentic-forges/forgejo-mcp)
- **GitHub Mirror**: [github.com/goern/forgejo-mcp](https://github.com/goern/forgejo-mcp)
- **Codeberg Mirror**: [codeberg.org/goern/forgejo-mcp](https://codeberg.org/goern/forgejo-mcp)
- **Model Context Protocol Specification**: [modelcontextprotocol.io](https://modelcontextprotocol.io/)

---

## Supported Clients & Target Paths

| Client | Default Configuration Path | Schema Section | Format |
| :--- | :--- | :--- | :--- |
| **Antigravity (`agy`) / Gemini CLI** | `~/.gemini/config/mcp_config.json` | `.mcpServers["forgejo"]` | `{"command": "...", "args": [...], "env": {...}}` |
| **OpenCode** | `~/.config/opencode/opencode.json` | `.mcp.servers["forgejo"]` | `{"type": "local", "command": [...], "environment": {...}}` |

---

## Prerequisites

- **`bash`** (v4.0 or newer)
- **`jq`**: JSON processor used to safely inspect, parse, and merge configurations.
- **`curl`**: For downloading pre-built binaries and verifying instance API connectivity.
- **`tar`**: For extracting downloaded release archives.
- **Network connectivity**: Access to your Forgejo instance.
- **Forgejo Personal Access Token**: A personal access token generated with the required permissions (e.g. repository read/write, issue tracking).

---

## Quick Start

### 1. Install & Configure for Both Clients (Antigravity & OpenCode)

```bash
./install.sh --token "<your-forgejo-token>"
```

### 2. Configure with a Custom Forgejo URL

```bash
./install.sh --url "https://git.example.org" --token "<your-token>"
```

### 3. Verify the Installation

```bash
# Test environment, binary, and API connectivity
./install.sh --verify --token "<your-token>"

# Verify Antigravity registration (if agy is installed)
agy mcp list

# Verify OpenCode registration (if opencode is installed)
opencode debug config
```

---

## Features

- **Multi-Client Support**: Simultaneously or individually configures Antigravity (`agy`) and OpenCode.
- **Automatic Binary Management**: Automatically downloads and installs the matching pre-compiled `forgejo-mcp` binary (`x86_64` / `amd64` or `aarch64` / `arm64`) into `~/.local/bin` if not already present.
- **Non-Destructive Safe Merging**: Uses `jq` to surgically update the `"forgejo"` server entry without touching or overwriting other existing MCP servers (e.g. `firefox-devtools`, `printlore`, custom bridges).
- **Automated Backups**: Generates timestamped `.bak.<timestamp>` copies of existing config files prior to writing modifications.
- **Atomic File Updates**: Writes changes through temporary files before atomically replacing target configs, avoiding file corruption.
- **Credential Protection**: Stores tokens securely inside MCP environment blocks (`env` / `environment`) rather than exposing them in process command-line arguments.
- **Self-Verifying**: Includes `--verify` to check binary execution, validate instance reachability, and test token authentication against the Forgejo REST API.
- **Dry-Run Preview**: Supports `--dry-run` to inspect proposed JSON changes without modifying any files.
- **Clean Uninstallation**: Supports `--remove` (`--uninstall`) to cleanly excise the server definition from targeted client configs.

---

## CLI Options & Flags

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
```

---

## Usage Examples

### Standard Installation with Token
```bash
./install.sh --token "91ee5fd16ff9d2ee86b78bae82cd671f4e02d766"
```

### Using Environment Variable for Token
```bash
export FORGEJO_ACCESS_TOKEN="91ee5fd16ff9d2ee86b78bae82cd671f4e02d766"
./install.sh
```

### Configure OpenCode Only
```bash
./install.sh --target opencode --token "91ee5fd16ff9d2ee86b78bae82cd671f4e02d766"
```

### Configure Antigravity (`agy`) Only
```bash
./install.sh --target agy --token "91ee5fd16ff9d2ee86b78bae82cd671f4e02d766"
```

### Custom Forgejo Instance URL
```bash
./install.sh --url "https://git.b4mad.industries" --token "<token>"
```

### Dry Run (Preview Output Without Saving)
```bash
./install.sh --dry-run --token "<token>"
```

### List Registered MCP Servers
```bash
./install.sh --list
```

### Verify Installation & Connectivity
```bash
./install.sh --verify --token "<token>"
```

### Remove Server from Configurations
```bash
./install.sh --remove
```

---

## Technical Details

### Antigravity (`agy`) Configuration Schema

In `~/.gemini/config/mcp_config.json`, servers are stored under `.mcpServers`:

```json
{
  "mcpServers": {
    "forgejo": {
      "command": "/home/user/.local/bin/forgejo-mcp",
      "args": [
        "--transport",
        "stdio",
        "--url",
        "https://git.home.0101.party"
      ],
      "env": {
        "FORGEJO_ACCESS_TOKEN": "...",
        "FORGEJO_URL": "https://git.home.0101.party",
        "FORGEJO_USER_AGENT": "forgejo-mcp/3.3.0"
      }
    }
  }
}
```

### OpenCode Configuration Schema

In `~/.config/opencode/opencode.json`, servers are stored under `.mcp.servers`:

```json
{
  "mcp": {
    "servers": {
      "forgejo": {
        "type": "local",
        "command": [
          "/home/user/.local/bin/forgejo-mcp",
          "--transport",
          "stdio",
          "--url",
          "https://git.home.0101.party"
        ],
        "environment": {
          "FORGEJO_ACCESS_TOKEN": "...",
          "FORGEJO_URL": "https://git.home.0101.party",
          "FORGEJO_USER_AGENT": "forgejo-mcp/3.3.0"
        }
      }
    }
  }
}
```

---

## Available Capabilities & Tools

Once configured, AI assistants gain native tool access to your Forgejo instance:

| Category | Available Operations |
| :--- | :--- |
| **Repositories** | Search repos, inspect metadata, list branches, tags, and topics. |
| **Files & Git Trees** | Read file contents (`get_file_content`), list directory trees (`get_repo_tree`), create/update files, and apply diff patches. |
| **Issues** | Search issues, create new issues, add comments, manage labels, assignees, milestones, and dependencies. |
| **Pull Requests** | List pull requests, inspect PR diffs, review PRs, submit review comments, and merge PRs. |
| **Actions & CI/CD** | List workflow runs, inspect job status, and fetch build logs. |
| **Releases & Attachments** | List releases, upload assets, and manage release notes. |
| **Wiki** | Read, create, update, and list wiki revisions. |
