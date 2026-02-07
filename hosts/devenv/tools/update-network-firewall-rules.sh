#!/usr/bin/env bash
# updateNetworkFirewallRules - OPNsense firewall rule generator from traffic logs
#
# Connects to an OPNsense firewall via API, pulls the last 30 days of traffic logs
# for all interfaces, and generates recommended ALLOW rules per interface with a
# final DENY ALL rule. Presents rules for review before applying.
#
# Requirements:
#   - OPNsense API key + secret (set via environment or prompted)
#   - Network access to the OPNsense management interface
#
set -euo pipefail

# ── Dependency paths (substituted by Nix) ──────────────────────────────────────
CURL="@curl@/bin/curl"
JQ="@jq@/bin/jq"
COLUMN="@util-linux@/bin/column"
SORT="@coreutils@/bin/sort"
UNIQ="@coreutils@/bin/uniq"
AWK="@gawk@/bin/awk"
DATE="@coreutils@/bin/date"
HEAD="@coreutils@/bin/head"
TAIL="@coreutils@/bin/tail"
WC="@coreutils@/bin/wc"
CAT="@coreutils@/bin/cat"
CUT="@coreutils@/bin/cut"
GREP="@gnugrep@/bin/grep"
SED="@gnused@/bin/sed"
MKTEMP="@coreutils@/bin/mktemp"
BASENAME="@coreutils@/bin/basename"
TR="@coreutils@/bin/tr"
RM="@coreutils@/bin/rm"

# ── Secrets (sourced from NixOS secrets module at build time) ──────────────────
SECRETS_HOST="@secretsHost@"
SECRETS_PORT="@secretsPort@"
SECRETS_API_KEY="@secretsApiKey@"
SECRETS_API_SECRET="@secretsApiSecret@"
SECRETS_API_SECRET_FILE="@secretsApiSecretFile@"

# ── Configuration (env vars override secrets, CLI flags override both) ─────────
OPNSENSE_HOST="${OPNSENSE_HOST:-$SECRETS_HOST}"
OPNSENSE_API_KEY="${OPNSENSE_API_KEY:-$SECRETS_API_KEY}"
OPNSENSE_API_SECRET="${OPNSENSE_API_SECRET:-$SECRETS_API_SECRET}"
OPNSENSE_PORT="${OPNSENSE_PORT:-$SECRETS_PORT}"
OPNSENSE_VERIFY_TLS="${OPNSENSE_VERIFY_TLS:-false}"
LOG_DAYS="${LOG_DAYS:-30}"

# How many unique src→dst:port flows to consider for rule generation
TOP_FLOWS="${TOP_FLOWS:-200}"

# ── Colors ─────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ── Temp files ─────────────────────────────────────────────────────────────────
TMPDIR=$($MKTEMP -d)
trap '$RM -rf "$TMPDIR"' EXIT

# ── Helper functions ───────────────────────────────────────────────────────────

log_info()  { echo -e "${BLUE}ℹ${NC}  $*"; }
log_ok()    { echo -e "${GREEN}✓${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}⚠${NC}  $*"; }
log_error() { echo -e "${RED}✗${NC}  $*" >&2; }

usage() {
  echo "Usage: updateNetworkFirewallRules [OPTIONS]"
  echo ""
  echo "Connect to an OPNsense firewall, analyze 30 days of traffic logs,"
  echo "and generate recommended firewall rules per interface."
  echo ""
  echo "Credentials are sourced from the NixOS secrets module by default:"
  echo "  secrets.opnsenseFirewall.keys.host       → Firewall host/IP"
  echo "  secrets.opnsenseFirewall.keys.port        → Management port"
  echo "  secrets.opnsenseFirewall.keys.apiKey      → API key"
  echo "  secrets.opnsenseFirewall.keys.apiSecret   → API secret"
  echo "  secrets.opnsenseFirewall.file             → API secret file (fallback)"
  echo ""
  echo "Options (override secrets/env):"
  echo "  -H, --host HOST         OPNsense hostname or IP"
  echo "  -k, --key KEY           API key"
  echo "  -s, --secret SECRET     API secret (plaintext, prefer file instead)"
  echo "  -p, --port PORT         Management port (default: 443)"
  echo "  -d, --days DAYS         Days of logs to analyze (default: 30)"
  echo "  -t, --top-flows N       Top N flows to consider (default: 200)"
  echo "      --verify-tls        Verify TLS certificates (default: false)"
  echo "      --dry-run           Generate rules but skip apply step"
  echo "  -h, --help              Show this help message"
  echo ""
  echo "Environment variables (override secrets, overridden by CLI flags):"
  echo "  OPNSENSE_HOST           Firewall hostname or IP"
  echo "  OPNSENSE_API_KEY        API key"
  echo "  OPNSENSE_API_SECRET     API secret"
  echo "  OPNSENSE_PORT           Management port"
  echo "  OPNSENSE_VERIFY_TLS     Verify TLS (default: false)"
  echo "  LOG_DAYS                Days of logs (default: 30)"
  echo "  TOP_FLOWS               Top flows to analyze (default: 200)"
  exit 0
}

