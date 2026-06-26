# Advanced MCP Patterns for Claude Code

Power-user configurations for getting the most out of the MCP servers in this kit. This guide assumes you have already run `setup.sh` and have a working MCP setup. If you haven't, start with the [README](README.md).

---

## 1. Project-Level vs User-Level Configuration

Claude Code reads MCP server configs from two locations:

- **User-level**: `~/.claude/settings.json` - applies to every project you open
- **Project-level**: `.claude/settings.json` at your repo root - applies only to that project

User-level is where your personal API keys and general-purpose servers live. Project-level is where team-shared, project-specific servers go.

### When to use which

| Use case | Where to configure |
|----------|--------------------|
| GitHub, Fetch, Memory (you always want these) | User-level |
| Postgres pointing at a project's database | Project-level |
| Filesystem scoped to a project's data directory | Project-level |
| Brave Search with your personal API key | User-level |
| Puppeteer for a frontend project only | Project-level |

### How they merge

When both files define MCP servers, Claude Code merges them. Project-level entries override user-level entries with the same key name. If your user-level config has a `postgres` server and your project-level config also defines `postgres`, the project-level one wins.

### Example: User-level baseline

`~/.claude/settings.json`:

```json
{
  "mcpServers": {
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "ghp_xxxxxxxxxxxxxxxxxxxx"
      }
    },
    "fetch": {
      "command": "npx",
      "args": ["-y", "@anthropic-ai/mcp-fetch"]
    },
    "memory": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-memory"]
    }
  }
}
```

### Example: Project-level addition

`your-repo/.claude/settings.json`:

```json
{
  "mcpServers": {
    "postgres": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-postgres", "postgresql://dev:dev@localhost:5432/myapp_dev"]
    }
  }
}
```

This way the whole team shares the same database config, and each engineer brings their own GitHub token from their user-level settings.

---

## 2. Workspace-Specific Configs

Different projects need different tools. Here are three practical setups, each designed as a project-level `.claude/settings.json`.

### Web frontend project

Puppeteer for testing rendered pages, Fetch for pulling API docs:

```json
{
  "mcpServers": {
    "puppeteer": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-puppeteer"]
    },
    "fetch": {
      "command": "npx",
      "args": ["-y", "@anthropic-ai/mcp-fetch"]
    }
  }
}
```

### Data engineering project

Direct access to your Postgres warehouse and a local SQLite staging database:

```json
{
  "mcpServers": {
    "postgres": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-postgres", "postgresql://analyst:password@localhost:5432/warehouse"]
    },
    "sqlite": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-sqlite", "./data/staging.db"]
    }
  }
}
```

### Infrastructure / platform project

Filesystem access to config directories, GitHub for PR review:

```json
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/etc/myapp", "/opt/myapp/config"]
    },
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "ghp_xxxxxxxxxxxxxxxxxxxx"
      }
    }
  }
}
```

---

## 3. Environment Variable Management

API keys are the most common source of MCP configuration mistakes. Here's how to handle them without leaking secrets.

### Option A: Shell profile (recommended for personal keys)

Set variables in your `~/.bashrc`, `~/.zshrc`, or `~/.bash_profile`:

```bash
export GITHUB_PERSONAL_ACCESS_TOKEN="ghp_xxxxxxxxxxxxxxxxxxxx"
export BRAVE_API_KEY="BSA_xxxxxxxxxxxxxxxxxxxx"
```

Then reference them in your settings without hardcoding:

```json
{
  "mcpServers": {
    "brave-search": {
      "command": "npx",
      "args": ["-y", "@anthropic-ai/mcp-server-brave-search"],
      "env": {
        "BRAVE_API_KEY": "${BRAVE_API_KEY}"
      }
    }
  }
}
```

Note: Claude Code does not perform `${VAR}` substitution in settings.json. If you set the variable in your shell profile, the MCP server process will inherit it from the environment automatically. You can simply omit the `env` block entirely, and the server will pick up the exported variable:

```json
{
  "mcpServers": {
    "brave-search": {
      "command": "npx",
      "args": ["-y", "@anthropic-ai/mcp-server-brave-search"]
    }
  }
}
```

### Option B: The env block in settings.json (quick but be careful)

For user-level settings that never get committed to version control, putting keys directly in the `env` block is fine:

```json
{
  "mcpServers": {
    "slack": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-slack"],
      "env": {
        "SLACK_BOT_TOKEN": "xoxb-xxxxxxxxxxxx",
        "SLACK_TEAM_ID": "T01XXXXXXXX"
      }
    }
  }
}
```

