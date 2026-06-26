#!/usr/bin/env bash
#
# uninstall.sh - Remove MCP server entries from Claude Code settings
#
# Removes the GitHub, Fetch, and Filesystem MCP server configurations
# that were added by setup.sh. Safe to run multiple times.

set -euo pipefail

SETTINGS_FILE="$HOME/.claude/settings.json"
BACKUP_SUFFIX=".backup.$(date +%Y%m%d%H%M%S)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

SERVERS_TO_REMOVE=("github" "fetch" "filesystem")

# -------------------------------------------------------------------
# Preflight
# -------------------------------------------------------------------

if [[ ! -f "$SETTINGS_FILE" ]]; then
    warn "No settings file found at $SETTINGS_FILE. Nothing to remove."
    exit 0
fi

# -------------------------------------------------------------------
# Pick a JSON tool
# -------------------------------------------------------------------

if command -v jq &> /dev/null; then
    JSON_TOOL="jq"
elif command -v python3 &> /dev/null; then
    JSON_TOOL="python3"
elif command -v python &> /dev/null; then
    JSON_TOOL="python"
else
    error "Neither jq nor python3 is available. Install one of them first."
fi

# -------------------------------------------------------------------
# Backup
# -------------------------------------------------------------------

cp "$SETTINGS_FILE" "${SETTINGS_FILE}${BACKUP_SUFFIX}"
info "Backed up settings to ${SETTINGS_FILE}${BACKUP_SUFFIX}"

# -------------------------------------------------------------------
# Remove servers
# -------------------------------------------------------------------

for server in "${SERVERS_TO_REMOVE[@]}"; do
    if [[ "$JSON_TOOL" == "jq" ]]; then
        tmp=$(mktemp)
        if jq --arg name "$server" '.mcpServers // {} | has($name)' "$SETTINGS_FILE" | grep -q true; then
            jq --arg name "$server" 'del(.mcpServers[$name])' "$SETTINGS_FILE" > "$tmp" && mv "$tmp" "$SETTINGS_FILE"
            info "Removed '$server' MCP server."
        else
            warn "'$server' MCP server was not configured. Skipping."
            rm -f "$tmp"
        fi
    else
        $JSON_TOOL - "$SETTINGS_FILE" "$server" <<'PYEOF'
import json, sys

settings_path = sys.argv[1]
server_name = sys.argv[2]

with open(settings_path, "r") as f:
    settings = json.load(f)

if "mcpServers" in settings and server_name in settings["mcpServers"]:
    del settings["mcpServers"][server_name]
    with open(settings_path, "w") as f:
        json.dump(settings, f, indent=2)
        f.write("\n")
    print(f"[INFO] Removed '{server_name}' MCP server.")
else:
    print(f"[WARN] '{server_name}' MCP server was not configured. Skipping.")
PYEOF
    fi
done

echo ""
info "Uninstall complete. Your original settings were backed up to:"
echo "  ${SETTINGS_FILE}${BACKUP_SUFFIX}"
echo ""