# OPNsense API call helper
api_call() {
  local method="$1"
  local endpoint="$2"
  local data="${3:-}"
  local tls_flag=""
  local timeout_connect="${API_CONNECT_TIMEOUT:-5}"
  local timeout_max="${API_MAX_TIMEOUT:-30}"

  if [[ "$OPNSENSE_VERIFY_TLS" != "true" ]]; then
    tls_flag="--insecure"
  fi

  local url="https://${OPNSENSE_HOST}:${OPNSENSE_PORT}${endpoint}"

  if [[ -n "$data" ]]; then
    # POST/PUT with body: include Content-Type header
    $CURL -s $tls_flag \
      --connect-timeout "$timeout_connect" \
      --max-time "$timeout_max" \
      -X "$method" \
      -u "${OPNSENSE_API_KEY}:${OPNSENSE_API_SECRET}" \
      -H "Content-Type: application/json" \
      -d "$data" \
      "$url"
  else
    # GET or POST without body: omit Content-Type to avoid "Invalid JSON syntax" errors
    $CURL -s $tls_flag \
      --connect-timeout "$timeout_connect" \
      --max-time "$timeout_max" \
      -X "$method" \
      -u "${OPNSENSE_API_KEY}:${OPNSENSE_API_SECRET}" \
      "$url"
  fi
}

# ── Parse arguments ────────────────────────────────────────────────────────────

DRY_RUN="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -H|--host)      OPNSENSE_HOST="$2"; shift 2 ;;
    -k|--key)       OPNSENSE_API_KEY="$2"; shift 2 ;;
    -s|--secret)    OPNSENSE_API_SECRET="$2"; shift 2 ;;
    -p|--port)      OPNSENSE_PORT="$2"; shift 2 ;;
    -d|--days)      LOG_DAYS="$2"; shift 2 ;;
    -t|--top-flows) TOP_FLOWS="$2"; shift 2 ;;
    --verify-tls)   OPNSENSE_VERIFY_TLS="true"; shift ;;
    --dry-run)      DRY_RUN="true"; shift ;;
    -h|--help)      usage ;;
    *)              log_error "Unknown option: $1"; usage ;;
  esac
done

# ── Validate required config ──────────────────────────────────────────────────

if [[ -z "$OPNSENSE_HOST" ]]; then
  read -rp "OPNsense host/IP: " OPNSENSE_HOST
fi
if [[ -z "$OPNSENSE_API_KEY" ]]; then
  read -rp "API Key: " OPNSENSE_API_KEY
fi

# Read API secret: prefer env/CLI/secrets key, then secrets file, then prompt
if [[ -z "$OPNSENSE_API_SECRET" ]]; then
  if [[ -n "$SECRETS_API_SECRET_FILE" && -f "$SECRETS_API_SECRET_FILE" ]]; then
    OPNSENSE_API_SECRET=$($CAT "$SECRETS_API_SECRET_FILE" | $TR -d '\n')
    log_info "API secret loaded from secrets file: ${SECRETS_API_SECRET_FILE}"
  else
    if [[ -n "$SECRETS_API_SECRET_FILE" && "$SECRETS_API_SECRET_FILE" != "/run/secrets/opnsense-api-secret" ]]; then
      log_warn "Secrets file not found: ${SECRETS_API_SECRET_FILE}"
    fi
    read -rsp "API Secret: " OPNSENSE_API_SECRET
    echo ""
  fi
fi

if [[ -z "$OPNSENSE_HOST" || -z "$OPNSENSE_API_KEY" || -z "$OPNSENSE_API_SECRET" ]]; then
  log_error "OPNsense host, API key, and API secret are all required."
  log_error "Configure via: modules/secrets/devenv.nix (keys.host, keys.apiKey, file for secret)"
  exit 1
fi

