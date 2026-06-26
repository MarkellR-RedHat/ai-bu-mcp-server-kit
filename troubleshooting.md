# MCP Server Kit - Troubleshooting Guide

Common problems and fixes for the ai-bu-mcp-server-kit. Organized by symptom: find what you see, apply the fix.

This guide covers MCP servers installed via `npx` from npm packages and configured in `~/.claude/settings.json` under the `mcpServers` key.

---

## 1. Claude says "no MCP tools available" or tools don't appear

**Symptom:** You ask Claude Code to use an MCP tool (e.g., "search the web" or "list GitHub issues") and it responds that no such tool exists or that MCP servers are not configured.

**Cause:** The `mcpServers` block is missing from `~/.claude/settings.json`, the JSON is malformed, or the server entry has a typo in the key name.

**Fix:**

```bash
# Confirm the settings file exists and is valid JSON
cat ~/.claude/settings.json | jq .

# If jq reports a parse error, the JSON is broken.
# Restore from the backup created by setup.sh:
ls ~/.claude/settings.json.backup.*
cp ~/.claude/settings.json.backup.<latest> ~/.claude/settings.json

# Or re-run setup:
./setup.sh
```

Check that `mcpServers` is a top-level key (not nested inside something else). Claude Code also needs a restart after settings changes: exit the session and relaunch `claude`.

---

## 2. "spawn npx ENOENT" when a server tries to start

**Symptom:** Server shows "Failed to connect" status. Logs contain `spawn npx ENOENT`.

**Cause:** The process launching MCP servers cannot find `npx` on its PATH. This is the single most common MCP issue. GUI-launched apps (Claude Desktop) and some terminal configurations inherit a minimal PATH that does not include nvm, Homebrew, or other user-installed Node paths.

**Fix:**

```bash
# Find where npx actually lives
which -a npx

# Replace "npx" with the absolute path in ~/.claude/settings.json.
# Example: if npx is at /opt/homebrew/bin/npx
```

In `~/.claude/settings.json`, change:
```json
"command": "npx"
```
to:
```json
"command": "/opt/homebrew/bin/npx"
```

If you use nvm, the path will be something like `/Users/<you>/.nvm/versions/node/v22.x.x/bin/npx`. Pin it to your current active version.

---

## 3. Server starts but immediately exits with no output

**Symptom:** `claude mcp list` shows "disconnected" for a server. Running the command manually produces no error and no output, then exits.

**Cause:** The npm package was not downloaded yet, and `npx -y` is failing silently. Or the package name in settings has a typo.

**Fix:**

```bash
# Run the exact command from your settings manually:
npx -y @modelcontextprotocol/server-github

# If it hangs or fails, the package cannot be resolved.
# Verify the package exists:
npm view @modelcontextprotocol/server-github version

# Clear the npx cache and retry:
npx clear-npx-cache
npx -y @modelcontextprotocol/server-github
```

---

## 4. GitHub server returns 401 or "Bad credentials"

**Symptom:** The GitHub MCP server starts, but tool calls fail with `401 Unauthorized` or `Bad credentials`.

**Cause:** `GITHUB_PERSONAL_ACCESS_TOKEN` is not set, has expired, or lacks the required scopes.

**Fix:**

```bash
# Check if the token is set in your current shell:
echo $GITHUB_PERSONAL_ACCESS_TOKEN

# If empty, set it. Generate a token at https://github.com/settings/tokens
# Required scopes: repo, read:org (minimum)
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

Or export it in your shell profile (`~/.zshrc` or `~/.bashrc`) so it is inherited by all child processes.

---

## 5. Brave Search returns "API key not found" or 401

**Symptom:** Brave Search MCP server starts but every search call fails with an authentication error.

**Cause:** `BRAVE_API_KEY` is not set or is invalid.

**Fix:**

Get an API key at https://brave.com/search/api/ and add it to the server config:

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

## 6. Filesystem server returns "Access denied" or refuses to read files

**Symptom:** The filesystem MCP server starts but refuses to read or list directories, returning permission errors.

**Cause:** The server is sandboxed to the directories listed in its `args`. Paths outside those directories are blocked by design.

**Fix:**

Check the args in your config. The filesystem server only grants access to directories explicitly listed after the package name:

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

## 7. Postgres or SQLite server cannot connect to the database

**Symptom:** Server starts but queries fail with connection refused, file not found, or authentication errors.

**Cause:** The connection string or database path in `args` is wrong, the database is not running, or the user lacks permissions.

**Fix:**

For Postgres, verify the database is running and the connection string is correct:

```bash
# Test the connection directly:
psql "postgresql://user:pass@localhost:5432/mydb"

