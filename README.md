# Assorted Tricks

A curated repository of standalone developer utilities, automation recipes, Model Context Protocol (MCP) integrations, and developer workflow scripts.

---

## Index of Tricks & Utilities

| Trick / Utility | Category | Description | Technologies |
| :--- | :--- | :--- | :--- |
| [**`firefox-devtools-mcp`**](./firefox-devtools-mcp/) | MCP Integration / Browser Automation | Bash installer to register Mozilla Firefox DevTools MCP server with Antigravity (`agy`), Gemini CLI, and OpenCode using `jq` to parse and safely merge configurations. | Bash, `jq`, Node.js, `npx`, Firefox, OpenCode |
| [**`forgejo-mcp`**](./forgejo-mcp/) | MCP Integration / Git Forge | Bash installer and configurator to register Forgejo MCP server with Antigravity (`agy`), Gemini CLI, and OpenCode with automatic binary fetching and safe `jq` config merging. | Bash, `jq`, `curl`, `tar`, Forgejo, OpenCode |
| [**`helium-profile-shortcuts-gnome`**](./helium-profile-shortcuts-gnome/) | Desktop Integration / Shortcuts | Script to create, list, and remove GNOME desktop launcher shortcuts for individual Helium browser profiles with custom HTML color code icons, dash pinning, and desktop support. | Bash, `jq`, Python 3, GNOME Shell, FreeDesktop |

---

## Repository Structure

```text
.
├── AGENTS.md                           # Agent guidelines for adding and updating tricks
├── LICENSE                             # MIT License
├── README.md                           # Central index and directory of all tricks
├── firefox-devtools-mcp/               # Firefox DevTools MCP installer for Antigravity & OpenCode
│   ├── install.sh                      # Executable installer and configurator
│   └── README.md                       # Detailed documentation and usage instructions
├── forgejo-mcp/                        # Forgejo MCP installer for Antigravity & OpenCode
│   ├── install.sh                      # Executable installer and configurator
│   └── README.md                       # Detailed documentation and usage instructions
└── helium-profile-shortcuts-gnome/     # GNOME shortcut manager for Helium profiles
    ├── manage-shortcuts.sh             # Executable shortcut manager
    └── README.md                       # Detailed documentation and usage instructions
```

---

## Contributing & Adding New Tricks

Every trick in this repository follows strict modular conventions outlined in [AGENTS.md](./AGENTS.md):

1. **Dedicated Directory**: Each utility or trick resides in its own `kebab-case` subdirectory.
2. **Dedicated Documentation**: Every trick must have a comprehensive `README.md` detailing prerequisites, CLI options, examples, and technical details.
3. **Index Maintenance**: Any new, modified, or removed trick must be reflected in the index table above.
4. **Script Standards**: Scripts must use strict bash (`set -euo pipefail`), include `--help`, perform safety backups, and check prerequisites before execution.

---

## License

This repository is licensed under the [MIT License](./LICENSE).