### What to never do

Never put API keys in a project-level `.claude/settings.json` that gets committed. If your project needs a server with an API key, define the server in project settings without the key and let each developer supply the key from their shell environment:

Project-level `.claude/settings.json` (committed):

```json
{
  "mcpServers": {
    "brave-search": {
      "command": "npx",
      "args": ["-y", "@anthropic-ai/mcp-server-brave-search"]
    }
  }
}
```

Each developer sets `BRAVE_API_KEY` in their shell profile. The server inherits it at startup.

### Safeguard: .gitignore

If you ever put secrets in user-level settings, make sure `~/.claude/settings.json` is never accidentally copied into a repo. For project-level settings, add a note in your onboarding docs that API keys come from the environment.

---

## 4. Multi-Database Setups

You can run multiple instances of the same server type by giving them different key names. This is common with Postgres and SQLite when you need to query multiple databases in the same session.

### Multiple Postgres databases

```json
{
  "mcpServers": {
    "postgres-app": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-postgres", "postgresql://dev:dev@localhost:5432/myapp"]
    },
    "postgres-analytics": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-postgres", "postgresql://dev:dev@localhost:5432/analytics"]
    },
    "postgres-staging": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-postgres", "postgresql://dev:dev@staging-host:5432/myapp"]
    }
  }
}
```

### Multiple SQLite databases

```json
{
  "mcpServers": {
    "sqlite-users": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-sqlite", "/data/users.db"]
    },
    "sqlite-logs": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-sqlite", "/data/event_logs.db"]
    }
  }
}
```

### Naming conventions

Use a consistent pattern: `{server-type}-{purpose}`. This makes it clear in Claude Code's tool list which database you're talking to. Some examples:

- `postgres-prod-readonly` - production, read-only connection
- `postgres-dev` - local development database
- `sqlite-cache` - application cache database
- `sqlite-test-fixtures` - test data

When you ask Claude Code to query something, reference the server by name: "Query the postgres-analytics database for last month's signups."

---

## 5. Composing Servers for Workflows

Individual MCP servers are useful. Combinations of them unlock real workflows. Here are four patterns you can drop into your settings.

### Research and Document

Brave Search to find sources, Fetch to pull full page content, Filesystem to write summaries to disk.

```json
{
  "mcpServers": {
    "brave-search": {
      "command": "npx",
      "args": ["-y", "@anthropic-ai/mcp-server-brave-search"]
    },
    "fetch": {
      "command": "npx",
      "args": ["-y", "@anthropic-ai/mcp-fetch"]
    },
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/home/user/research"]
    }
  }
}
```

Workflow: "Search for recent benchmarks on llm-d inference performance, fetch the top 3 results, and write a summary to /home/user/research/llm-d-benchmarks.md."

### Database Migration Review

Postgres for checking actual schema state, GitHub for reviewing migration PRs.

```json
{
  "mcpServers": {
    "postgres-dev": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-postgres", "postgresql://dev:dev@localhost:5432/myapp_dev"]
    },
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "ghp_xxxxxxxxxxxxxxxxxxxx"
      }
    }
  }
}
```

Workflow: "Pull the open migration PRs from our repo, then compare each migration's expected schema changes against the current tables in postgres-dev."

### Full-Stack Development

GitHub for code context, Filesystem for local access, Puppeteer for browser testing, Fetch for pulling API documentation.

```json
{
  "mcpServers": {
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "ghp_xxxxxxxxxxxxxxxxxxxx"
      }
    },
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/home/user/projects/myapp"]
    },
    "puppeteer": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-puppeteer"]
    },
    "fetch": {
      "command": "npx",
      "args": ["-y", "@anthropic-ai/mcp-fetch"]
    }
  }
}
```

Workflow: "Fetch the Stripe API docs for the checkout session endpoint, implement the integration, then use Puppeteer to verify the checkout page renders correctly at localhost:3000/checkout."

### AI/ML Development

Context7 for current library documentation, Sequential Thinking for structured problem breakdown, Filesystem for managing notebooks and data files.

```json
{
  "mcpServers": {
    "context7": {
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp"]
    },
    "sequential-thinking": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-sequential-thinking"]
    },
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/home/user/ml-projects"]
    }
  }
}
```

Workflow: "Use Context7 to get the latest PyTorch distributed training docs, then use Sequential Thinking to plan a migration from DataParallel to DistributedDataParallel, and write the implementation plan to the filesystem."

---

## 6. Performance Tuning

Every MCP server is a separate process. More servers means more startup time and more memory.

