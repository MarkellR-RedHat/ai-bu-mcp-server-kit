# MCP Server Kit for Claude Code

**Claude Code is powerful out of the box. But without MCP servers, it is boxed in.**

It cannot search the web. It cannot query your database. It cannot read a URL you paste into the conversation. It cannot remember what you told it yesterday.

MCP servers fix that. This kit installs and configures them in under 3 minutes.

## Before and After

| Without MCP servers | With MCP servers |
|---|---|
| Manually paste file contents into your prompt | Claude reads and writes files in your project directories |
| No web access at all | Fetch any URL, API response, or documentation page directly |
| Copy-paste GitHub issues into the conversation | Query repos, PRs, issues, and commit history live |
| Cannot search the internet | Search the web via Brave Search and pull current results |
| No database access | Query PostgreSQL and SQLite databases in conversation |
| Context resets every session | Persistent memory that carries across sessions |
| "I don't have access to that" | "Here's what I found" |

## Quick Start

```bash
git clone https://github.com/MarkellR-RedHat/ai-bu-mcp-server-kit.git
cd ai-bu-mcp-server-kit
chmod +x setup.sh verify.sh uninstall.sh
./setup.sh
```

That is the whole thing. The setup script checks your prerequisites, walks you through server selection, and verifies each package resolves.

**Want to skip the prompts?**

```bash
# Install everything, no questions asked
./setup.sh --all

# Install only the essentials (GitHub, Fetch, Filesystem)
./setup.sh --minimal
```

### Full enterprise setup

For teams that want every server configured with real credentials from the start:

```bash
# 1. Export your API keys first (add these to ~/.bashrc or ~/.zshrc to persist):
export GITHUB_PERSONAL_ACCESS_TOKEN="ghp_your_token"
export BRAVE_API_KEY="BSA_your_key"
export SLACK_BOT_TOKEN="xoxb-your-token"
export SLACK_TEAM_ID="T01XXXXXX"
export GOOGLE_MAPS_API_KEY="AIza_your_key"

# 2. Install all 13 servers, no prompts:
./setup.sh --all -y

# 3. Verify everything connected:
./verify.sh
```

After setup, customize paths and connection strings in `~/.claude/settings.json`:

```json
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/home/engineer/projects", "/opt/app/config"]
    },
    "postgres": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-postgres", "postgresql://dev:dev@localhost:5432/myapp?sslmode=require"]
    }
  }
}
```

See [advanced-patterns.md](advanced-patterns.md) for project-level configs, multi-database setups, and team-shared configurations.

## Available Servers

### The essentials (installed with `--minimal`)

| Server | Package | What it does |
|--------|---------|-------------|
| **GitHub** | `@modelcontextprotocol/server-github` | Query repos, issues, PRs, file contents, and commit history |
| **Fetch** | `@anthropic-ai/mcp-fetch` | Read the contents of any URL: docs, APIs, web pages, raw data |
| **Filesystem** | `@modelcontextprotocol/server-filesystem` | Controlled read/write/search access to local directories |

### Search and research

| Server | Package | What it does |
|--------|---------|-------------|
| **Brave Search** | `@anthropic-ai/mcp-server-brave-search` | Web search via Brave Search API (requires API key) |
| **Context7** | `@upstash/context7-mcp` | Up-to-date library documentation pulled from source |

### Memory and reasoning

| Server | Package | What it does |
|--------|---------|-------------|
| **Memory** | `@modelcontextprotocol/server-memory` | Persistent key-value storage across Claude Code sessions |
| **Sequential Thinking** | `@modelcontextprotocol/server-sequential-thinking` | Structured step-by-step reasoning for complex problems |

### Database

| Server | Package | What it does |
|--------|---------|-------------|
| **PostgreSQL** | `@modelcontextprotocol/server-postgres` | Query and inspect PostgreSQL databases |
| **SQLite** | `@modelcontextprotocol/server-sqlite` | Query and inspect SQLite database files |