# The connection string goes in args:
```

```json
"postgres": {
  "command": "npx",
  "args": ["-y", "@modelcontextprotocol/server-postgres", "postgresql://user:pass@localhost:5432/mydb"]
}
```

For SQLite, the database file path must be absolute and the file must exist:

```json
"sqlite": {
  "command": "npx",
  "args": ["-y", "@modelcontextprotocol/server-sqlite", "/absolute/path/to/database.db"]
}
```

---

## 8. Slow server startup (15-30+ seconds per server)

**Symptom:** Claude Code takes a long time to become responsive. Each MCP server adds 10-30 seconds to startup.

**Cause:** `npx -y` downloads and installs the package on every launch if it is not cached. Multiple servers compound the delay.

**Fix:**

Install the packages globally so `npx` finds them in the cache immediately:

```bash
# Pre-install the packages you use:
npm install -g @modelcontextprotocol/server-github
npm install -g @anthropic-ai/mcp-fetch
npm install -g @modelcontextprotocol/server-filesystem
npm install -g @modelcontextprotocol/server-memory
```

Alternatively, if you do not need all configured servers for your current task, disable the ones you are not using:

```
/mcp disable brave-search
/mcp disable puppeteer
```

This also frees up context window space. Tool definitions from every enabled MCP server consume tokens even when you never call them.

---

## 9. "Error: Cannot find module" after upgrading Node.js

**Symptom:** Servers that previously worked now fail with `Cannot find module` or `ERR_MODULE_NOT_FOUND`.

**Cause:** Upgrading Node.js (especially via nvm) changes the path to `npx` and invalidates the global package cache for the old version.

**Fix:**

```bash
# Clear the npx cache:
npx clear-npx-cache

# If using absolute paths in settings.json, update them to the new Node version:
which npx
# Update the "command" field in ~/.claude/settings.json

# Reinstall global packages for the new Node version:
npm install -g @modelcontextprotocol/server-github
# ... repeat for other servers
```

---

## 10. Servers work in terminal but fail in Claude Desktop

**Symptom:** Running `npx -y @modelcontextprotocol/server-github` works fine in your terminal, but the same server shows "Failed" in Claude Desktop.

**Cause:** Claude Desktop inherits the system PATH, not your shell's PATH. Tools installed via nvm, Homebrew, or custom paths are invisible to it.

**Fix:**

Use absolute paths for the `command` field in your configuration. See Problem 2 above for details.

Additionally, environment variables set in `.bashrc`/`.zshrc` are not available to Claude Desktop. Any required variables (API keys, tokens) must go in the server's `env` block in the config file.

---

## 11. Two MCP servers conflict or duplicate tool names

**Symptom:** Claude uses the wrong server for a task, or you see unexpected behavior when two servers offer similar capabilities (e.g., both `fetch` and `puppeteer` can retrieve web pages).

**Cause:** MCP tool names are namespaced by server, but Claude picks tools based on the task description. Multiple servers with overlapping capabilities can cause confusion.

**Fix:**

Disable the server you do not need for the current session:

```
/mcp disable puppeteer
```

If the conflict is persistent, remove one of the overlapping servers from your config or rename the server key in `settings.json` to make the purpose clearer. Claude uses the server name as context when selecting tools.

---

## 12. "ETIMEOUT" or "ECONNREFUSED" from Puppeteer or Google Maps server

**Symptom:** The Puppeteer server fails to launch a browser, or the Google Maps server cannot reach the API.

**Cause for Puppeteer:** Chromium is not installed, or the system lacks required libraries for headless browser operation. Common on Linux servers and containers.

**Cause for Google Maps:** `GOOGLE_MAPS_API_KEY` is not set, or the API key does not have the required APIs enabled in Google Cloud Console.

**Fix for Puppeteer:**

```bash
# On macOS, Chromium should install automatically via Puppeteer.
# On Linux (Fedora/RHEL):
dnf install -y chromium

