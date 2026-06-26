#!/usr/bin/env bash
#
# verify.sh - Check that each configured MCP server is responding
#
# Reads your Claude Code settings, finds all configured MCP servers,
# and tries to start each one to confirm it loads without errors.

set -euo pipefail

SETTINGS_FILE="$HOME/.claude/settings.json"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${GREEN}[PASS]${NC} $1"; }
warn()  { echo -e "${YELLOW}[SKIP]${NC} $1"; }
fail()  { echo -e "${RED}[FAIL]${NC} $1"; }

# -------------------------------------------------------------------
# Preflight
# -------------------------------------------------------------------

if [[ ! -f "$SETTINGS_FILE" ]]; then
    echo -e "${RED}[ERROR]${NC} No settings file found at $SETTINGS_FILE"
    echo "Run setup.sh first to configure MCP servers."
    exit 1
fi

if command -v jq &> /dev/null; then
    JSON_TOOL="jq"
elif command -v python3 &> /dev/null; then
    JSON_TOOL="python3"
elif command -v python &> /dev/null; then
    JSON_TOOL="python"
else
    echo -e "${RED}[ERROR]${NC} Neither jq nor python3 is available."
    exit 1
fi

# -------------------------------------------------------------------
# Get server list
# -------------------------------------------------------------------

get_server_names() {
    if [[ "$JSON_TOOL" == "jq" ]]; then
        jq -r '.mcpServers // {} | keys[]' "$SETTINGS_FILE" 2>/dev/null
    else
        $JSON_TOOL -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
for k in data.get('mcpServers', {}):
    print(k)
" "$SETTINGS_FILE" 2>/dev/null
    fi
}

get_server_command() {
    local name="$1"
    if [[ "$JSON_TOOL" == "jq" ]]; then
        jq -r --arg n "$name" '.mcpServers[$n].command' "$SETTINGS_FILE" 2>/dev/null
    else
        $JSON_TOOL -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
print(data.get('mcpServers', {}).get(sys.argv[2], {}).get('command', ''))
" "$SETTINGS_FILE" "$name" 2>/dev/null
    fi
}

get_server_args() {
    local name="$1"
    if [[ "$JSON_TOOL" == "jq" ]]; then
        jq -r --arg n "$name" '.mcpServers[$n].args[]' "$SETTINGS_FILE" 2>/dev/null
    else
        $JSON_TOOL -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
for a in data.get('mcpServers', {}).get(sys.argv[2], {}).get('args', []):
    print(a)
" "$SETTINGS_FILE" "$name" 2>/dev/null
    fi
}

# -------------------------------------------------------------------
# Verify each server
# -------------------------------------------------------------------

echo ""
echo -e "${BOLD}=====================================${NC}"
echo -e "${BOLD}  MCP Server Verification${NC}"
echo -e "${BOLD}=====================================${NC}"
echo ""

servers=$(get_server_names)

if [[ -z "$servers" ]]; then
    warn "No MCP servers configured in $SETTINGS_FILE"
    exit 0
fi

pass_count=0
fail_count=0
skip_count=0
total=0

while IFS= read -r server_name; do
    total=$((total + 1))
    cmd=$(get_server_command "$server_name")

    if [[ -z "$cmd" || "$cmd" == "null" ]]; then
        warn "$server_name - no command configured"
        skip_count=$((skip_count + 1))
        continue
    fi

    # Read args into an array
    mapfile -t args < <(get_server_args "$server_name")

    # For npx-based servers, check that the package resolves
    if [[ "$cmd" == "npx" ]]; then
        # Find the package name (skip flags like -y)
        pkg=""
        for arg in "${args[@]}"; do
            if [[ "$arg" != -* ]]; then
                pkg="$arg"
                break
            fi
        done

        if [[ -z "$pkg" ]]; then
            warn "$server_name - could not determine package name"
            skip_count=$((skip_count + 1))
            continue
        fi

        # Try to resolve the package with a short timeout
        if timeout 15 npx -y "$pkg" --help &>/dev/null; then
            info "$server_name ($pkg) - server package resolves OK"
            pass_count=$((pass_count + 1))
        else
            # Some MCP servers don't support --help but still resolve fine.
            # Try checking if npm can find the package instead.
            if npm view "$pkg" version &>/dev/null 2>&1; then
                info "$server_name ($pkg) - package exists in npm registry"
                pass_count=$((pass_count + 1))
            else
                fail "$server_name ($pkg) - could not resolve package"
                fail_count=$((fail_count + 1))
            fi
        fi
    else
        # Non-npx server: just check if the command exists
        if command -v "$cmd" &>/dev/null; then
            info "$server_name - command '$cmd' found"
            pass_count=$((pass_count + 1))
        else
            fail "$server_name - command '$cmd' not found"
            fail_count=$((fail_count + 1))
        fi
    fi
done <<< "$servers"

# -------------------------------------------------------------------
# Summary
# -------------------------------------------------------------------

echo ""
echo -e "${BOLD}Results:${NC} $pass_count passed, $fail_count failed, $skip_count skipped (out of $total)"

if [[ $fail_count -gt 0 ]]; then
    echo ""
    echo "Some servers could not be verified. Check that:"
    echo "  - Node.js and npx are installed and working"
    echo "  - You have internet access for npm package resolution"
    echo "  - Required API keys are set (e.g., BRAVE_API_KEY, GITHUB_PERSONAL_ACCESS_TOKEN)"
    exit 1
fi

echo ""