### Browser and automation

| Server | Package | What it does |
|--------|---------|-------------|
| **Puppeteer** | `@modelcontextprotocol/server-puppeteer` | Browser automation: screenshots, clicks, form fills, navigation |

### Communication

| Server | Package | What it does |
|--------|---------|-------------|
| **Slack** | `@modelcontextprotocol/server-slack` | Read and post messages in Slack channels (requires bot token) |

### Location

| Server | Package | What it does |
|--------|---------|-------------|
| **Google Maps** | `@modelcontextprotocol/server-google-maps` | Geocoding, directions, and place search (requires API key) |

### Creative

| Server | Package | What it does |
|--------|---------|-------------|
| **EverArt** | `@modelcontextprotocol/server-everart` | AI image generation and model training (requires API key) |

## Try It

After setup, restart Claude Code and try these:

```
List the open issues in MarkellR-RedHat/ai-bu-mcp-server-kit
```

```
Fetch https://httpbin.org/get and show me the response headers
```

```
Search the web for "latest Claude Code features" and summarize what you find
```

```
Remember that my preferred programming language is Python and I work on RHEL
```

If Claude responds with real data instead of "I don't have access to that," your MCP servers are working.

**Cross-tool smoke tests:**
- Run `/briefing` in Claude Code to test the GitHub MCP server end to end
- Run `/upstream vllm` in Claude Code to test fetch + GitHub servers together

## Setup Options

### Interactive mode (default)

```bash
./setup.sh
```

Choose from pre-built bundles based on your workflow:

| Bundle | Servers included |
|--------|-----------------|
| **Quick Start** | GitHub, Fetch, Filesystem, Memory |
| **Full Stack Developer** | Core + Brave Search, Context7, Sequential Thinking, Puppeteer |
| **Data and Backend** | Core + Postgres, SQLite, Sequential Thinking |
| **AI/ML Engineer** | Core + Brave Search, Context7, Sequential Thinking, EverArt |
| **Everything** | All 13 available servers |
| **Custom** | Pick exactly which servers you want |

### Non-interactive modes

```bash
./setup.sh --all        # Install everything
./setup.sh --minimal    # Just GitHub, Fetch, Filesystem
./setup.sh --list       # Show available servers and exit
./setup.sh --restore    # Roll back to the most recent backup
```

### What the setup does

1. **Preflight checks** - Verifies Claude Code, npx, and jq/python are available
2. **Environment detection** - Finds installed languages, tools, and databases
3. **Existing config detection** - Identifies servers you already have configured
4. **Interactive selection** - Recommends servers based on your workflow
5. **Path and connection prompts** - Asks for filesystem paths, database connections, and API keys
6. **Backup** - Creates a timestamped backup of your current settings
7. **Installation** - Writes server configs to `~/.claude/settings.json`
8. **Validation** - Verifies each package exists in the npm registry
9. **Rollback on failure** - Restores your backup if anything goes wrong

## What Is MCP?

