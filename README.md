# AI BU MCP Server Kit

A setup script that installs useful MCP (Model Context Protocol) servers for Claude Code. These servers connect Claude Code to external tools like GitHub, web fetching, local filesystem access, web search, and persistent memory.

## What is MCP?

Model Context Protocol (MCP) is an open standard that lets AI assistants connect to external data sources and tools. When you add an MCP server to Claude Code, it gains the ability to interact with that service directly during your conversations.

## Included MCP Servers

| Server | Package | What it does | What it enables |
|--------|---------|-------------|-----------------|
| **GitHub** | `@modelcontextprotocol/server-github` | Connects to the GitHub API | Query repos, issues, PRs, file contents, and commit history |
| **Fetch** | `@anthropic-ai/mcp-fetch` | Reads the contents of any URL | Pull in docs, API references, web pages, and raw data |
| **Filesystem** | `@modelcontextprotocol/server-filesystem` | Controlled access to local directories | Read, list, and search files on your machine |
| **Brave Search** | `@anthropic-ai/mcp-server-brave-search` | Web search via Brave Search API | Search the web and get summarized results |
| **Memory** | `@modelcontextprotocol/server-memory` | Persistent key-value storage | Remember facts, preferences, and context across sessions |

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed and working
- Node.js v18+ with `npx` available
- `jq` or `python3` for JSON processing (most systems have at least one)
- (Optional) A `GITHUB_PERSONAL_ACCESS_TOKEN` for private repo access
- (Optional) A `BRAVE_API_KEY` for Brave Search ([get one here](https://brave.com/search/api/))

## Quick Start

```bash
git clone https://github.com/MarkellR-RedHat/ai-bu-mcp-server-kit.git
cd ai-bu-mcp-server-kit
chmod +x setup.sh verify.sh uninstall.sh
./setup.sh
```

The script will:

1. Check that Claude Code, npx, and a JSON tool are installed.
2. Back up your existing `~/.claude/settings.json`.
3. Ask you which MCP servers to install (or install all with `--all`).
4. Show a summary with test prompts you can try right away.

### Non-interactive install

To install all servers without being prompted:

```bash
./setup.sh --all
```

### Verify your setup

After running setup, confirm everything is working:

```bash
./verify.sh
```

This checks each configured MCP server by resolving its npm package and reports pass/fail results.

## What can I do with this?

Once your MCP servers are set up, open Claude Code and try these prompts:

```
List the open issues in MarkellR-RedHat/ai-bu-mcp-server-kit
```

```
Fetch https://httpbin.org/get and show me the response headers
```

```
List the files in my projects directory and summarize what each project does
```

```
Search the web for "latest Claude Code features" and summarize what you find
```

```
Remember that my preferred programming language is Python and I work on RHEL
```

```
What do you remember about my preferences?
```

If Claude Code responds with actual data instead of an error, the MCP servers are working.

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

### Adding a Brave Search API Key

Brave Search requires an API key. Get one at https://brave.com/search/api/ and add it to your settings:

```json
"brave-search": {
  "command": "npx",
  "args": ["-y", "@anthropic-ai/mcp-server-brave-search"],
  "env": {
    "BRAVE_API_KEY": "your-api-key-here"
  }
}
```

See `configs/brave-search-mcp.json` for a full example.

### Example Configs

The `configs/` directory contains standalone JSON snippets for each server. You can use these as reference if you want to manually add servers to your settings, or if you want to configure them in a project-level `.claude/settings.json` instead.

## Uninstall

To remove the MCP server entries from your Claude Code settings:

```bash
./uninstall.sh
```

This removes all MCP server entries that were added by setup.sh from `~/.claude/settings.json`. A backup of your settings is created before any changes are made.

## Troubleshooting

### "npx not found"

Install Node.js v18 or later.

- macOS: `brew install node`
- Fedora/RHEL: `dnf install nodejs`
- Ubuntu: `apt install nodejs npm`

### "Claude Code not found"

Install Claude Code:

```bash
npm install -g @anthropic-ai/claude-code
```

Or follow the full instructions at https://docs.anthropic.com/en/docs/claude-code.

### GITHUB_PERSONAL_ACCESS_TOKEN not set

Without a token, the GitHub MCP server works but is limited to public repos and lower rate limits. To fix this:

1. Create a token at https://github.com/settings/tokens (classic token with `repo` scope is fine).
2. Export it before running Claude Code:
   ```bash
   export GITHUB_PERSONAL_ACCESS_TOKEN="ghp_your_token_here"
   ```
3. Or add it to the `env` block in `~/.claude/settings.json` (see `configs/github-mcp.json`).

### BRAVE_API_KEY not set

Brave Search will not work without an API key. Sign up at https://brave.com/search/api/ to get one, then add it to the `env` block in your settings (see `configs/brave-search-mcp.json`).

### MCP server not responding

1. Make sure npx can run the server manually:
   ```bash
   npx -y @modelcontextprotocol/server-github --help
   ```
2. Run `./verify.sh` to check all servers at once.
3. Check that you have internet access (npx needs to download packages on first run).

### GitHub rate limiting

You are hitting GitHub's unauthenticated rate limit (60 requests/hour). Set `GITHUB_PERSONAL_ACCESS_TOKEN` as described above to raise the limit to 5,000 requests/hour.

### "jq not found" and "python3 not found"

The setup script needs at least one JSON processing tool. Install jq:

- macOS: `brew install jq`
- Fedora/RHEL: `dnf install jq`
- Ubuntu: `apt install jq`

## License

Apache-2.0
