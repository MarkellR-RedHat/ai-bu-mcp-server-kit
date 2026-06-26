#!/usr/bin/env bash
#
# verify.sh - MCP Server Health Dashboard
#
# Tests each configured MCP server, diagnoses common problems,
# suggests fixes, and reports an overall health score.
#
# Usage:
#   ./verify.sh          Full health check with diagnostics
#   ./verify.sh --quick  Package-existence checks only (faster, no npx probe)
#   ./verify.sh --json   Output results as JSON

set -euo pipefail

SETTINGS_FILE="$HOME/.claude/settings.json"

# -------------------------------------------------------------------
# Colors
# -------------------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

PASS="${GREEN}[PASS]${NC}"
FAIL="${RED}[FAIL]${NC}"
WARN="${YELLOW}[WARN]${NC}"
INFO="${BLUE}[INFO]${NC}"

# -------------------------------------------------------------------
# Parse flags
# -------------------------------------------------------------------

QUICK_MODE=false
JSON_MODE=false

for arg in "$@"; do
    case "$arg" in
        --quick) QUICK_MODE=true ;;
        --json)  JSON_MODE=true ;;
        --help|-h)
            echo "Usage: ./verify.sh [--quick] [--json]"
            echo ""
            echo "  --quick   Package-existence checks only (skips startup probe)"
            echo "  --json    Output results as JSON"
            exit 0
            ;;
        *) echo "Unknown flag: $arg"; exit 1 ;;
    esac
done

# -------------------------------------------------------------------
# JSON tool selection
# -------------------------------------------------------------------

if command -v jq &> /dev/null; then
    JSON_TOOL="jq"
elif command -v python3 &> /dev/null; then
    JSON_TOOL="python3"
elif command -v python &> /dev/null; then
    JSON_TOOL="python"
else
    echo -e "$FAIL Neither jq nor python3 is available."
    exit 1
fi

# -------------------------------------------------------------------
# Preflight checks
# -------------------------------------------------------------------

preflight_issues=()

check_preflight() {
    # Settings file
    if [[ ! -f "$SETTINGS_FILE" ]]; then
        preflight_issues+=("No settings file found at $SETTINGS_FILE. Run setup.sh first.")
    fi

    # npx
    if ! command -v npx &>/dev/null; then
        preflight_issues+=("npx is not installed. Install Node.js v18+ to get npx.")
    fi

    # Node version
    if command -v node &>/dev/null; then
        local node_version
        node_version=$(node --version 2>/dev/null | sed 's/v//' | cut -d. -f1)
        if [[ -n "$node_version" ]] && (( node_version < 18 )); then
            preflight_issues+=("Node.js version is below v18 (found v$node_version). Some MCP servers require v18+.")
        fi
    fi

    # Internet connectivity (quick check)
    if ! curl -s --max-time 3 https://registry.npmjs.org/ &>/dev/null; then
        preflight_issues+=("Cannot reach npm registry. Internet access is required for first-run package downloads.")
    fi
}

# -------------------------------------------------------------------
# Server extraction
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