# Or install Puppeteer's bundled Chromium:
npx puppeteer browsers install chrome
```

**Fix for Google Maps:**

```json
"google-maps": {
  "command": "npx",
  "args": ["-y", "@modelcontextprotocol/server-google-maps"],
  "env": {
    "GOOGLE_MAPS_API_KEY": "AIza..."
  }
}
```

Ensure the key has Places API and Geocoding API enabled at https://console.cloud.google.com/apis/library.

---

## 13. Slack server returns "invalid_auth" or "not_authed"

**Symptom:** The Slack MCP server starts but all API calls fail with authentication errors.

**Cause:** `SLACK_BOT_TOKEN` or `SLACK_TEAM_ID` is missing or incorrect.

**Fix:**

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

The bot token must have the required OAuth scopes for the operations you need (channels:read, chat:write, etc.). Check your Slack app configuration at https://api.slack.com/apps.

---

## 14. context7 MCP server fails with "fetch failed" or hangs

**Symptom:** The `@upstash/context7-mcp` server starts but queries time out or return network errors.

**Cause:** The server needs outbound HTTPS access to Upstash's API. Corporate proxies, VPNs, or firewall rules can block it.

**Fix:**

```bash
# Test connectivity:
curl -I https://context7.com

# If behind a proxy, set the proxy env var in the server config:
```

```json
"context7": {
  "command": "npx",
  "args": ["-y", "@upstash/context7-mcp"],
  "env": {
    "HTTPS_PROXY": "http://proxy.corp.example.com:8080"
  }
}
```

If using a corporate proxy with TLS inspection, you also need to set `NODE_EXTRA_CA_CERTS` to your organization's CA bundle:

```json
"env": {
  "NODE_EXTRA_CA_CERTS": "/etc/pki/tls/certs/ca-bundle.crt"
}
```

---

## 15. "SSL certificate verification failed" for any server

**Symptom:** One or more servers fail with SSL/TLS certificate errors during startup or API calls.

**Cause:** A corporate proxy or security appliance is intercepting TLS traffic and presenting its own certificate. Node.js does not trust it by default.

**Fix:**

Add your organization's CA certificate bundle to the server's environment:

```json
"env": {
  "NODE_EXTRA_CA_CERTS": "/path/to/ca-bundle.pem"
}
```

Common locations:
- RHEL/Fedora: `/etc/pki/tls/certs/ca-bundle.crt`
- Ubuntu/Debian: `/etc/ssl/certs/ca-certificates.crt`
- macOS: Export from Keychain Access, or use `security find-certificate -a -p /System/Library/Keychains/SystemRootCertificates.keychain > ~/ca-bundle.pem`

Do NOT set `NODE_TLS_REJECT_UNAUTHORIZED=0`. That disables all certificate validation and is a security risk.

---

## 16. Settings file gets corrupted after running setup.sh multiple times

**Symptom:** `~/.claude/settings.json` contains invalid JSON. Claude Code fails to start or ignores all MCP settings.

**Cause:** A previous run of setup.sh was interrupted, or a manual edit introduced a syntax error (trailing comma, missing quote, etc.).

**Fix:**

```bash
# Validate the current file:
jq . ~/.claude/settings.json

