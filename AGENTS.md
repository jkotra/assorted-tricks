# Agent Guidelines for `assorted-tricks`

This repository is a curated collection of standalone developer utilities, automation recipes, MCP integrations, and system tricks.

All agents operating in this workspace must strictly adhere to the following conventions and workflows when creating, modifying, or refactoring tools.

---

## Core Rules & Responsibilities

### 1. Mandatory Subdirectory Structure
Every new trick, script, or tool **must** be created in its own dedicated, self-contained subdirectory at the repository root.
- Use lowercase `kebab-case` naming (e.g., `firefox-devtools-mcp-agy`).
- Never place standalone scripts or one-off files loosely in the repository root.

### 2. Trick-Specific `README.md` is Mandatory
Every trick directory **must** contain its own comprehensive `README.md` file. It should include:
- **Overview & Upstream References**: What the tool does and links to upstream projects/specs where applicable.
- **Prerequisites**: Minimum required runtimes, system packages, or binaries (e.g., `jq`, `node >= 20.19`, `firefox`).
- **Quick Start**: Clear copy-paste commands to run the tool.
- **CLI Options / Flags**: Full reference of all supported arguments, defaults, and environment variables.
- **Usage Examples**: Concrete examples for typical, advanced, dry-run, and uninstall scenarios.
- **Technical Details / Architecture**: Explanation of how the script functions internally.

### 3. Maintain the Central Index (`/README.md`)
Whenever adding, renaming, or removing a trick, the agent **must** immediately update the root `README.md` index:
- Add a row to the **Index of Tricks** table linking to the trick directory.
- Provide a concise description, relevant tags/technologies, and directory link.
- Update the directory tree layout in the root `README.md` if present.

### 4. Script Quality & Standards
- **Shebang & Safety**: All shell scripts must start with `#!/usr/bin/env bash` and enable strict mode (`set -euo pipefail`).
- **Permissions**: Ensure scripts are marked executable (`chmod +x <script>`).
- **Self-Documenting**: Scripts must support `--help` (`-h`) displaying comprehensive usage, options, and practical examples.
- **Dependency Checks**: Always inspect required binaries (using `command -v`) early in execution and provide actionable install instructions if missing.
- **Safety & Non-Destructive Operations**:
  - Always back up existing user configuration files before modifying them (e.g., `.bak.<timestamp>`).
  - Use atomic write techniques (temporary files + `mv`) when updating configs.
  - Provide a `--dry-run` option when mutating system or application configuration files.
  - Preserve all existing user configuration entries (e.g., using `jq` for JSON merging).
- **Exit Codes**: Return `0` on success and non-zero on errors, logging diagnostic messages to standard error (`>&2`).

### 5. Verification & Testing
Before declaring a task complete:
- Execute syntax checks on scripts (`bash -n <script>`).
- Test `--help`, `--dry-run`, or verification modes.
- Verify that both the trick's `README.md` and the root `README.md` index are accurate and up to date.
