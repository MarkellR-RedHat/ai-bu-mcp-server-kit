# MCP Server Kit for Claude Code

Claude Code is powerful on its own. With MCP servers, it can search your GitHub repos, fetch web pages, read your local files, and query your databases. Setup takes 3 minutes.

## What You Unlock

| Without MCP servers | With MCP servers |
|---|---|
| Edit local files and run terminal commands | Everything on the left, plus... |
| Ask questions from Claude's training data | Search the live web and pull current documentation |
| Manually paste in file contents or URLs | Fetch any URL, API response, or web page directly |
| Copy-paste GitHub issues into your prompt | Query repos, PRs, issues, and commit history in conversation |
| No database access | Query PostgreSQL and SQLite databases directly |
| Context resets every session | Persistent memory across sessions |

## Quick Start

```bash
git clone https://github.com/MarkellR-RedHat/ai-bu-mcp-server-kit.git
cd ai-bu-mcp-server-kit
chmod +x setup.sh verify.sh uninstall.sh
./setup.sh
```

The setup wizard handles everything. It checks your system, recommends the right servers for your workflow, and verifies each one works.

Want to skip the wizard? Install everything in one shot:

```bash
./setup.sh --all
```

Or install just the essentials:

```bash
./setup.sh --minimal
```

## Try It Out

After setup, restart Claude Code and try these prompts:

**GitHub:**
```
List the open issues in MarkellR-RedHat/ai-bu-mcp-server-kit
```

**Fetch:**
```
Fetch https://httpbin.org/get and show me the response headers
```

**Filesystem:**
```
List the files in my projects directory and summarize what each project does
```

**Memory:**
```
Remember that my preferred programming language is Python and I work on RHEL
```

**Brave Search:**
```
Search the web for "latest Claude Code features" and summarize what you find
```

**Sequential Thinking:**
```
Use sequential thinking to design a migration strategy for moving from monolith to microservices
```

**Context7:**
```
Use context7 to get the latest docs for FastAPI and show me how to add middleware
```

**PostgreSQL:**
```
Connect to my database and show me the schema for the users table
```

If Claude Code responds with actual data instead of an error, your MCP servers are working.

## What is MCP?

