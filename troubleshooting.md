# MCP Server Kit: Troubleshooting

Something not working? Find the symptom that matches what you see, then follow the fix.

This guide covers MCP servers installed via `npx` from npm packages and configured in `~/.claude/settings.json` under the `mcpServers` key.

---

## Quick Diagnostic Checklist

Run through this in 60 seconds before diving into specific problems.

```bash
# 1. Is Claude Code installed and current?
claude --version

# 2. Is Node.js v18+ and npx available?
node --version
npx --version

# 3. Is the settings file valid JSON?
jq . ~/.claude/settings.json

# 4. What servers are configured?
jq '.mcpServers | keys' ~/.claude/settings.json

# 5. Can npx resolve a server package?
npx -y @modelcontextprotocol/server-github --help 2>&1 | head -5

# 6. Are required environment variables set?
env | grep -E 'GITHUB_PERSONAL_ACCESS_TOKEN|BRAVE_API_KEY|GOOGLE_MAPS_API_KEY|SLACK_BOT_TOKEN'

# 7. Can you reach npm and external APIs?
curl -sI https://registry.npmjs.org/ | head -3

# 8. Run the kit's built-in verification:
./verify.sh

# 9. Check MCP status (run inside Claude Code):
# /mcp

# 10. Check overall health (run inside Claude Code):
# claude doctor
```

If all ten pass and the problem persists, run `/feedback` inside Claude Code to report it.

---

## Claude Code says tools are not available

### "No MCP tools available" or tools don't appear

**What you see:** You ask Claude to use a tool (like "search the web" or "list GitHub issues") and it says no such tool exists or MCP servers are not configured.

**Why it happens:** The `mcpServers` block is missing from your settings file, the JSON is broken, or a server name has a typo.

**Fix it:**

```bash
# 1. Check if the settings file exists and is valid JSON:
jq . ~/.claude/settings.json

# 2. If jq reports a parse error, restore from backup:
ls ~/.claude/settings.json.backup.*
cp ~/.claude/settings.json.backup.<latest> ~/.claude/settings.json

# 3. Or re-run setup to regenerate it:
./setup.sh
```

Make sure `mcpServers` is a top-level key (not nested inside something else). Then restart Claude Code: exit and relaunch `claude`.

---

### Claude uses the wrong tool or picks the wrong server

**What you see:** You ask Claude to do something and it uses a tool from the wrong server, or behaves unexpectedly when two servers can do similar things (for example, both `fetch` and `puppeteer` can retrieve web pages).

**Why it happens:** Multiple servers with overlapping capabilities confuse tool selection.

**Fix it:**

```bash
# Disable the server you don't need right now (run inside Claude Code):
# /mcp disable puppeteer
```

If the conflict keeps happening, rename the server key in `~/.claude/settings.json` to make its purpose clearer. Claude uses the server name as context when picking tools.

---

### "Prompt is too long" or response quality drops

**What you see:** Claude reports the prompt is too long, or responses get noticeably worse. Running `/context` shows MCP tool definitions eating a big chunk of the context window.

**Why it happens:** Every enabled MCP server registers its tool definitions in Claude's context window. With 10+ servers, this can consume thousands of tokens before you even send a message.

**Fix it:**

```bash
# Disable servers you're not actively using (run inside Claude Code):
# /mcp disable postgres
# /mcp disable sqlite
# /mcp disable puppeteer
# /mcp disable google-maps
# /mcp disable slack

# Re-enable when needed:
# /mcp enable postgres

# Check the token breakdown:
# /context
```

> **Still not working?** Run `./verify.sh` or type `/feedback` inside Claude Code.

---

## An MCP server won't start

### "spawn npx ENOENT" error

**What you see:** A server shows "Failed to connect." Logs say `spawn npx ENOENT`.

**Why it happens:** The process launching MCP servers can't find `npx` on its PATH (the most common MCP issue).

**Fix it:**

```bash
# 1. Find where npx actually lives:
which -a npx

# 2. In ~/.claude/settings.json, replace "npx" with the full path.
#    For example, if which returned /opt/homebrew/bin/npx, change:
#      "command": "npx"
#    to:
#      "command": "/opt/homebrew/bin/npx"
```

If you use nvm, the path will look like `/Users/<you>/.nvm/versions/node/v22.x.x/bin/npx`. Pin it to your current active version.

---

### Server starts but immediately disconnects (no error)

**What you see:** `claude mcp list` shows "disconnected" for a server. Running the command manually produces no error and no output, then exits.