get_server_field() {
    local name="$1" field="$2"
    if [[ "$JSON_TOOL" == "jq" ]]; then
        jq -r --arg n "$name" --arg f "$field" '.mcpServers[$n][$f] // empty' "$SETTINGS_FILE" 2>/dev/null
    else
        $JSON_TOOL -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
val = data.get('mcpServers', {}).get(sys.argv[2], {}).get(sys.argv[3], '')
if isinstance(val, list):
    print(' '.join(str(v) for v in val))
elif val:
    print(val)
" "$SETTINGS_FILE" "$name" "$field" 2>/dev/null
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

get_server_env_keys() {
    local name="$1"
    if [[ "$JSON_TOOL" == "jq" ]]; then
        jq -r --arg n "$name" '.mcpServers[$n].env // {} | keys[]' "$SETTINGS_FILE" 2>/dev/null
    else
        $JSON_TOOL -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
env = data.get('mcpServers', {}).get(sys.argv[2], {}).get('env', {})
for k in env:
    print(k)
" "$SETTINGS_FILE" "$name" 2>/dev/null
    fi
}

get_server_env_value() {
    local name="$1" var="$2"
    if [[ "$JSON_TOOL" == "jq" ]]; then
        jq -r --arg n "$name" --arg v "$var" '.mcpServers[$n].env[$v] // empty' "$SETTINGS_FILE" 2>/dev/null
    else
        $JSON_TOOL -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
val = data.get('mcpServers', {}).get(sys.argv[2], {}).get('env', {}).get(sys.argv[3], '')
if val:
    print(val)
" "$SETTINGS_FILE" "$name" "$var" 2>/dev/null
    fi
}

# -------------------------------------------------------------------
# Diagnostic functions
# -------------------------------------------------------------------

extract_package_name() {
    local name="$1"
    local args
    args=$(get_server_args "$name")
    local pkg=""
    while IFS= read -r arg; do
        if [[ "$arg" != -* && -n "$arg" ]]; then
            pkg="$arg"
            break
        fi
    done <<< "$args"
    echo "$pkg"
}

check_api_keys() {
    local name="$1"
    local issues=()

    local env_keys
    env_keys=$(get_server_env_keys "$name")

    if [[ -z "$env_keys" ]]; then
        return 0
    fi

    while IFS= read -r key; do
        [[ -z "$key" ]] && continue
        local val
        val=$(get_server_env_value "$name" "$key")
        if [[ -z "$val" || "$val" == *"<your-"* || "$val" == *"your_"* || "$val" == *"-here>"* ]]; then
            issues+=("$key is not set (still has placeholder value)")
        fi
    done <<< "$env_keys"

    if [[ ${#issues[@]} -gt 0 ]]; then
        for issue in "${issues[@]}"; do
            echo "  $issue"
        done
        return 1
    fi
    return 0
}

check_path_args() {
    local name="$1"
    local args
    args=$(get_server_args "$name")
    local issues=()

    # Check for path-like arguments (filesystem, sqlite, etc.)
    while IFS= read -r arg; do
        if [[ "$arg" == /* || "$arg" == ~* ]]; then
            local expanded="${arg/#\~/$HOME}"
            if [[ ! -e "$expanded" ]]; then
                issues+=("Path does not exist: $arg")
            elif [[ -d "$expanded" && ! -r "$expanded" ]]; then
                issues+=("Path is not readable: $arg (check permissions)")
            fi
        fi
    done <<< "$args"

    if [[ ${#issues[@]} -gt 0 ]]; then
        for issue in "${issues[@]}"; do
            echo "  $issue"
        done
        return 1
    fi
    return 0
}

verify_package_exists() {
    local pkg="$1"
    if npm view "$pkg" version &>/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

verify_package_runs() {
    local pkg="$1"
    # Try to run with --help, give it a short timeout
    if timeout 15 npx -y "$pkg" --help &>/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# -------------------------------------------------------------------
# Main verification loop
# -------------------------------------------------------------------

run_checks() {
    if ! $JSON_MODE; then
        echo ""
        echo -e "${BOLD}${CYAN}============================================${NC}"
        echo -e "${BOLD}${CYAN}  MCP Server Health Dashboard               ${NC}"
        echo -e "${BOLD}${CYAN}============================================${NC}"
        echo ""
    fi

    # Preflight
    check_preflight

    if [[ ${#preflight_issues[@]} -gt 0 ]]; then
        if ! $JSON_MODE; then
            echo -e "${BOLD}Preflight Issues:${NC}"
            for issue in "${preflight_issues[@]}"; do
                echo -e "  $WARN $issue"
            done
            echo ""
        fi
    fi

    if [[ ! -f "$SETTINGS_FILE" ]]; then
        if $JSON_MODE; then
            echo '{"status":"error","message":"No settings file found","servers":[]}'
        else
            echo -e "$FAIL No settings file at $SETTINGS_FILE"
            echo ""
            echo "Run setup.sh to configure MCP servers."
        fi
        exit 1
    fi

    # Get servers
    local servers
    servers=$(get_server_names)

    if [[ -z "$servers" ]]; then
        if $JSON_MODE; then
            echo '{"status":"warning","message":"No MCP servers configured","servers":[]}'
        else
            echo -e "$WARN No MCP servers configured in $SETTINGS_FILE"
            echo ""
            echo "Run setup.sh to add servers."
        fi
        exit 0
    fi

    local pass_count=0
    local fail_count=0
    local warn_count=0
    local total=0

    # JSON output accumulator
    local json_results="["
    local json_first=true

    if ! $JSON_MODE; then
        echo -e "${BOLD}Server Health Checks:${NC}"
        echo ""
    fi

    while IFS= read -r server_name; do
        [[ -z "$server_name" ]] && continue
        total=$((total + 1))

        local cmd
        cmd=$(get_server_field "$server_name" "command")
        local pkg
        pkg=$(extract_package_name "$server_name")
        local status="pass"
        local status_msg=""
        local diagnostics=()

        # Check 1: command exists
        if [[ -z "$cmd" || "$cmd" == "null" ]]; then
            status="fail"
            status_msg="No command configured"
            diagnostics+=("Fix: check the 'command' field in ~/.claude/settings.json for this server")
        elif ! command -v "$cmd" &>/dev/null; then
            status="fail"
            status_msg="Command '$cmd' not found"
            diagnostics+=("Fix: install $cmd or update the command path in settings.json")
        fi

        # Check 2: for npx servers, verify the package
        if [[ "$status" == "pass" && "$cmd" == "npx" && -n "$pkg" ]]; then
            if $QUICK_MODE; then
                # Quick mode: just check npm registry
                if verify_package_exists "$pkg"; then
                    status_msg="Package found in npm registry"
                else
                    status="fail"
                    status_msg="Package not found: $pkg"
                    diagnostics+=("Fix: verify the package name is correct")
                    diagnostics+=("Fix: check your internet connection")
                fi
            else
                # Full mode: try to resolve and optionally run
                if verify_package_exists "$pkg"; then
                    status_msg="Package verified ($pkg)"
                else
                    status="fail"
                    status_msg="Package not found: $pkg"
                    diagnostics+=("Fix: verify the package name is correct")
                    diagnostics+=("Fix: check your internet connection")
                fi
            fi
        fi

        # Check 3: API key validation
        if [[ "$status" == "pass" ]]; then
            local key_issues
            key_issues=$(check_api_keys "$server_name" 2>/dev/null || true)
            if [[ -n "$key_issues" ]]; then
                status="warn"
                status_msg="${status_msg} (missing API key)"
                while IFS= read -r ki; do
                    [[ -n "$ki" ]] && diagnostics+=("$ki")
                done <<< "$key_issues"
            fi
        fi

        # Check 4: path validation
        if [[ "$status" == "pass" || "$status" == "warn" ]]; then
            local path_issues
            path_issues=$(check_path_args "$server_name" 2>/dev/null || true)
            if [[ -n "$path_issues" ]]; then
                if [[ "$status" == "pass" ]]; then
                    status="warn"
                fi
                while IFS= read -r pi; do
                    [[ -n "$pi" ]] && diagnostics+=("$pi")
                done <<< "$path_issues"
            fi
        fi

        # Count results
        case "$status" in
            pass) pass_count=$((pass_count + 1)) ;;
            fail) fail_count=$((fail_count + 1)) ;;
            warn) warn_count=$((warn_count + 1)) ;;
        esac

        # Output
        if $JSON_MODE; then
            if ! $json_first; then json_results+=","; fi
            json_first=false
            local diag_json="[]"
            if [[ ${#diagnostics[@]} -gt 0 ]]; then
                diag_json="["
                local d_first=true
                for d in "${diagnostics[@]}"; do
                    if ! $d_first; then diag_json+=","; fi
                    d_first=false
                    # Escape quotes in diagnostic messages
                    d="${d//\"/\\\"}"
                    diag_json+="\"$d\""
                done
                diag_json+="]"
            fi
            json_results+="{\"name\":\"$server_name\",\"package\":\"$pkg\",\"status\":\"$status\",\"message\":\"$status_msg\",\"diagnostics\":$diag_json}"
        else
            case "$status" in
                pass)
                    echo -e "  $PASS ${BOLD}$server_name${NC} - $status_msg"
                    ;;
                fail)
                    echo -e "  $FAIL ${BOLD}$server_name${NC} - $status_msg"
                    for d in "${diagnostics[@]}"; do
                        echo -e "       ${DIM}$d${NC}"
                    done
                    ;;
                warn)
                    echo -e "  $WARN ${BOLD}$server_name${NC} - $status_msg"
                    for d in "${diagnostics[@]}"; do
                        echo -e "       ${DIM}$d${NC}"
                    done
                    ;;
            esac
        fi

    done <<< "$servers"

    json_results+="]"

    # -------------------------------------------------------------------
    # Health score
    # -------------------------------------------------------------------

    local score=0
    if [[ $total -gt 0 ]]; then
        score=$(( (pass_count * 100 + warn_count * 50) / total ))
    fi

    local grade
    if (( score >= 90 )); then
        grade="${GREEN}Excellent${NC}"
    elif (( score >= 70 )); then
        grade="${YELLOW}Good${NC}"
    elif (( score >= 50 )); then
        grade="${YELLOW}Fair${NC}"
    else
        grade="${RED}Needs Attention${NC}"
    fi

    if $JSON_MODE; then
        echo "{\"status\":\"complete\",\"total\":$total,\"passed\":$pass_count,\"warned\":$warn_count,\"failed\":$fail_count,\"score\":$score,\"servers\":$json_results}"
    else
        echo ""
        echo -e "${BOLD}============================================${NC}"
        echo -e "${BOLD}  Health Score: ${score}% - ${grade}${NC}"
        echo -e "${BOLD}============================================${NC}"
        echo ""
        echo -e "  ${GREEN}Passed:${NC}  $pass_count"
        echo -e "  ${YELLOW}Warnings:${NC} $warn_count"
        echo -e "  ${RED}Failed:${NC}  $fail_count"
        echo -e "  ${DIM}Total:${NC}   $total"
        echo ""

        if [[ $fail_count -gt 0 ]]; then
            echo -e "${BOLD}Common fixes:${NC}"
            echo ""
            echo "  1. Check internet: curl -s https://registry.npmjs.org/"
            echo "  2. Update Node.js: node --version (need v18+)"
            echo "  3. Clear npx cache: npx clear-npx-cache"
            echo "  4. Set API keys in ~/.claude/settings.json env blocks"
            echo "  5. See troubleshooting.md for detailed diagnostics"
            echo ""
        fi

        if [[ $warn_count -gt 0 && $fail_count -eq 0 ]]; then
            echo "  Some servers have warnings (usually missing API keys)."
            echo "  They will work but with limited functionality."
            echo "  See troubleshooting.md for details."
            echo ""
        fi

        if [[ $pass_count -eq $total ]]; then
            echo -e "  ${GREEN}All servers are healthy. You're good to go.${NC}"
            echo ""
        fi
    fi

    # Exit with error if any servers failed
    if [[ $fail_count -gt 0 ]]; then
        exit 1
    fi
}

run_checks
