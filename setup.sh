#!/usr/bin/env bash
#
# setup.sh - Install and configure MCP servers for Claude Code
#
# This script adds GitHub, Fetch, and Filesystem MCP servers
# to your Claude Code settings. It is safe to run multiple times.

set -euo pipefail

SETTINGS_FILE="$HOME/.claude/settings.json"
SETTINGS_DIR="$HOME/.claude"
BACKUP_SUFFIX=".backup.$(date +%Y%m%d%H%M%S)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# -------------------------------------------------------------------
# Preflight checks
# -------------------------------------------------------------------

check_claude_code() {
    if command -v claude &> /dev/null; then
        info "Claude Code is installed: $(claude --version 2>/dev/null || echo 'version unknown')"
    else
        error "Claude Code is not installed. Install it first: https://docs.anthropic.com/en/docs/claude-code"
    fi
}

check_npx() {
    if command -v npx &> /dev/null; then
        info "npx is available: $(npx --version 2>/dev/null)"
    else
        error "npx is not installed. Install Node.js (v18+) and npm first."
    fi
}

check_jq_or_python() {
    if command -v jq &> /dev/null; then
        JSON_TOOL="jq"
        info "Using jq for JSON processing."
    elif command -v python3 &> /dev/null; then
        JSON_TOOL="python3"
        info "jq not found. Using python3 for JSON processing."
    elif command -v python &> /dev/null; then
        JSON_TOOL="python"
        info "jq not found. Using python for JSON processing."
    else
        error "Neither jq nor python3 is available. Install one of them first."
    fi
}

# -------------------------------------------------------------------
# Backup existing settings
# -------------------------------------------------------------------

backup_settings() {
    if [[ -f "$SETTINGS_FILE" ]]; then
        cp "$SETTINGS_FILE" "${SETTINGS_FILE}${BACKUP_SUFFIX}"
        info "Backed up existing settings to ${SETTINGS_FILE}${BACKUP_SUFFIX}"
    fi
}

# -------------------------------------------------------------------
# JSON merge logic
# -------------------------------------------------------------------

merge_mcp_config() {
    local name="$1"
    local command="$2"
    shift 2
    local args=("$@")

    # Build the args JSON array
    local args_json="["
    local first=true
    for arg in "${args[@]}"; do
        if $first; then
            first=false
        else
            args_json+=","
        fi
        args_json+="\"$arg\""
    done
    args_json+="]"

    local new_server
    new_server=$(cat <<SERVEREOF
{"command":"$command","args":$args_json}
SERVEREOF
)

    if [[ "$JSON_TOOL" == "jq" ]]; then
        local tmp
        tmp=$(mktemp)
        jq --arg name "$name" --argjson server "$new_server" '
            .mcpServers //= {} |
            .mcpServers[$name] = $server
        ' "$SETTINGS_FILE" > "$tmp" && mv "$tmp" "$SETTINGS_FILE"
    else
        $JSON_TOOL - "$SETTINGS_FILE" "$name" "$new_server" <<'PYEOF'
import json, sys

settings_path = sys.argv[1]
server_name = sys.argv[2]
server_json = json.loads(sys.argv[3])

try:
    with open(settings_path, "r") as f:
        settings = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    settings = {}

if "mcpServers" not in settings:
    settings["mcpServers"] = {}

settings["mcpServers"][server_name] = server_json

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
PYEOF
    fi
}

# -------------------------------------------------------------------
# Main
# -------------------------------------------------------------------

main() {
    echo ""
    echo "======================================"
    echo "  MCP Server Kit for Claude Code"
    echo "======================================"
    echo ""

    check_claude_code
    check_npx
    check_jq_or_python

    # Make sure the settings directory and file exist
    mkdir -p "$SETTINGS_DIR"
    if [[ ! -f "$SETTINGS_FILE" ]]; then
        echo '{}' > "$SETTINGS_FILE"
        info "Created new settings file at $SETTINGS_FILE"
    fi

    backup_settings

    # 1. GitHub MCP Server
    info "Configuring GitHub MCP server..."
    merge_mcp_config "github" "npx" "-y" "@modelcontextprotocol/server-github"

    # 2. Fetch MCP Server
    info "Configuring Fetch MCP server..."
    merge_mcp_config "fetch" "npx" "-y" "@anthropic-ai/mcp-fetch"

    # 3. Filesystem MCP Server
    info "Configuring Filesystem MCP server..."
    merge_mcp_config "filesystem" "npx" "-y" "@modelcontextprotocol/server-filesystem" "$HOME/projects"

    echo ""
    info "All MCP servers configured successfully."
    echo ""
    echo "You can verify by running:"
    echo "  cat ~/.claude/settings.json"
    echo ""
    echo "Or start Claude Code and try one of these prompts:"
    echo "  - \"List my GitHub repos\""
    echo "  - \"Fetch the contents of https://example.com\""
    echo "  - \"List the files in my projects directory\""
    echo ""
    echo "To change the filesystem path, edit the 'filesystem' entry"
    echo "in ~/.claude/settings.json and replace $HOME/projects with"
    echo "the directory you want Claude Code to access."
    echo ""
}

main "$@"