**Why it happens:** The npm package hasn't been downloaded yet and `npx -y` is failing silently, or the package name has a typo.

**Fix it:**

```bash
# 1. Run the exact command from your settings manually:
npx -y @modelcontextprotocol/server-github

# 2. If it hangs or fails, verify the package exists:
npm view @modelcontextprotocol/server-github version

# 3. Clear the npx cache and retry:
npx clear-npx-cache
npx -y @modelcontextprotocol/server-github
```

---

### Settings file has invalid JSON

**What you see:** Claude Code fails to start or ignores all MCP settings. Running `jq . ~/.claude/settings.json` shows a parse error.

**Why it happens:** A previous setup run was interrupted, or a manual edit introduced a syntax error (trailing comma, missing quote, etc.).

**Fix it:**

```bash
# 1. Validate the current file:
jq . ~/.claude/settings.json

# 2. If broken, restore from backup:
ls -la ~/.claude/settings.json.backup.*
# Pick the most recent valid one:
cp ~/.claude/settings.json.backup.20260625143000 ~/.claude/settings.json

# 3. Validate the restored file:
jq . ~/.claude/settings.json
```

If no backup exists, rebuild from scratch:

```bash
echo '{}' > ~/.claude/settings.json
./setup.sh
```

---

### Servers work in my terminal but fail in Claude Desktop

**What you see:** Running `npx -y @modelcontextprotocol/server-github` works fine in your terminal, but the same server shows "Failed" in Claude Desktop.

**Why it happens:** Claude Desktop inherits the system PATH, not your shell's PATH. Tools installed via nvm, Homebrew, or custom paths are invisible to it.

**Fix it:**

```bash
# 1. Find the absolute path to npx:
which -a npx

# 2. Use that absolute path as "command" in your config.
#    See the "spawn npx ENOENT" section above for the exact edit.
```

Environment variables set in `.bashrc` or `.zshrc` are also invisible to Claude Desktop. Any required variables (API keys, tokens) must go in the server's `env` block in `~/.claude/settings.json`:

```json
"github": {
  "command": "/opt/homebrew/bin/npx",
  "args": ["-y", "@modelcontextprotocol/server-github"],
  "env": {
    "GITHUB_PERSONAL_ACCESS_TOKEN": "ghp_your_token_here"
  }
}
```

> **Still not working?** Run `./verify.sh` or type `/feedback` inside Claude Code.

---

## A server starts but gives errors when I use it

### GitHub server: "401 Unauthorized" or "Bad credentials"

**What you see:** The GitHub MCP server starts, but tool calls fail with `401 Unauthorized` or `Bad credentials`.

**Why it happens:** `GITHUB_PERSONAL_ACCESS_TOKEN` is not set, has expired, or lacks required scopes.

**Fix it:**

```bash
# 1. Check if the token is set in your current shell:
echo $GITHUB_PERSONAL_ACCESS_TOKEN

# 2. If empty, generate a token at https://github.com/settings/tokens
#    Required scopes: repo, read:org (minimum)
export GITHUB_PERSONAL_ACCESS_TOKEN="ghp_your_token_here"
```

To make the token available to MCP servers launched by Claude Code, add it to the server's `env` block in `~/.claude/settings.json`:

```json
"github": {
  "command": "npx",
  "args": ["-y", "@modelcontextprotocol/server-github"],
  "env": {
    "GITHUB_PERSONAL_ACCESS_TOKEN": "ghp_your_token_here"
  }
}
```

Or export it in your shell profile (`~/.zshrc` or `~/.bashrc`) so all child processes inherit it.

---

### Brave Search: "API key not found" or 401

**What you see:** Brave Search MCP server starts but every search call fails with an authentication error.

**Why it happens:** `BRAVE_API_KEY` is not set or is invalid.

**Fix it:**

Get an API key at https://brave.com/search/api/ and add it to the server config in `~/.claude/settings.json`:

```json
"brave-search": {
  "command": "npx",
  "args": ["-y", "@anthropic-ai/mcp-server-brave-search"],
  "env": {
    "BRAVE_API_KEY": "BSA_your_key_here"
  }
}
```

---

### Slack server: "invalid_auth" or "not_authed"

**What you see:** The Slack MCP server starts but all API calls fail with authentication errors.

**Why it happens:** `SLACK_BOT_TOKEN` or `SLACK_TEAM_ID` is missing or incorrect.

**Fix it:**

Update `~/.claude/settings.json`:

```json
"slack": {
  "command": "npx",
  "args": ["-y", "@modelcontextprotocol/server-slack"],
  "env": {
    "SLACK_BOT_TOKEN": "xoxb-your-token",
    "SLACK_TEAM_ID": "T01XXXXXX"
  }
}
```