### Server weight categories

**Lightweight** (negligible overhead, always safe to keep):
- Sequential Thinking - no external connections, pure logic
- Memory - small local storage
- Filesystem - local file operations only

**Medium** (one external connection or moderate resources):
- Fetch - makes HTTP requests on demand, idle otherwise
- GitHub - single API connection
- SQLite - opens one database file
- Context7 - external API calls for documentation

**Heavier** (noticeable resource usage):
- Puppeteer - launches a headless Chromium browser
- Postgres - maintains a database connection
- Slack - WebSocket connection to Slack
- Google Maps - API calls with potential rate limiting

### Practical advice

1. **Don't load Puppeteer globally.** Put it in project-level settings for frontend projects only. A headless browser sitting idle still uses memory.

2. **Remove what you don't use.** If you set up all 13 servers with `setup.sh --all` but only use 4 of them, remove the rest. Each server adds a few seconds to Claude Code's startup.

3. **Use project-level configs for heavy servers.** Keep your user-level settings lean (GitHub, Fetch, Memory) and add heavy servers per-project.

4. **First-run overhead.** The first time `npx` runs a server after install or update, it downloads the package. Subsequent starts are faster. If startup feels slow, run the server manually once to prime the cache:
   ```bash
   npx -y @modelcontextprotocol/server-puppeteer --help
   ```

---

## 7. Team-Shared Configurations

A project-level `.claude/settings.json` committed to your repo means every team member gets the same MCP setup when they clone.

### Setting up a shared config

Create `.claude/settings.json` at the root of your repo:

```bash
mkdir -p .claude
```

```json
{
  "mcpServers": {
    "postgres-dev": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-postgres", "postgresql://dev:dev@localhost:5432/myapp_dev"]
    },
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "./data", "./config"]
    },
    "sequential-thinking": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-sequential-thinking"]
    }
  }
}
```

Commit it:

```bash
git add .claude/settings.json
git commit -m "Add shared MCP server config for Claude Code"
```

### What goes where

| In project settings (shared) | In user settings (personal) |
|------------------------------|-----------------------------|
| Database connections with dev credentials | API keys (GitHub, Brave, Slack) |
| Filesystem paths relative to the repo | Personal Memory server |
| Servers the team workflow depends on | Servers for your personal workflow |
| Sequential Thinking, Context7 | Google Maps, EverArt |

### Onboarding template

Add this to your project's onboarding docs or CONTRIBUTING.md:

```markdown
## Claude Code Setup

This repo includes MCP server configs at `.claude/settings.json`.
To get started:

1. Install Claude Code: `npm install -g @anthropic-ai/claude-code`
2. Make sure you have Node.js v18+ and npx available
3. Set up your personal API keys in your shell profile:
   ```bash
   export GITHUB_PERSONAL_ACCESS_TOKEN="ghp_your_token"
   export BRAVE_API_KEY="BSA_your_key"   # optional
   ```
4. Start the local dev database: `docker compose up -d`
5. Open Claude Code in the repo directory - MCP servers load automatically
```

### Handling different environments

If your team has different database hosts for different environments, use the dev defaults in the committed config. Engineers who need to point at a different database can override in their user-level settings:

User-level override in `~/.claude/settings.json`:

```json
{
  "mcpServers": {
    "postgres-dev": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-postgres", "postgresql://dev:dev@my-custom-host:5432/myapp_dev"]
    }
  }
}
```

This replaces the project-level `postgres-dev` for that user only.

---

## 8. Custom Server Arguments

Most MCP servers accept command-line arguments that control their behavior. These go in the `args` array after the `-y` flag and package name.

### Filesystem: Restricting accessible paths

The Filesystem server takes one or more directory paths as arguments. It will only allow access to those directories and their contents.

Single directory:

```json
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/home/user/projects"]
    }
  }
}
```

Multiple directories:

```json
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/home/user/projects", "/home/user/documents", "/tmp/scratch"]
    }
  }
}
```

Each path is a separate argument. The server grants read/write access to all listed paths and denies access to everything else.

### Postgres: Connection string options

The Postgres server takes a standard PostgreSQL connection URI. You can include all standard connection parameters:

```json
{
  "mcpServers": {
    "postgres": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-postgres", "postgresql://user:password@host:5432/dbname?sslmode=require&connect_timeout=10"]
    }
  }
}
```

Common connection string parameters:
- `sslmode=require` - force SSL connections (important for remote databases)
- `connect_timeout=10` - fail fast if the database is unreachable
- `application_name=claude-code` - identify the connection in `pg_stat_activity`