# ── Banner ─────────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║  OPNsense Firewall Rule Generator                            ║${NC}"
echo -e "${BOLD}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "  Host:      ${CYAN}${OPNSENSE_HOST}:${OPNSENSE_PORT}${NC}"
echo -e "  Secret:    ${CYAN}${SECRETS_API_SECRET_FILE:-none}${NC}"
echo -e "  Log Range: ${CYAN}Last ${LOG_DAYS} days${NC}"
echo -e "  Top Flows: ${CYAN}${TOP_FLOWS}${NC}"
echo -e "  Dry Run:   ${CYAN}${DRY_RUN}${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ── Step 1: Test API connectivity ─────────────────────────────────────────────

log_info "Testing API connectivity to ${OPNSENSE_HOST}:${OPNSENSE_PORT}..."

# Use a short timeout for the connectivity test
SAVED_CONNECT_TIMEOUT="${API_CONNECT_TIMEOUT:-5}"
SAVED_MAX_TIMEOUT="${API_MAX_TIMEOUT:-30}"
export API_CONNECT_TIMEOUT=5
export API_MAX_TIMEOUT=15

API_TEST=""
CURL_EXIT=0
set +e
API_TEST=$(api_call GET "/api/core/menu/search" 2>&1)
CURL_EXIT=$?
set -e

# Restore default timeouts
export API_CONNECT_TIMEOUT="$SAVED_CONNECT_TIMEOUT"
export API_MAX_TIMEOUT="$SAVED_MAX_TIMEOUT"

if [[ $CURL_EXIT -ne 0 ]]; then
  log_error "Failed to connect to OPNsense API at ${OPNSENSE_HOST}:${OPNSENSE_PORT}"
  case $CURL_EXIT in
    6)  log_error "Could not resolve host '${OPNSENSE_HOST}'" ;;
    7)  log_error "Connection refused — is the API service running?" ;;
    28) log_error "Connection timed out — port ${OPNSENSE_PORT} may be filtered/blocked from this network" ;;
    35) log_error "TLS handshake failed — try --verify-tls or check certificate" ;;
    60) log_error "Certificate verification failed — try without --verify-tls or fix the certificate" ;;
    *)  log_error "curl exit code: $CURL_EXIT" ;;
  esac
  log_error "Verify: network access, host/port, and that the OPNsense API is enabled"
  exit 1
fi

# Check for HTTP-level errors (auth failures, etc)
if echo "$API_TEST" | $JQ -e '.status' >/dev/null 2>&1; then
  API_STATUS=$(echo "$API_TEST" | $JQ -r '.status // empty')
  if [[ "$API_STATUS" == "403" || "$API_STATUS" == "401" ]]; then
    log_error "Authentication failed (HTTP $API_STATUS) — check API key and secret"
    exit 1
  fi
fi

# Verify we got a valid JSON response (any JSON response means connectivity works)
if ! echo "$API_TEST" | $JQ -e '.' >/dev/null 2>&1; then
  # Could be an HTML error page
  RESPONSE_PREVIEW=$(echo "$API_TEST" | $HEAD -c 300)
  if echo "$RESPONSE_PREVIEW" | $GREP -qi "unauthorized\|forbidden\|401\|403"; then
    log_error "Authentication failed — check API key and secret"
  else
    log_error "Unexpected non-JSON response from API"
    log_error "Response: $RESPONSE_PREVIEW"
  fi
  exit 1
fi

log_ok "API connection established"

# ── Step 2: Discover interfaces ────────────────────────────────────────────────

log_info "Discovering firewall interfaces..."

# getInterfaceNames requires POST (despite appearing as GET in docs)
INTERFACES_JSON=$(api_call POST "/api/diagnostics/interface/getInterfaceNames" "{}")

# Detect API error responses before parsing
if echo "$INTERFACES_JSON" | $JQ -e '.status' >/dev/null 2>&1; then
  API_ERR_STATUS=$(echo "$INTERFACES_JSON" | $JQ -r '.status // empty')
  API_ERR_MSG=$(echo "$INTERFACES_JSON" | $JQ -r '.message // empty')
  if [[ -n "$API_ERR_STATUS" && "$API_ERR_STATUS" != "ok" && "$API_ERR_STATUS" != "OK" ]]; then
    log_warn "Interface names endpoint returned error: ${API_ERR_MSG:-status $API_ERR_STATUS}"
    INTERFACES_JSON="{}"
  fi
fi