The bot token must have the required OAuth scopes (channels:read, chat:write, etc.). Check your app config at https://api.slack.com/apps.

---

### Filesystem server: "Access denied" or refuses to read files

**What you see:** The filesystem MCP server starts but refuses to read or list directories, returning permission errors.

**Why it happens:** The server is sandboxed to only the directories listed in its `args`. Paths outside those directories are blocked by design.

**Fix it:**

Check the args in `~/.claude/settings.json`. The filesystem server only allows access to directories explicitly listed after the package name:

```json
"filesystem": {
  "command": "npx",
  "args": ["-y", "@modelcontextprotocol/server-filesystem", "/Users/you/projects"]
}
```

To add more directories, append them as additional args:

```json
"args": ["-y", "@modelcontextprotocol/server-filesystem", "/Users/you/projects", "/Users/you/documents"]
```

Always use absolute paths. Relative paths resolve unpredictably because the MCP server's working directory may be `/` on macOS.

---

### Database server: can't connect to Postgres or SQLite

**What you see:** Server starts but queries fail with "connection refused," "file not found," or authentication errors.

**Why it happens:** The connection string or database path in `args` is wrong, the database isn't running, or the user lacks permissions.

**Fix it (Postgres):**

```bash
# 1. Test the connection directly:
psql "postgresql://user:pass@localhost:5432/mydb"
```

Then use that same connection string in `~/.claude/settings.json`:

```json
"postgres": {
  "command": "npx",
  "args": ["-y", "@modelcontextprotocol/server-postgres", "postgresql://user:pass@localhost:5432/mydb"]
}
```

**Fix it (SQLite):**

The database file path must be absolute and the file must exist:

```json
"sqlite": {
  "command": "npx",
  "args": ["-y", "@modelcontextprotocol/server-sqlite", "/absolute/path/to/database.db"]
}
```

---

### Puppeteer: "ETIMEOUT" or can't launch browser

**What you see:** The Puppeteer server fails to launch a browser, returning timeout or connection refused errors.

**Why it happens:** Chromium is not installed, or the system lacks required libraries for headless browser operation (common on Linux servers and containers).

**Fix it:**

```bash
# On macOS, Chromium should install automatically via Puppeteer.

# On Linux (Fedora/RHEL):
dnf install -y chromium

# Or install Puppeteer's bundled Chromium:
npx puppeteer browsers install chrome
```

---

### Google Maps server: "ECONNREFUSED" or API errors

**What you see:** The Google Maps server can't reach the API, or calls fail with permission errors.

**Why it happens:** `GOOGLE_MAPS_API_KEY` is not set, or the key doesn't have the required APIs enabled.

**Fix it:**

Update `~/.claude/settings.json`:

```json
"google-maps": {
  "command": "npx",
  "args": ["-y", "@modelcontextprotocol/server-google-maps"],
  "env": {
    "GOOGLE_MAPS_API_KEY": "AIza..."
  }
}
```

Make sure the key has **Places API** and **Geocoding API** enabled at https://console.cloud.google.com/apis/library.

> **Still not working?** Run `./verify.sh` or type `/feedback` inside Claude Code.

---

## Everything is slow

### Servers take 15-30+ seconds to start

**What you see:** Claude Code takes a long time to become responsive. Each MCP server adds 10-30 seconds to startup.

**Why it happens:** `npx -y` downloads and installs the package on every launch if it isn't cached. Multiple servers compound the delay.

**Fix it:**

```bash
# Pre-install the packages you use so npx finds them instantly:
npm install -g @modelcontextprotocol/server-github
npm install -g @anthropic-ai/mcp-fetch
npm install -g @modelcontextprotocol/server-filesystem
npm install -g @modelcontextprotocol/server-memory
```

Also disable servers you don't need right now (run inside Claude Code):

```
/mcp disable brave-search
/mcp disable puppeteer
```

This also frees context window space, since tool definitions from every enabled server consume tokens even when you never call them.

> **Still not working?** Run `./verify.sh` or type `/feedback` inside Claude Code.

---

## Things broke after an update

### "Cannot find module" after upgrading Node.js

**What you see:** Servers that previously worked now fail with `Cannot find module` or `ERR_MODULE_NOT_FOUND`.

**Why it happens:** Upgrading Node.js (especially via nvm) changes the path to `npx` and invalidates the global package cache for the old version.

**Fix it:**

