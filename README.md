# AI BU MCP Server Kit

A setup script that installs useful MCP (Model Context Protocol) servers for Claude Code. These servers connect Claude Code to external tools like GitHub, web fetching, and local filesystem access.

## What is MCP?

Model Context Protocol (MCP) is an open standard that lets AI assistants connect to external data sources and tools. When you add an MCP server to Claude Code, it gains the ability to interact with that service directly during your conversations.

## Included MCP Servers

### GitHub (`@modelcontextprotocol/server-github`)

Gives Claude Code access to GitHub. It can query repositories, issues, pull requests, file contents, and more. Useful when you want to work with GitHub data without leaving your terminal.

### Fetch (`@anthropic-ai/mcp-fetch`)

Lets Claude Code read the contents of any URL. If you need Claude to pull in documentation, API references, or any web page, this is the server that makes it happen.

### Filesystem (`@modelcontextprotocol/server-filesystem`)

Gives Claude Code controlled access to directories on your local machine. By default, the setup script points it at `~/projects`. You can change this path in your settings after running setup.

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed and working
- Node.js v18+ with `npx` available
- `jq` or `python3` for JSON processing (most systems have at least one)

## Quick Start

```bash
git clone https://github.com/MarkellR-RedHat/ai-bu-mcp-server-kit.git
cd ai-bu-mcp-server-kit
chmod +x setup.sh
./setup.sh
```

The script will:

1. Check that Claude Code and npx are installed.
2. Back up your existing `~/.claude/settings.json`.
3. Add the three MCP server configurations.

The script is idempotent. Running it again will overwrite the MCP entries with the same values, which is harmless.

## Configuration

After running setup, your MCP servers are configured in `~/.claude/settings.json` under the `mcpServers` key.

### Changing the Filesystem Path

By default, the filesystem server points to `~/projects`. To change it, edit `~/.claude/settings.json` and update the last argument in the filesystem entry:

```json
"filesystem": {
  "command": "npx",
  "args": ["-y", "@modelcontextprotocol/server-filesystem", "/your/preferred/path"]
}
```

### Adding a GitHub Token

For private repo access or higher API rate limits, set `GITHUB_PERSONAL_ACCESS_TOKEN` as an environment variable before launching Claude Code, or add an `env` block to the GitHub server entry. See `configs/github-mcp.json` for an example.

### Example Configs

The `configs/` directory contains standalone JSON snippets for each server. You can use these as reference if you want to manually add servers to your settings, or if you want to configure them in a project-level `.claude/settings.json` instead.

## Test It

After running setup, start Claude Code and try these prompts:

**GitHub MCP:**
```
List the open issues in MarkellR-RedHat/ai-bu-mcp-server-kit
```

**Fetch MCP:**
```
Fetch https://httpbin.org/get and show me the response
```

**Filesystem MCP:**
```
List the files in my projects directory
```

If Claude Code responds with actual data instead of an error, the MCP servers are working.

## Uninstall

To remove the MCP server entries from your Claude Code settings:

```bash
chmod +x uninstall.sh
./uninstall.sh
```

This removes the `github`, `fetch`, and `filesystem` entries from `~/.claude/settings.json`. A backup of your settings is created before any changes are made.

## Troubleshooting

**"npx not found"**: Install Node.js v18 or later. On macOS: `brew install node`. On Fedora/RHEL: `dnf install nodejs`.

**"Claude Code not found"**: Follow the install instructions at https://docs.anthropic.com/en/docs/claude-code.

**MCP server not responding**: Make sure npx can run the server manually. For example:
```bash
npx -y @modelcontextprotocol/server-github --help
```

**GitHub rate limiting**: Create a personal access token and set it as described in the Configuration section above.

## License

Apache-2.0