Full example with SSL and timeout:

```json
{
  "mcpServers": {
    "postgres-prod-readonly": {
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/server-postgres",
        "postgresql://readonly_user:password@prod-db.internal:5432/myapp?sslmode=require&connect_timeout=10&application_name=claude-code"
      ]
    }
  }
}
```

### SQLite: Database file path

SQLite takes a file path to the database. Use absolute paths to avoid ambiguity:

```json
{
  "mcpServers": {
    "sqlite": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-sqlite", "/absolute/path/to/database.db"]
    }
  }
}
```

If the file doesn't exist, the server creates it.

### Fetch: URL handling

The Fetch server doesn't take startup arguments, but it processes URLs passed to it during conversation. It handles HTTP-to-HTTPS upgrades automatically and follows redirects.

```json
{
  "mcpServers": {
    "fetch": {
      "command": "npx",
      "args": ["-y", "@anthropic-ai/mcp-fetch"]
    }
  }
}
```

### Environment variables as configuration

Some servers use environment variables instead of command-line arguments for configuration. When a server needs both args and env vars:

```json
{
  "mcpServers": {
    "google-maps": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-google-maps"],
      "env": {
        "GOOGLE_MAPS_API_KEY": "AIzaSy_xxxxxxxxxxxxxxxxxxxx"
      }
    }
  }
}
```

---

## 9. Debugging MCP Connections

When a server isn't working, here's how to figure out why.

### Step 1: Test the server manually

Run the server outside of Claude Code to see if it starts:

```bash
npx -y @modelcontextprotocol/server-github --help
```

If this fails, the problem is with the package install or Node.js, not Claude Code.

For servers that need environment variables:

```bash
BRAVE_API_KEY="your-key" npx -y @anthropic-ai/mcp-server-brave-search
```

The server should start and wait for input on stdin (MCP uses JSON-RPC over stdio). Press `Ctrl+C` to exit.

### Step 2: Check Claude Code's MCP status

Inside Claude Code, run:

```
/mcp
```

This shows the status of all configured MCP servers: which ones connected successfully and which ones failed.

### Step 3: Read the logs

Claude Code writes MCP server logs to:

```
~/.claude/logs/
```

Look for recent log files. Errors during server startup, connection failures, and malformed responses show up here.

```bash
ls -lt ~/.claude/logs/ | head -10
```

### Step 4: Common failure modes

**Server fails to start:**
- Check that `npx` is on your PATH
- Check that Node.js is v18 or later: `node --version`
- Try clearing the npx cache: `npx clear-npx-cache` or remove `~/.npm/_npx/`

**Server starts but tools don't appear:**
- The server name in settings.json might conflict with a built-in. Try renaming the key.
- Check for JSON syntax errors in your settings file: `python3 -m json.tool ~/.claude/settings.json`

**Server connects but queries fail:**
- For Postgres: verify the connection string works with `psql`: 
  ```bash
  psql "postgresql://user:password@localhost:5432/mydb"
  ```
- For GitHub: check that your token has the right scopes (need `repo` for private repos)
- For Brave Search: confirm your API key is active at https://brave.com/search/api/

**Server timeout on first run:**
- The first `npx` invocation downloads the package. On slow networks this can take long enough to time out. Run it manually first to prime the cache:
  ```bash
  npx -y @modelcontextprotocol/server-puppeteer --help
  ```

### Step 5: Validate your settings.json

A single misplaced comma or bracket breaks the entire file. Validate it:

```bash
python3 -m json.tool ~/.claude/settings.json > /dev/null && echo "Valid JSON" || echo "Invalid JSON"
```

Or with jq:

```bash
jq . ~/.claude/settings.json > /dev/null 2>&1 && echo "Valid JSON" || echo "Invalid JSON"
```

### Full debugging example

If the GitHub server isn't connecting:

```bash
# 1. Validate settings.json
python3 -m json.tool ~/.claude/settings.json > /dev/null

# 2. Test the server manually
GITHUB_PERSONAL_ACCESS_TOKEN="ghp_xxx" npx -y @modelcontextprotocol/server-github

# 3. If it starts, press Ctrl+C and check Claude Code
# Run /mcp inside Claude Code

# 4. If /mcp shows it failed, check logs
ls -lt ~/.claude/logs/ | head -5
cat ~/.claude/logs/<most-recent-log-file>
```

---

## What's Next

These patterns cover the most common power-user setups. For the base server configurations, see the `configs/` directory. For initial setup, see the [README](README.md).

If you find a useful pattern not covered here, open a PR.