[MCP (Model Context Protocol)](https://modelcontextprotocol.io/) is an open standard for connecting AI tools to external data sources. Each MCP server gives Claude Code a specific capability: GitHub access, web search, database queries, persistent memory, and more.

## Prerequisites

| Requirement | Why | How to install |
|------------|-----|---------------|
| [Claude Code](https://docs.anthropic.com/en/docs/claude-code) | The AI assistant these servers plug into | `npm install -g @anthropic-ai/claude-code` |
| Node.js v18+ | MCP servers run via npx | `brew install node` / `dnf install nodejs` / `apt install nodejs npm` |
| jq or python3 | JSON processing during setup | `brew install jq` / `dnf install jq` / `apt install jq` |

Optional:
- `GITHUB_PERSONAL_ACCESS_TOKEN` for private repo access and higher rate limits
- `BRAVE_API_KEY` for web search (free tier available)
- Database access for Postgres/SQLite servers

## Configuration Reference

### Where settings live

MCP servers are configured in `~/.claude/settings.json` under the `mcpServers` key. You can also use project-level settings at `.claude/settings.json` in any repo root (these merge with your user settings).

### Server config format

Every MCP server entry follows this structure:

```json
{
  "mcpServers": {
    "server-name": {
      "command": "npx",
      "args": ["-y", "@scope/package-name", "optional-arg"],
      "env": {
        "API_KEY": "your-key-here"
      }
    }
  }
}
```

### Adding API keys

Servers that need API keys (Brave Search, Slack, Google Maps, EverArt) look for them in the `env` block. You can also export them as environment variables before starting Claude Code:

```bash
export BRAVE_API_KEY="your-key"
export GITHUB_PERSONAL_ACCESS_TOKEN="ghp_your_token"
```

Or add them directly to your settings:

```json
"brave-search": {
  "command": "npx",
  "args": ["-y", "@anthropic-ai/mcp-server-brave-search"],
  "env": {
    "BRAVE_API_KEY": "your-api-key-here"
  }
}
```

### API key sources

| Server | Variable | Where to get it |
|--------|----------|----------------|
| GitHub | `GITHUB_PERSONAL_ACCESS_TOKEN` | https://github.com/settings/tokens |
| Brave Search | `BRAVE_API_KEY` | https://brave.com/search/api/ |
| Slack | `SLACK_BOT_TOKEN`, `SLACK_TEAM_ID` | https://api.slack.com/apps |
| Google Maps | `GOOGLE_MAPS_API_KEY` | https://console.cloud.google.com/ |
| EverArt | `EVERART_API_KEY` | EverArt dashboard |

### Example configs

The `configs/` directory contains standalone JSON snippets for each server. Use these as reference if you want to manually add servers or configure them in project-level settings.

## Uninstall

```bash
./uninstall.sh            # Remove all kit-managed servers
./uninstall.sh --select   # Choose which servers to remove
```

A backup is always created before removal. To restore:

```bash
./setup.sh --restore
```

## Troubleshooting

See [troubleshooting.md](troubleshooting.md) for the 20 most common MCP setup problems and their solutions.

Quick fixes for the most frequent issues:

### Claude says "tool not available"

Restart Claude Code after running setup.sh. MCP servers are loaded at startup, not hot-reloaded.

### MCP server fails to start

```bash
# Check that npx can reach the package
npx -y @modelcontextprotocol/server-github --help

# Run the full health check
./verify.sh
```

### API key not working

Make sure your key is in the `env` block of the server config in `~/.claude/settings.json`, not just exported in your shell. Claude Code spawns MCP servers as child processes and only passes `env` block variables.

### npx not found

Install Node.js v18+:
- macOS: `brew install node`
- Fedora/RHEL: `dnf install nodejs`
- Ubuntu: `apt install nodejs npm`

### Behind a corporate proxy

If `npm view @modelcontextprotocol/server-github version` times out, configure npm to use your proxy:

```bash
npm config set proxy http://proxy.example.com:8080
npm config set https-proxy http://proxy.example.com:8080
```

For TLS inspection (corporate CA), set `NODE_EXTRA_CA_CERTS` in each server's `env` block in `~/.claude/settings.json`. See [troubleshooting.md](troubleshooting.md) for details.

### GitHub rate limiting

You are hitting the unauthenticated rate limit (60 requests/hour). Set `GITHUB_PERSONAL_ACCESS_TOKEN` to raise it to 5,000 requests/hour. See [API key sources](#api-key-sources) above.

## Advanced Usage

See [advanced-patterns.md](advanced-patterns.md) for power-user configurations:

- Project-level vs user-level configuration
- Workspace-specific server bundles
- Environment variable management and secret handling
- Multi-database setups
- Composing servers for specific workflows
- Performance tuning
- Team-shared configurations

## Contributing

Open a PR to add server configs to `configs/` or improve the setup scripts.

## License

Apache-2.0