# Build device-name → friendly-name mapping (e.g. vlan0.12:dmz, igb0:Frontier)
INTERFACE_LIST=$($JQ -r 'to_entries[] | "\(.key):\(.value)"' <<< "$INTERFACES_JSON" 2>/dev/null || true)

# Also fetch the firewall filter interface list for device→OPNsense ID mapping
# The filter API uses internal names (opt4, wan, lan) while logs use device names (vlan0.12, igb0)
FILTER_IFACE_JSON=$(api_call GET "/api/firewall/filter/getInterfaceList")

# Build a mapping: OPNsense-ID → label (e.g. opt4=dmz, wan=Frontier)
IFACE_MAP_FILE="$TMPDIR/iface_map.tsv"
echo "$FILTER_IFACE_JSON" | $JQ -r '
  .interfaces.items[]? | "\(.value)\t\(.label)"
' > "$IFACE_MAP_FILE" 2>/dev/null || true

# Build reverse mapping: label → OPNsense-ID (for rule creation later)
IFACE_LABEL_TO_ID_FILE="$TMPDIR/iface_label_to_id.tsv"
echo "$FILTER_IFACE_JSON" | $JQ -r '
  .interfaces.items[]? | "\(.label)\t\(.value)"
' > "$IFACE_LABEL_TO_ID_FILE" 2>/dev/null || true

# Build device-name → label mapping from getInterfaceNames
# and device-name → OPNsense-ID by cross-referencing
DEVICE_TO_LABEL_FILE="$TMPDIR/device_to_label.tsv"
echo "$INTERFACES_JSON" | $JQ -r 'to_entries[] | "\(.key)\t\(.value)"' > "$DEVICE_TO_LABEL_FILE" 2>/dev/null || true

if [[ -z "$INTERFACE_LIST" ]]; then
  log_warn "Could not auto-discover interfaces, falling back to common names"
  INTERFACE_LIST="wan:WAN lan:LAN opt1:OPT1 opt2:OPT2"
fi

echo -e "  Found interfaces:"
echo "$INTERFACE_LIST" | while IFS=: read -r iface desc; do
  # Look up the OPNsense filter ID for this device
  FILTER_ID=$($AWK -F'\t' -v label="$desc" '$1 == label {print $2}' "$IFACE_LABEL_TO_ID_FILE" 2>/dev/null || true)
  if [[ -n "$FILTER_ID" ]]; then
    echo -e "    ${CYAN}${iface}${NC} → ${desc} (filter ID: ${FILTER_ID})"
  else
    echo -e "    ${CYAN}${iface}${NC} → ${desc}"
  fi
done
echo ""

# ── Step 3: Fetch firewall logs ────────────────────────────────────────────────

log_info "Fetching firewall logs for the last ${LOG_DAYS} days..."
log_info "This may take a moment depending on log volume..."

# OPNsense /api/diagnostics/firewall/log is a GET endpoint that returns a JSON array.
# Query params: limit=N, action=pass|block, interface_name=X, dir=in|out
# The API returns entries from the syslog circular buffer — date range depends on
# log rotation/retention settings, not a user-supplied date parameter.
# We fetch a large batch filtered to "pass" actions only (since we're building ALLOW rules).

LOG_FILE="$TMPDIR/firewall_logs.json"
TOTAL_ROWS=0

# Fetch "pass" logs first (primary for rule generation)
PASS_LIMIT=50000
log_info "Requesting up to ${PASS_LIMIT} 'pass' log entries..."

# Use longer timeout for large log fetches
SAVED_MAX_TIMEOUT2="${API_MAX_TIMEOUT:-30}"
export API_MAX_TIMEOUT=120

set +e
PASS_RESPONSE=$(api_call GET "/api/diagnostics/firewall/log?limit=${PASS_LIMIT}&action=pass" 2>&1)
PASS_EXIT=$?
set -e

export API_MAX_TIMEOUT="$SAVED_MAX_TIMEOUT2"

if [[ $PASS_EXIT -ne 0 ]]; then
  log_error "Failed to fetch firewall logs (curl exit: $PASS_EXIT)"
  exit 1
fi

# Detect API error response
if echo "$PASS_RESPONSE" | $JQ -e '.status' >/dev/null 2>&1; then
  API_ERR=$(echo "$PASS_RESPONSE" | $JQ -r '.message // .status // empty')
  log_error "Firewall log API error: ${API_ERR}"
  exit 1
fi

# Verify we got a JSON array
if ! echo "$PASS_RESPONSE" | $JQ -e 'type == "array"' >/dev/null 2>&1; then
  log_error "Unexpected response format from firewall log API (expected JSON array)"
  log_error "Response preview: $(echo "$PASS_RESPONSE" | $HEAD -c 300)"
  exit 1