MCP servers are plugins that give Claude Code new abilities. Without them, Claude works with your local files and terminal. With them, it can search the web, query databases, interact with GitHub, and remember things across sessions. [MCP (Model Context Protocol)](https://modelcontextprotocol.io/) is the open standard that makes this possible.

## Available Servers

### Start with these three

These are the servers that 90% of users want. The `--minimal` flag installs exactly these.

| Server | Package | What It Does |
|--------|---------|-------------|
| **GitHub** | `@modelcontextprotocol/server-github` | Query repos, issues, PRs, file contents, and commit history |
| **Fetch** | `@anthropic-ai/mcp-fetch` | Read the contents of any URL: docs, APIs, web pages, raw data |
| **Filesystem** | `@modelcontextprotocol/server-filesystem` | Controlled read/write/search access to local directories |

### Add more when you need them

<details>
<summary><strong>Search and Research</strong></summary>

| Server | Package | What It Does |
|--------|---------|-------------|
| **Brave Search** | `@anthropic-ai/mcp-server-brave-search` | Web search via Brave Search API (requires API key) |
| **Context7** | `@upstash/context7-mcp` | Up-to-date library documentation pulled from source |

</details>

<details>
<summary><strong>Memory and Reasoning</strong></summary>

| Server | Package | What It Does |
|--------|---------|-------------|
| **Memory** | `@modelcontextprotocol/server-memory` | Persistent key-value storage across Claude Code sessions |
| **Sequential Thinking** | `@modelcontextprotocol/server-sequential-thinking` | Structured step-by-step reasoning for complex problems |

</details>

<details>
<summary><strong>Database</strong></summary>

| Server | Package | What It Does |
|--------|---------|-------------|
| **PostgreSQL** | `@modelcontextprotocol/server-postgres` | Query and inspect PostgreSQL databases |
| **SQLite** | `@modelcontextprotocol/server-sqlite` | Query and inspect SQLite database files |

</details>

<details>
<summary><strong>Browser and Automation</strong></summary>

| Server | Package | What It Does |
|--------|---------|-------------|
| **Puppeteer** | `@modelcontextprotocol/server-puppeteer` | Browser automation: screenshots, clicks, form fills, navigation |

</details>

<details>
<summary><strong>Communication</strong></summary>

| Server | Package | What It Does |
|--------|---------|-------------|
| **Slack** | `@modelcontextprotocol/server-slack` | Read and post messages in Slack channels (requires bot token) |

</details>

<details>
<summary><strong>Location</strong></summary>

| Server | Package | What It Does |
|--------|---------|-------------|
| **Google Maps** | `@modelcontextprotocol/server-google-maps` | Geocoding, directions, and place search (requires API key) |

</details>

<details>
<summary><strong>Creative</strong></summary>

| Server | Package | What It Does |
|--------|---------|-------------|
| **EverArt** | `@modelcontextprotocol/server-everart` | AI image generation and model training (requires API key) |

</details>

## Setup Options

### Interactive mode (default)

```bash
./setup.sh
```

Choose from pre-built bundles based on your workflow:

- **Quick Start** - GitHub, Fetch, Filesystem, Memory
- **Full Stack Developer** - Core + Brave Search, Context7, Sequential Thinking, Puppeteer
- **Data and Backend** - Core + Postgres, SQLite, Sequential Thinking
- **AI/ML Engineer** - Core + Brave Search, Context7, Sequential Thinking, EverArt
- **Everything** - All available servers
- **Custom** - Pick exactly which servers you want

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
4. **Interactive selection** - Recommends servers based on your workflow, with suggestions based on detected tools
5. **Path and connection prompts** - Asks for filesystem paths, database connection strings, and API keys
6. **Backup** - Creates a timestamped backup of your current settings
7. **Installation** - Writes server configs to `~/.claude/settings.json`
8. **Validation** - Verifies each package exists in the npm registry
9. **Rollback on failure** - Restores your backup if anything goes wrong

## Verify Your Setup

After running setup, confirm everything is healthy:

```bash
./verify.sh
```

The health dashboard will:
- Test each configured MCP server
- Show connection status with color indicators
- Check API keys for placeholder values
- Validate file paths exist and are readable
- Diagnose common problems and suggest fixes
- Report an overall health score

Additional options:

```bash
./verify.sh --quick    # Registry checks only (faster)
./verify.sh --json     # Machine-readable output
```

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

### Changing the Filesystem path

By default, the filesystem server points to `~/projects`. To change it:

```json
"filesystem": {
  "command": "npx",
  "args": ["-y", "@modelcontextprotocol/server-filesystem", "/your/preferred/path"]
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

| Server | Variable | Where to Get It |
|--------|----------|----------------|
| GitHub | `GITHUB_PERSONAL_ACCESS_TOKEN` | https://github.com/settings/tokens |
| Brave Search | `BRAVE_API_KEY` | https://brave.com/search/api/ |
| Slack | `SLACK_BOT_TOKEN`, `SLACK_TEAM_ID` | https://api.slack.com/apps |
| Google Maps | `GOOGLE_MAPS_API_KEY` | https://console.cloud.google.com/ |
| EverArt | `EVERART_API_KEY` | EverArt dashboard |

### Example configs

The `configs/` directory contains standalone JSON snippets for each server. Use these as reference if you want to manually add servers or configure them in project-level settings:

```
configs/
  github-mcp.json
  fetch-mcp.json
  filesystem-mcp.json
  brave-search-mcp.json
  memory-mcp.json
  context7-mcp.json
  sequential-thinking-mcp.json
  postgres-mcp.json
  sqlite-mcp.json
  puppeteer-mcp.json
  slack-mcp.json
  google-maps-mcp.json
  everart-mcp.json
```

## Uninstall

Remove MCP server entries added by this kit:

```bash
./uninstall.sh            # Remove all kit-managed servers
./uninstall.sh --select   # Choose which servers to remove
```

A backup is always created before removal. To restore:

```bash
./setup.sh --restore
```

## Troubleshooting

See [troubleshooting.md](troubleshooting.md) for the 20 most common MCP setup problems and their solutions, organized by symptom.

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

### GitHub rate limiting

You are hitting the unauthenticated rate limit (60 requests/hour). Set `GITHUB_PERSONAL_ACCESS_TOKEN` to raise it to 5,000 requests/hour. See [API key sources](#api-key-sources) above.

## Prerequisites

Most people already have what they need. Here is a quick check:

| Requirement | Why | How to Install |
|------------|-----|---------------|
| [Claude Code](https://docs.anthropic.com/en/docs/claude-code) | The AI assistant these servers plug into | `npm install -g @anthropic-ai/claude-code` |
| Node.js v18+ | MCP servers run via npx | `brew install node` / `dnf install nodejs` / `apt install nodejs npm` |
| jq or python3 | JSON processing during setup | `brew install jq` / `dnf install jq` / `apt install jq` |

Optional:
- `GITHUB_PERSONAL_ACCESS_TOKEN` for private repo access and higher rate limits
- `BRAVE_API_KEY` for web search (free tier available)
- Database access for Postgres/SQLite servers

## Advanced Usage

See [advanced-patterns.md](advanced-patterns.md) for power-user configurations:

- Project-level vs user-level configuration
- Workspace-specific server bundles
- Environment variable management and secret handling
- Multi-database setups
- Composing servers for specific workflows
- Performance tuning
- Team-shared configurations
- Custom server arguments
- Debugging MCP connections

## Contributing

Contributions are welcome. If you have a useful MCP server configuration, open a PR adding it to the `configs/` directory and updating setup.sh.

## License

Apache-2.0