```bash
# 1. Clear the npx cache:
npx clear-npx-cache

# 2. If using absolute paths in settings.json, update them to the new Node version:
which npx
# Update the "command" field in ~/.claude/settings.json to match

# 3. Reinstall global packages for the new Node version:
npm install -g @modelcontextprotocol/server-github
# Repeat for other servers you use
```

---

### Servers fail after macOS update or Xcode Command Line Tools update

**What you see:** Servers that worked yesterday fail after a macOS update. Errors mention missing libraries or invalid binaries.

**Why it happens:** macOS updates can reset developer tool paths or invalidate compiled native modules in the npm cache.

**Fix it:**

```bash
# 1. Reinstall Xcode Command Line Tools if prompted:
xcode-select --install

# 2. Clear all npm and npx caches:
npm cache clean --force
npx clear-npx-cache

# 3. If using Homebrew-installed Node, relink:
brew reinstall node
```

---

### Linux: "GLIBC not found" or shared library errors

**What you see:** An MCP server (especially Puppeteer) crashes with shared library errors on Linux.

**Why it happens:** The npm package includes prebuilt native binaries that require a minimum glibc version. Older RHEL/CentOS systems may not meet this requirement. Container images based on Alpine (musl libc) are also affected.

**Fix it:**

```bash
# 1. Check your glibc version:
ldd --version

# 2. On RHEL/Fedora, update system libraries:
dnf update -y

# 3. For Puppeteer specifically, install browser dependencies:
dnf install -y \
  alsa-lib atk at-spi2-atk cups-libs libdrm libXcomposite \
  libXdamage libXrandr mesa-libgbm pango

# 4. If on a container, use a base image with glibc (not Alpine):
# FROM registry.access.redhat.com/ubi9/nodejs-22
```

> **Still not working?** Run `./verify.sh` or type `/feedback` inside Claude Code.

---

## Network and proxy issues

### npm/npx behind corporate proxy: ECONNREFUSED

**What you see:** All npx-based servers fail on startup. Running `npx -y <package>` manually also fails with network errors.

**Why it happens:** npm and npx need proxy configuration to reach the npm registry from behind a corporate firewall.

**Fix it:**

```bash
# 1. Configure npm to use your proxy:
npm config set proxy http://proxy.corp.example.com:8080
npm config set https-proxy http://proxy.corp.example.com:8080

# 2. If using a private registry:
npm config set registry https://registry.corp.example.com/

# 3. Verify it works:
npm view @modelcontextprotocol/server-github version
```

---

### context7 server: "fetch failed" or hangs

**What you see:** The `@upstash/context7-mcp` server starts but queries time out or return network errors.

**Why it happens:** The server needs outbound HTTPS access to Upstash's API, and corporate proxies, VPNs, or firewall rules can block it.

**Fix it:**

```bash
# 1. Test connectivity:
curl -I https://context7.com
```

If behind a proxy, set the proxy env var in `~/.claude/settings.json`:

```json
"context7": {
  "command": "npx",
  "args": ["-y", "@upstash/context7-mcp"],
  "env": {
    "HTTPS_PROXY": "http://proxy.corp.example.com:8080"
  }
}
```

If using a corporate proxy with TLS inspection, you also need to set `NODE_EXTRA_CA_CERTS`:

```json
"env": {
  "HTTPS_PROXY": "http://proxy.corp.example.com:8080",
  "NODE_EXTRA_CA_CERTS": "/etc/pki/tls/certs/ca-bundle.crt"
}
```

---

### "SSL certificate verification failed" for any server

**What you see:** One or more servers fail with SSL/TLS certificate errors during startup or API calls.

**Why it happens:** A corporate proxy or security appliance is intercepting TLS traffic and presenting its own certificate. Node.js doesn't trust it by default.

**Fix it:**

Add your organization's CA certificate bundle to the server's environment in `~/.claude/settings.json`:

```json
"env": {
  "NODE_EXTRA_CA_CERTS": "/path/to/ca-bundle.pem"
}
```

Common locations for the CA bundle:

```bash
# RHEL/Fedora:
ls /etc/pki/tls/certs/ca-bundle.crt

# Ubuntu/Debian:
ls /etc/ssl/certs/ca-certificates.crt

# macOS (export from Keychain):
security find-certificate -a -p /System/Library/Keychains/SystemRootCertificates.keychain > ~/ca-bundle.pem
```

Do **not** set `NODE_TLS_REJECT_UNAUTHORIZED=0`. That disables all certificate validation and is a security risk.

> **Still not working?** Run `./verify.sh` or type `/feedback` inside Claude Code.