fi

TOTAL_ROWS=$(echo "$PASS_RESPONSE" | $JQ 'length')

# Write each entry as a separate JSON line (NDJSON format for later jq processing)
echo "$PASS_RESPONSE" | $JQ -c '.[]' > "$LOG_FILE" 2>/dev/null || true

log_ok "Fetched ${TOTAL_ROWS} 'pass' log entries"

# Also fetch a smaller sample of "block" entries for informational purposes
BLOCK_FILE="$TMPDIR/firewall_blocked.json"
set +e
BLOCK_RESPONSE=$(api_call GET "/api/diagnostics/firewall/log?limit=5000&action=block" 2>&1)
BLOCK_EXIT=$?
set -e

BLOCK_ROWS=0
if [[ $BLOCK_EXIT -eq 0 ]]; then
  if echo "$BLOCK_RESPONSE" | $JQ -e 'type == "array"' >/dev/null 2>&1; then
    BLOCK_ROWS=$(echo "$BLOCK_RESPONSE" | $JQ 'length')
    echo "$BLOCK_RESPONSE" | $JQ -c '.[]' > "$BLOCK_FILE" 2>/dev/null || true
    log_info "Also fetched ${BLOCK_ROWS} 'block' log entries (for reference)"
  fi
fi

# Check date range of fetched logs
if [[ "$TOTAL_ROWS" -gt 0 ]]; then
  OLDEST_TS=$(echo "$PASS_RESPONSE" | $JQ -r '.[-1].__timestamp__ // empty')
  NEWEST_TS=$(echo "$PASS_RESPONSE" | $JQ -r '.[0].__timestamp__ // empty')
  if [[ -n "$OLDEST_TS" && -n "$NEWEST_TS" ]]; then
    log_info "Log time range: ${OLDEST_TS} → ${NEWEST_TS}"
  fi
fi

if [[ "$TOTAL_ROWS" -eq 0 ]]; then
  log_error "No 'pass' firewall log entries found."
  log_error "Check that logging is enabled on firewall rules in OPNsense."
  log_error "Note: The API returns entries from the syslog buffer — very old entries"
  log_error "may have been rotated out. The --days flag is advisory only."
  exit 1
fi

# ── Step 4: Analyze traffic patterns per interface ─────────────────────────────

log_info "Analyzing traffic patterns..."

RULES_FILE="$TMPDIR/proposed_rules.txt"
RULES_JSON="$TMPDIR/proposed_rules.json"
echo "[]" > "$RULES_JSON"

# Extract unique traffic patterns from NDJSON log file
# Fields from OPNsense API: interface, action, dir, protoname, src, dst, dstport
# Note: already filtered to action=pass via API query params
$JQ -r '[.interface // "unknown", .dir // "in", .protoname // "tcp", .src // "any", .dst // "any", .dstport // "any"] | @tsv' \
  "$LOG_FILE" 2>/dev/null | \
  $SORT | $UNIQ -c | $SORT -rn | $HEAD -n "$TOP_FLOWS" \
  > "$TMPDIR/traffic_summary.tsv" || true

# Collect unique interfaces from the logs
LOG_INTERFACES=$($AWK '{print $2}' "$TMPDIR/traffic_summary.tsv" | $SORT -u)

if [[ -z "$LOG_INTERFACES" ]]; then
  log_warn "No passed traffic found in filtered results. Attempting broader analysis..."
  
  # Try without action filter (use all entries in log file)
  $JQ -r '[.interface // "unknown", .dir // "in", .protoname // "tcp", .src // "any", .dst // "any", .dstport // "any", .action // "unknown"] | @tsv' \
    "$LOG_FILE" 2>/dev/null | \
    $SORT | $UNIQ -c | $SORT -rn | $HEAD -n "$TOP_FLOWS" \
    > "$TMPDIR/traffic_summary_all.tsv" || true
  
  LOG_INTERFACES=$($AWK '{print $2}' "$TMPDIR/traffic_summary_all.tsv" | $SORT -u)
fi

# ── Step 5: Generate rules per interface ───────────────────────────────────────

log_info "Generating recommended rules per interface..."
echo ""

RULE_NUM=0
TOTAL_ALLOW_RULES=0