# If broken, restore from backup:
ls -la ~/.claude/settings.json.backup.*
# Pick the most recent valid one:
cp ~/.claude/settings.json.backup.20260625143000 ~/.claude/settings.json

# Validate the restored file:
jq . ~/.claude/settings.json
```

If no backup exists, rebuild from scratch:

```bash
echo '{}' > ~/.claude/settings.json
./setup.sh
```

---

## 17. MCP servers consume too much context window

**Symptom:** Claude reports "Prompt is too long" or responses feel degraded in quality. `/context` shows MCP tool definitions consuming a large chunk of the window.

**Cause:** Every enabled MCP server registers its tool definitions in Claude's context window. With 10+ servers enabled, this can consume thousands of tokens before you even send a message. Subagents inherit all tool definitions from the parent session, making this worse.

**Fix:**

Disable servers you are not actively using:

```
/mcp disable postgres
/mcp disable sqlite
/mcp disable puppeteer
/mcp disable google-maps
/mcp disable slack
```

Re-enable them when needed:

```
/mcp enable postgres
```

Run `/context` to see the token breakdown and identify which servers are consuming the most space.

---

## 18. npm/npx behind corporate proxy returns ECONNREFUSED

**Symptom:** All npx-based servers fail on startup. Running `npx -y <package>` manually also fails with network errors.

**Cause:** npm and npx need proxy configuration to reach the npm registry from behind a corporate firewall.

**Fix:**

```bash
# Configure npm to use your proxy:
npm config set proxy http://proxy.corp.example.com:8080
npm config set https-proxy http://proxy.corp.example.com:8080

# If using a private registry:
npm config set registry https://registry.corp.example.com/

# Verify:
npm view @modelcontextprotocol/server-github version
```

---

## 19. macOS: servers fail after OS update or Xcode Command Line Tools update

**Symptom:** Servers that worked yesterday fail after a macOS update. Errors mention missing libraries or invalid binaries.

**Cause:** macOS updates can reset developer tool paths or invalidate compiled native modules in the npm cache.

**Fix:**

```bash
# Reinstall Xcode Command Line Tools if prompted:
xcode-select --install

# Clear all npm and npx caches:
npm cache clean --force
npx clear-npx-cache

# If using Homebrew-installed Node, relink:
brew reinstall node
```

---

## 20. Linux: servers fail with "GLIBC not found" or similar library errors

**Symptom:** An MCP server (especially Puppeteer) crashes with shared library errors on Linux.

**Cause:** The npm package includes prebuilt native binaries that require a minimum glibc version. Older RHEL/CentOS systems may not meet this requirement. Container images based on Alpine (musl libc) are also affected.

**Fix:**

```bash
# Check your glibc version:
ldd --version

# On RHEL/Fedora, update system libraries:
dnf update -y

# For Puppeteer specifically, install browser dependencies:
dnf install -y \
  alsa-lib atk at-spi2-atk cups-libs libdrm libXcomposite \
  libXdamage libXrandr mesa-libgbm pango

# If on a container, use a base image with glibc (not Alpine):
# FROM registry.access.redhat.com/ubi9/nodejs-22
```

---

## Quick Diagnostic Checklist

Run through this before filing an issue.

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

# 5. Can npx resolve the server packages?
npx -y @modelcontextprotocol/server-github --help 2>&1 | head -5

# 6. Are required environment variables set?
env | grep -E 'GITHUB_PERSONAL_ACCESS_TOKEN|BRAVE_API_KEY|GOOGLE_MAPS_API_KEY|SLACK_BOT_TOKEN'

# 7. Can you reach npm and external APIs?
curl -sI https://registry.npmjs.org/ | head -3

# 8. Run the kit's built-in verification:
./verify.sh

# 9. Check Claude Code's own MCP status:
# (Run inside Claude Code)
# /mcp

# 10. Check overall health:
# (Run inside Claude Code)
# claude doctor
```

If all ten checks pass and the problem persists, run `/feedback` inside Claude Code to send the transcript and environment details to Anthropic.
