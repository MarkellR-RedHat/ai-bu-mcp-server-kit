#!/usr/bin/env bash
#
# uninstall.sh - Remove MCP server entries from Claude Code settings
#
# Removes all MCP server configurations that were added by setup.sh.
# Safe to run multiple times.
#
# Usage:
#   ./uninstall.sh          Remove all kit-managed servers
#   ./uninstall.sh --select Interactively choose which servers to remove

set -euo pipefail

SETTINGS_FILE="$HOME/.claude/settings.json"
BACKUP_DIR="$HOME/.claude/backups"
BACKUP_FILE="$BACKUP_DIR/settings.backup.$(date +%Y%m%d%H%M%S).json"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

info()  { echo -e "${GREEN}[OK]${NC}   $1"; }
warn()  { echo -e "${YELLOW}[SKIP]${NC} $1"; }
fail()  { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }

# All servers this kit can manage
ALL_MANAGED_SERVERS=(
    "github"
    "fetch"
    "filesystem"
    "brave-search"
    "memory"
    "context7"
    "sequential-thinking"
    "postgres"
    "sqlite"
    "puppeteer"
    "slack"
    "google-maps"
    "everart"
)

# Parse flags
SELECT_MODE=false
for arg in "$@"; do
    case "$arg" in
        --select) SELECT_MODE=true ;;
        --help|-h)
            echo "Usage: ./uninstall.sh [--select]"
            echo ""
            echo "  (none)     Remove all kit-managed MCP servers"
            echo "  --select   Choose which servers to remove"
            exit 0
            ;;
        *) echo "Unknown flag: $arg"; exit 1 ;;
    esac
done

# -------------------------------------------------------------------
# Preflight
# -------------------------------------------------------------------

if [[ ! -f "$SETTINGS_FILE" ]]; then
    warn "No settings file found at $SETTINGS_FILE. Nothing to remove."
    exit 0
fi

# Pick a JSON tool
if command -v jq &> /dev/null; then
    JSON_TOOL="jq"
elif command -v python3 &> /dev/null; then
    JSON_TOOL="python3"
elif command -v python &> /dev/null; then
    JSON_TOOL="python"
else
    fail "Neither jq nor python3 is available. Install one of them first."
fi

# -------------------------------------------------------------------
# Find which managed servers are actually configured
# -------------------------------------------------------------------

get_configured_servers() {
    local configured=()
    for server in "${ALL_MANAGED_SERVERS[@]}"; do
        local exists=false
        if [[ "$JSON_TOOL" == "jq" ]]; then
            exists=$(jq --arg name "$server" '.mcpServers // {} | has($name)' "$SETTINGS_FILE" 2>/dev/null || echo "false")
        else
            exists=$($JSON_TOOL -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
print('true' if sys.argv[2] in data.get('mcpServers', {}) else 'false')
" "$SETTINGS_FILE" "$server" 2>/dev/null || echo "false")
        fi
        if [[ "$exists" == "true" ]]; then
            configured+=("$server")
        fi
    done
    echo "${configured[@]}"
}

# -------------------------------------------------------------------
# Interactive selection
# -------------------------------------------------------------------

select_servers_to_remove() {
    local configured=("$@")

    echo ""
    echo -e "${BOLD}Currently configured MCP servers:${NC}"
    echo ""

    local i=1
    for server in "${configured[@]}"; do
        echo "  $i) $server"
        i=$((i + 1))
    done

    echo ""
    echo "Enter the numbers of servers to remove (space-separated), or press Enter for all:"
    read -r choices

    if [[ -z "$choices" ]]; then
        SERVERS_TO_REMOVE=("${configured[@]}")
        return
    fi

    SERVERS_TO_REMOVE=()
    for choice in $choices; do
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#configured[@]} )); then
            local idx=$((choice - 1))
            SERVERS_TO_REMOVE+=("${configured[$idx]}")
        else
            warn "Ignoring invalid selection: $choice"
        fi
    done
}

# -------------------------------------------------------------------
# Remove servers
# -------------------------------------------------------------------

echo ""
echo -e "${BOLD}MCP Server Uninstall${NC}"
echo ""

read -ra configured <<< "$(get_configured_servers)"

if [[ ${#configured[@]} -eq 0 ]]; then
    warn "No kit-managed MCP servers found in $SETTINGS_FILE"
    exit 0
fi

if $SELECT_MODE; then
    select_servers_to_remove "${configured[@]}"
else
    SERVERS_TO_REMOVE=("${configured[@]}")
fi

if [[ ${#SERVERS_TO_REMOVE[@]} -eq 0 ]]; then
    echo "No servers selected. Nothing to remove."
    exit 0
fi

# Backup
mkdir -p "$BACKUP_DIR"
cp "$SETTINGS_FILE" "$BACKUP_FILE"
info "Backed up settings to $BACKUP_FILE"

# Remove each server
removed_count=0
for server in "${SERVERS_TO_REMOVE[@]}"; do
    if [[ "$JSON_TOOL" == "jq" ]]; then
        tmp=$(mktemp)
        if jq --arg name "$server" '.mcpServers // {} | has($name)' "$SETTINGS_FILE" | grep -q true; then
            jq --arg name "$server" 'del(.mcpServers[$name])' "$SETTINGS_FILE" > "$tmp" && mv "$tmp" "$SETTINGS_FILE"
            info "Removed '$server'"
            removed_count=$((removed_count + 1))
        else
            warn "'$server' was not configured"
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
    print(f"[OK]   Removed '{server_name}'")
else:
    print(f"[SKIP] '{server_name}' was not configured")
PYEOF
    fi
done

echo ""
info "Removed $removed_count server(s). Backup saved to:"
echo "  $BACKUP_FILE"
echo ""
echo "To restore your previous settings:"
echo "  ./setup.sh --restore"
echo ""