{
  echo "# ═══════════════════════════════════════════════════════════════"
  echo "# OPNsense Firewall Rules - Generated $($DATE '+%Y-%m-%d %H:%M:%S')"
  echo "# Source: Traffic analysis of last ${LOG_DAYS} days"  
  echo "# Host: ${OPNSENSE_HOST}"
  echo "# ═══════════════════════════════════════════════════════════════"
  echo ""

  for iface in $LOG_INTERFACES; do
    echo "# ───────────────────────────────────────────────────────────────"
    echo "# Interface: ${iface}"
    echo "# ───────────────────────────────────────────────────────────────"
    echo ""

    # Aggregate rules for this interface
    # Group by: direction, protocol, source network (aggregated to /24), destination, destination port
    $AWK -v iface="$iface" '
      $2 == iface {
        count = $1
        dir   = $3
        proto = $4
        src   = $5
        dst   = $6
        port  = $7

        # Aggregate source IPs to /24 networks for cleaner rules
        n = split(src, octets, ".")
        if (n == 4) {
          src_net = octets[1] "." octets[2] "." octets[3] ".0/24"
        } else {
          src_net = src
        }

        # Build rule key
        key = dir "|" proto "|" src_net "|" dst "|" port
        hits[key] += count
        dirs[key] = dir
        protos[key] = proto
        srcs[key] = src_net
        dsts[key] = dst
        ports[key] = port
      }
      END {
        # Sort by hit count (descending)
        n = asorti(hits, sorted_keys)
        for (i = n; i >= 1; i--) {
          k = sorted_keys[i]
          printf "ALLOW  %-4s %-6s %-20s → %-20s port %-8s  (%d hits)\n", \
            dirs[k], protos[k], srcs[k], dsts[k], ports[k], hits[k]
        }
      }
    ' "$TMPDIR/traffic_summary.tsv"

    IFACE_RULES=$($AWK -v iface="$iface" '$2 == iface' "$TMPDIR/traffic_summary.tsv" | $WC -l)
    TOTAL_ALLOW_RULES=$((TOTAL_ALLOW_RULES + IFACE_RULES))

    echo ""
    echo "# Default deny for ${iface}"
    echo "DENY   ALL  any    any                  → any                  port any       (default policy)"
    echo ""
  done

  echo "# ═══════════════════════════════════════════════════════════════"
  echo "# FINAL: Global Default Deny"
  echo "# ═══════════════════════════════════════════════════════════════"
  echo "DENY   ALL  any    any                  → any                  port any       (global default)"
  echo ""
  echo "# Total ALLOW rules: ${TOTAL_ALLOW_RULES}"
  echo "# Total interfaces:  $(echo "$LOG_INTERFACES" | $WC -w)"

} > "$RULES_FILE"

# ── Step 6: Present rules for review ──────────────────────────────────────────

echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  PROPOSED FIREWALL RULES${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Colorize the output
while IFS= read -r line; do
  if [[ "$line" =~ ^#.* ]]; then
    echo -e "${CYAN}${line}${NC}"
  elif [[ "$line" =~ ^ALLOW ]]; then
    echo -e "${GREEN}${line}${NC}"
  elif [[ "$line" =~ ^DENY ]]; then
    echo -e "${RED}${line}${NC}"
  else
    echo "$line"
  fi
done < "$RULES_FILE"

echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Also save a clean copy
SAVE_PATH="$TMPDIR/firewall-rules-$($DATE '+%Y%m%d-%H%M%S').txt"
$CAT "$RULES_FILE" > "$SAVE_PATH"
log_info "Rules saved to: ${SAVE_PATH}"

# ── Step 7: Confirmation and apply ─────────────────────────────────────────────

if [[ "$DRY_RUN" == "true" ]]; then
  log_warn "Dry run mode - skipping rule application"
  echo ""
  echo "To apply these rules, run again without --dry-run"
  exit 0
fi

echo ""
echo -e "${YELLOW}${BOLD}⚠  WARNING: Applying these rules will modify your OPNsense firewall.${NC}"
echo -e "${YELLOW}   Existing rules on the affected interfaces will be replaced.${NC}"
echo -e "${YELLOW}   Ensure you have console access in case of lockout.${NC}"
echo ""

# Require explicit confirmation
read -rp "Do you want to apply these rules? Type 'yes' to confirm: " CONFIRM

if [[ "$CONFIRM" != "yes" ]]; then
  log_warn "Aborted - no rules were applied"
  echo "The proposed rules have been saved to: ${SAVE_PATH}"
  exit 0
fi

echo ""
log_info "Applying firewall rules to OPNsense..."

# Create a savepoint for automatic rollback (60s timeout)
log_info "Creating savepoint for safe rollback..."
set +e
SAVEPOINT_RESULT=$(api_call POST "/api/firewall/filter/savepoint" "{}" 2>&1)
SAVEPOINT_EXIT=$?
set -e

SAVEPOINT_REV=""
if [[ $SAVEPOINT_EXIT -eq 0 ]]; then
  SAVEPOINT_REV=$(echo "$SAVEPOINT_RESULT" | $JQ -r '.revision // empty' 2>/dev/null || true)
  if [[ -n "$SAVEPOINT_REV" ]]; then
    log_ok "Savepoint created (revision: ${SAVEPOINT_REV})"
    log_warn "Rules will auto-rollback in 60 seconds unless confirmed!"
  else
    log_warn "Could not create savepoint — proceeding without rollback protection"
  fi
else
  log_warn "Savepoint creation failed — proceeding without rollback protection"
fi

# Convert proposed rules to OPNsense API format and apply
APPLY_ERRORS=0

for iface in $LOG_INTERFACES; do
  log_info "Processing interface: ${iface}"

  # Map device name (e.g. vlan0.12) → friendly label (e.g. dmz) → OPNsense filter ID (e.g. opt4)
  IFACE_LABEL=$($AWK -F'\t' -v dev="$iface" '$1 == dev {print $2}' "$DEVICE_TO_LABEL_FILE" 2>/dev/null || true)
  FILTER_IFACE_ID=""
  if [[ -n "$IFACE_LABEL" ]]; then
    FILTER_IFACE_ID=$($AWK -F'\t' -v label="$IFACE_LABEL" '$1 == label {print $2}' "$IFACE_LABEL_TO_ID_FILE" 2>/dev/null || true)
  fi

  if [[ -z "$FILTER_IFACE_ID" ]]; then
    log_warn "  Cannot map device '${iface}' to OPNsense filter interface — skipping"
    log_warn "  (Known mappings: $($CAT "$DEVICE_TO_LABEL_FILE" 2>/dev/null | $TR '\t' '=' | $TR '\n' ' '))"
    continue
  fi

  log_info "  Mapped: ${iface} → ${IFACE_LABEL} → ${FILTER_IFACE_ID}"

  # Build and apply rules for this interface
  RULE_SEQ=1

  $AWK -v iface="$iface" '
    $2 == iface {
      dir   = $3
      proto = $4
      src   = $5
      dst   = $6
      port  = $7

      # Aggregate source to /24
      n = split(src, octets, ".")
      if (n == 4) {
        src_net = octets[1] "." octets[2] "." octets[3] ".0/24"
      } else {
        src_net = src
      }

      printf "%s|%s|%s|%s|%s\n", dir, proto, src_net, dst, port
    }
  ' "$TMPDIR/traffic_summary.tsv" | $SORT -u | while IFS='|' read -r dir proto src dst port; do

    # Map direction to OPNsense format
    if [[ "$dir" == "in" ]]; then
      DIRECTION="in"
    else
      DIRECTION="out"
    fi

    # Protocol must match OPNsense's expected format (uppercase for TCP, UDP, etc.)
    PROTO_UPPER=$(echo "$proto" | $TR '[:lower:]' '[:upper:]')
    # Map common names
    case "$PROTO_UPPER" in
      TCP|UDP|ICMP|GRE|ESP|AH|SCTP|CARP) ;; # known protocols
      TCP/UDP) ;; # also valid
      *) PROTO_UPPER="any" ;; # fallback for unknown
    esac

    # Create the rule via API
    RULE_DATA=$($JQ -n \
      --arg action "pass" \
      --arg direction "$DIRECTION" \
      --arg interface "$FILTER_IFACE_ID" \
      --arg protocol "$PROTO_UPPER" \
      --arg source_net "$src" \
      --arg destination_net "$dst" \
      --arg destination_port "$port" \
      --arg description "Auto-generated from traffic analysis ($($DATE '+%Y-%m-%d'))" \
      --arg sequence "$RULE_SEQ" \
      '{
        "rule": {
          "action": $action,
          "direction": $direction,
          "interface": $interface,
          "ipprotocol": "inet",
          "protocol": $protocol,
          "source_net": $source_net,
          "destination_net": $destination_net,
          "destination_port": $destination_port,
          "description": $description,
          "sequence": $sequence,
          "enabled": "1",
          "quick": "1"
        }
      }')

    RESULT=$(api_call POST "/api/firewall/filter/addRule" "$RULE_DATA" 2>&1) || true

    if echo "$RESULT" | $JQ -e '.uuid' >/dev/null 2>&1; then
      RULE_UUID=$(echo "$RESULT" | $JQ -r '.uuid')
      log_ok "  Rule created: ${proto} ${src} → ${dst}:${port} (UUID: ${RULE_UUID})"
    else
      log_error "  Failed to create rule: ${proto} ${src} → ${dst}:${port}"
      log_error "  Response: $(echo "$RESULT" | $HEAD -c 200)"
      APPLY_ERRORS=$((APPLY_ERRORS + 1))
    fi

    RULE_SEQ=$((RULE_SEQ + 1))
  done

  # Add DENY ALL rule for this interface
  DENY_DATA=$($JQ -n \
    --arg interface "$FILTER_IFACE_ID" \
    --arg description "Default DENY ALL - Auto-generated ($($DATE '+%Y-%m-%d'))" \
    '{
      "rule": {
        "action": "block",
        "direction": "in",
        "interface": $interface,
        "ipprotocol": "inet",
        "protocol": "any",
        "source_net": "any",
        "destination_net": "any",
        "description": $description,
        "sequence": "99999",
        "enabled": "1",
        "quick": "1",
        "log": "1"
      }
    }')

  DENY_RESULT=$(api_call POST "/api/firewall/filter/addRule" "$DENY_DATA" 2>&1) || true

  if echo "$DENY_RESULT" | $JQ -e '.uuid' >/dev/null 2>&1; then
    log_ok "  DENY ALL rule created for ${iface}"
  else
    log_error "  Failed to create DENY ALL rule for ${iface}"
    APPLY_ERRORS=$((APPLY_ERRORS + 1))
  fi
done

# ── Step 8: Apply changes (save & reload) ─────────────────────────────────────

echo ""
log_info "Saving and applying firewall configuration..."

# Apply changes — if savepoint exists, pass the revision for rollback tracking
if [[ -n "$SAVEPOINT_REV" ]]; then
  APPLY_RESULT=$(api_call POST "/api/firewall/filter/apply/${SAVEPOINT_REV}" "{}" 2>&1) || true
else
  APPLY_RESULT=$(api_call POST "/api/firewall/filter/apply" "{}" 2>&1) || true
fi

if echo "$APPLY_RESULT" | $JQ -e '.status' >/dev/null 2>&1; then
  APPLY_STATUS=$(echo "$APPLY_RESULT" | $JQ -r '.status // empty')
  if [[ "$APPLY_STATUS" == *"OK"* || "$APPLY_STATUS" == *"ok"* ]]; then
    log_ok "Firewall rules applied successfully"
  else
    log_warn "Apply returned status: ${APPLY_STATUS}"
    log_warn "Please verify rules in OPNsense web UI"
  fi
else
  log_warn "Apply returned unexpected response: $(echo "$APPLY_RESULT" | $HEAD -c 200)"
  log_warn "Please verify rules in OPNsense web UI"
fi

# If savepoint was created, cancel the rollback timer to keep changes
if [[ -n "$SAVEPOINT_REV" ]]; then
  echo ""
  log_info "Cancelling automatic rollback..."
  CANCEL_RESULT=$(api_call POST "/api/firewall/filter/cancelRollback/${SAVEPOINT_REV}" "{}" 2>&1) || true
  if echo "$CANCEL_RESULT" | $JQ -e '.status == "ok"' >/dev/null 2>&1; then
    log_ok "Rollback cancelled — changes are now permanent"
  else
    log_warn "Could not cancel rollback. Changes may revert in 60 seconds!"
    log_warn "Manually cancel via: POST /api/firewall/filter/cancelRollback/${SAVEPOINT_REV}"
  fi
fi

# ── Summary ────────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  APPLY SUMMARY${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  Interfaces processed: $(echo "$LOG_INTERFACES" | $WC -w)"
echo -e "  ALLOW rules created:  ${TOTAL_ALLOW_RULES}"
echo -e "  Errors:               ${APPLY_ERRORS}"

if [[ "$APPLY_ERRORS" -gt 0 ]]; then
  log_warn "Some rules failed to apply. Review the output above and check OPNsense."
  exit 1
fi

echo ""
log_ok "All firewall rules applied successfully!"
echo "  → Review rules in OPNsense: https://${OPNSENSE_HOST}:${OPNSENSE_PORT}/ui/firewall/automation"
