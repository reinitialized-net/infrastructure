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
OPNSENSE_VERIFY_TLS="${OPNSENSE_VERIFY_TLS:-true}"
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
RULES_TMPDIR=$($MKTEMP -d)
trap '$RM -rf "$RULES_TMPDIR"' EXIT

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
  echo "      --verify-tls        Verify TLS certificates (default: true)"
  echo "      --dry-run           Generate rules but skip apply step"
  echo "  -h, --help              Show this help message"
  echo ""
  echo "Environment variables (override secrets, overridden by CLI flags):"
  echo "  OPNSENSE_HOST           Firewall hostname or IP"
  echo "  OPNSENSE_API_KEY        API key"
  echo "  OPNSENSE_API_SECRET     API secret"
  echo "  OPNSENSE_PORT           Management port"
  echo "  OPNSENSE_VERIFY_TLS     Verify TLS (default: true; explicit false disables)"
  echo "  CURL_CA_BUNDLE          Trusted CA bundle for a private management CA"
  echo "  LOG_DAYS                Days of logs (default: 30)"
  echo "  TOP_FLOWS               Top flows to analyze (default: 200)"
  exit 0
}

# OPNsense API call helper
api_call() {
  local method="$1"
  local endpoint="$2"
  local data="${3:-}"
  local -a tls_flags=()
  local timeout_connect="${API_CONNECT_TIMEOUT:-5}"
  local timeout_max="${API_MAX_TIMEOUT:-30}"

  if [[ "$OPNSENSE_VERIFY_TLS" == "false" ]]; then
    tls_flags=(--insecure)
  fi

  local url="https://${OPNSENSE_HOST}:${OPNSENSE_PORT}${endpoint}"

  if [[ -n "$data" ]]; then
    # POST/PUT with body: include Content-Type header
    $CURL --fail-with-body --silent --show-error "${tls_flags[@]}" \
      --connect-timeout "$timeout_connect" \
      --max-time "$timeout_max" \
      -X "$method" \
      -u "${OPNSENSE_API_KEY}:${OPNSENSE_API_SECRET}" \
      -H "Content-Type: application/json" \
      -d "$data" \
      "$url"
  else
    # GET or POST without body: omit Content-Type to avoid "Invalid JSON syntax" errors
    $CURL --fail-with-body --silent --show-error "${tls_flags[@]}" \
      --connect-timeout "$timeout_connect" \
      --max-time "$timeout_max" \
      -X "$method" \
      -u "${OPNSENSE_API_KEY}:${OPNSENSE_API_SECRET}" \
      "$url"
  fi
}

# The configd endpoints return either "ok" or "OK\n" on success.
api_status_ok() {
  $JQ -e '(.status | ascii_downcase | gsub("^\\s+|\\s+$"; "")) == "ok"' >/dev/null 2>&1
}

# Restore staged changes as well as the running policy on every unconfirmed exit.
# Do not cancel the automatic rollback timer on a failure, even if revert fails.
SAVEPOINT_REV=""
CHANGES_STARTED="false"
CHANGES_CONFIRMED="false"
cleanup() {
  local exit_status=$?
  local rollback_result
  trap - EXIT
  if [[ "$CHANGES_STARTED" == "true" && "$CHANGES_CONFIRMED" != "true" ]]; then
    log_warn "Restoring firewall savepoint ${SAVEPOINT_REV}..."
    if rollback_result=$(api_call POST "/api/firewall/filter/revert/${SAVEPOINT_REV}" "{}") &&
      api_status_ok <<< "$rollback_result"; then
      log_ok "Previous firewall configuration restored"
    else
      log_error "Could not restore savepoint. Check the firewall from its console."
      log_error "The automatic rollback timer, if started, has not been cancelled."
      exit_status=1
    fi
  fi
  $RM -rf "$RULES_TMPDIR"
  exit "$exit_status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

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

case "$OPNSENSE_VERIFY_TLS" in
  true) ;;
  false) log_warn "TLS verification is explicitly disabled; API credentials are not protected against impersonation." ;;
  *) log_error "OPNSENSE_VERIFY_TLS must be true or false"; exit 1 ;;
esac
if [[ ! "$TOP_FLOWS" =~ ^[1-9][0-9]*$ ]]; then
  log_error "TOP_FLOWS must be a positive integer"
  exit 1
fi

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
    35) log_error "TLS handshake failed — check the management endpoint and certificate" ;;
    60) log_error "Certificate verification failed — fix its hostname/chain or set CURL_CA_BUNDLE to the trusted private CA bundle" ;;
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
    log_error "Interface names endpoint returned error: ${API_ERR_MSG:-status $API_ERR_STATUS}"
    exit 1
  fi
fi

# Build device-name → friendly-name mapping (e.g. vlan0.12:dmz, igb0:Frontier)
if ! $JQ -e 'type == "object" and length > 0 and all(.[]; type == "string" and length > 0)' \
  <<< "$INTERFACES_JSON" >/dev/null; then
  log_error "Invalid interface discovery response"
  exit 1
fi
INTERFACE_LIST=$($JQ -r 'to_entries[] | "\(.key):\(.value)"' <<< "$INTERFACES_JSON")

# Also fetch the firewall filter interface list for device→OPNsense ID mapping
# The filter API uses internal names (opt4, wan, lan) while logs use device names (vlan0.12, igb0)
FILTER_IFACE_JSON=$(api_call GET "/api/firewall/filter/getInterfaceList")
if ! $JQ -e '.interfaces.items | type == "array" and length > 0 and all(.[];
  (.value | type == "string" and length > 0) and (.label | type == "string" and length > 0))' \
  <<< "$FILTER_IFACE_JSON" >/dev/null; then
  log_error "Invalid firewall interface mapping response"
  exit 1
fi

# Build a mapping: OPNsense-ID → label (e.g. opt4=dmz, wan=Frontier)
IFACE_MAP_FILE="$RULES_TMPDIR/iface_map.tsv"
echo "$FILTER_IFACE_JSON" | $JQ -r '
  .interfaces.items[]? | "\(.value)\t\(.label)"
' > "$IFACE_MAP_FILE"

# Build reverse mapping: label → OPNsense-ID (for rule creation later)
IFACE_LABEL_TO_ID_FILE="$RULES_TMPDIR/iface_label_to_id.tsv"
echo "$FILTER_IFACE_JSON" | $JQ -r '
  .interfaces.items[]? | "\(.label)\t\(.value)"
' > "$IFACE_LABEL_TO_ID_FILE"

# Build device-name → label mapping from getInterfaceNames
# and device-name → OPNsense-ID by cross-referencing
DEVICE_TO_LABEL_FILE="$RULES_TMPDIR/device_to_label.tsv"
echo "$INTERFACES_JSON" | $JQ -r 'to_entries[] | "\(.key)\t\(.value)"' > "$DEVICE_TO_LABEL_FILE"

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

LOG_FILE="$RULES_TMPDIR/firewall_logs.json"
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
echo "$PASS_RESPONSE" | $JQ -c '.[]' > "$LOG_FILE"

log_ok "Fetched ${TOTAL_ROWS} 'pass' log entries"

# Also fetch a smaller sample of "block" entries for informational purposes
BLOCK_FILE="$RULES_TMPDIR/firewall_blocked.json"
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

RULES_FILE="$RULES_TMPDIR/proposed_rules.txt"
RULES_JSON="$RULES_TMPDIR/proposed_rules.ndjson"

# Extract unique traffic patterns from NDJSON log file
# Fields from OPNsense API: interface, action, dir, protoname, src, dst, dstport
# Note: already filtered to action=pass via API query params
if ! $JQ -se 'all(.[];
  ([.interface, .protoname, .src, .dst] | all(.[]; type == "string" and test("^[^[:space:]]+$"))) and
  (.dir == "in" or .dir == "out") and
  (if (.protoname | ascii_downcase) == "tcp" or (.protoname | ascii_downcase) == "udp" or
      (.protoname | ascii_downcase) == "sctp" then
    (.dstport | tostring | test("^[0-9]+$") and (tonumber >= 0 and tonumber <= 65535))
   else true end))
' "$LOG_FILE" >/dev/null; then
  log_error "Incomplete or unsupported traffic log fields; refusing to infer broader allow rules"
  exit 1
fi
$JQ -r '[.interface, .dir, .protoname, .src, .dst, (if .dstport == null or .dstport == "" then "any" else .dstport end)] | @tsv' \
  "$LOG_FILE" 2>/dev/null | \
  $SORT | $UNIQ -c | $SORT -rn | $AWK -v limit="$TOP_FLOWS" 'NR <= limit' \
  > "$RULES_TMPDIR/traffic_summary.tsv"

# Collect unique interfaces from the logs
LOG_INTERFACES=$($AWK '{print $2}' "$RULES_TMPDIR/traffic_summary.tsv" | $SORT -u)

if [[ -z "$LOG_INTERFACES" ]]; then
  log_error "No usable passed traffic found; no rules will be applied"
  exit 1
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
    ' "$RULES_TMPDIR/traffic_summary.tsv"

    IFACE_RULES=$($AWK -v iface="$iface" '$2 == iface' "$RULES_TMPDIR/traffic_summary.tsv" | $WC -l)
    TOTAL_ALLOW_RULES=$((TOTAL_ALLOW_RULES + IFACE_RULES))

    echo ""
    echo "# Default deny for ${iface}"
    echo "DENY   ALL  any    any                  → any                  port any       (default policy)"
    echo ""
  done

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
SAVE_PATH="$RULES_TMPDIR/firewall-rules-$($DATE '+%Y%m%d-%H%M%S').txt"
$CAT "$RULES_FILE" > "$SAVE_PATH"
log_info "Temporary rule preview: ${SAVE_PATH} (removed when this command exits)"

# ── Step 7: Confirmation and apply ─────────────────────────────────────────────

if [[ "$DRY_RUN" == "true" ]]; then
  log_warn "Dry run mode - skipping rule application"
  echo ""
  echo "To apply these rules, run again without --dry-run"
  exit 0
fi

echo ""
echo -e "${YELLOW}${BOLD}⚠  WARNING: Applying these rules will modify your OPNsense firewall.${NC}"
echo -e "${YELLOW}   Generated rules will be added alongside the existing rules.${NC}"
echo -e "${YELLOW}   Ensure you have console access in case of lockout.${NC}"
echo ""

# Require explicit confirmation
read -rp "Do you want to apply these rules? Type 'yes' to confirm: " CONFIRM

if [[ "$CONFIRM" != "yes" ]]; then
  log_warn "Aborted - no rules were applied"
  exit 0
fi

echo ""
log_info "Preparing complete rule set before changing the firewall..."

# Prepare every payload first: a missing interface or unsupported protocol must
# not leave a partial rule set in the firewall configuration.
: > "$RULES_JSON"
TOTAL_ALLOW_RULES=0
for iface in $LOG_INTERFACES; do
  IFACE_LABEL=$($AWK -F'\t' -v dev="$iface" '$1 == dev {print $2}' "$DEVICE_TO_LABEL_FILE")
  FILTER_IFACE_ID=""
  if [[ -n "$IFACE_LABEL" ]]; then
    FILTER_IFACE_ID=$($AWK -F'\t' -v label="$IFACE_LABEL" '$1 == label {print $2}' "$IFACE_LABEL_TO_ID_FILE")
  fi
  if [[ -z "$FILTER_IFACE_ID" || "$FILTER_IFACE_ID" == *$'\n'* ]]; then
    log_error "Cannot uniquely map device '${iface}' to an OPNsense filter interface"
    exit 1
  fi

  RULE_SEQ=1
  $AWK -v iface="$iface" '
    $2 == iface {
      src = $5
      if (split(src, octets, ".") == 4) {
        src = octets[1] "." octets[2] "." octets[3] ".0/24"
      }
      printf "%s|%s|%s|%s|%s\n", $3, $4, src, $6, $7
    }
  ' "$RULES_TMPDIR/traffic_summary.tsv" | $SORT -u > "$RULES_TMPDIR/interface_flows"

  while IFS='|' read -r dir proto src dst port; do
    PROTO_UPPER=$(echo "$proto" | $TR '[:lower:]' '[:upper:]')
    case "$PROTO_UPPER" in
      TCP|UDP|ICMP|GRE|ESP|AH|SCTP|CARP|TCP/UDP) ;;
      *) log_error "Unsupported protocol '${proto}'; no rules have been changed"; exit 1 ;;
    esac
    # This generator and its default deny rules currently support IPv4 only.
    if [[ "$src" == *:* || "$dst" == *:* ]]; then
      log_error "IPv6 traffic requires a separate reviewed policy; no rules have been changed"
      exit 1
    fi

    $JQ -cn \
      --arg direction "$dir" \
      --arg interface "$FILTER_IFACE_ID" \
      --arg protocol "$PROTO_UPPER" \
      --arg source_net "$src" \
      --arg destination_net "$dst" \
      --arg destination_port "$port" \
      --arg description "Auto-generated from traffic analysis ($($DATE '+%Y-%m-%d'))" \
      --arg sequence "$RULE_SEQ" \
      '{"rule": {
        "action": "pass", "direction": $direction, "interface": $interface,
        "ipprotocol": "inet", "protocol": $protocol, "source_net": $source_net,
        "destination_net": $destination_net, "destination_port": $destination_port,
        "description": $description, "sequence": $sequence, "enabled": "1", "quick": "1"
      }}' >> "$RULES_JSON"
    RULE_SEQ=$((RULE_SEQ + 1))
    TOTAL_ALLOW_RULES=$((TOTAL_ALLOW_RULES + 1))
  done < "$RULES_TMPDIR/interface_flows"

  $JQ -cn \
    --arg interface "$FILTER_IFACE_ID" \
    --arg description "Default DENY ALL - Auto-generated ($($DATE '+%Y-%m-%d'))" \
    '{"rule": {
      "action": "block", "direction": "in", "interface": $interface,
      "ipprotocol": "inet", "protocol": "any", "source_net": "any",
      "destination_net": "any", "description": $description, "sequence": "99999",
      "enabled": "1", "quick": "1", "log": "1"
    }}' >> "$RULES_JSON"
done
PLANNED_RULES=$($WC -l < "$RULES_JSON")

# OPNsense releases without savepoint/revert support must use --dry-run. Never
# fall back to applying a policy without rollback protection.
log_info "Creating savepoint for safe rollback..."
if ! SAVEPOINT_RESULT=$(api_call POST "/api/firewall/filter/savepoint" "{}") ||
  ! api_status_ok <<< "$SAVEPOINT_RESULT"; then
  log_error "Savepoint unavailable; no rules have been changed. Use --dry-run."
  exit 1
fi
SAVEPOINT_REV=$($JQ -r '.revision // empty' <<< "$SAVEPOINT_RESULT")
if [[ ! "$SAVEPOINT_REV" =~ ^[0-9]+$ ]]; then
  SAVEPOINT_REV=""
  log_error "Invalid savepoint revision; no rules have been changed"
  exit 1
fi

# Each addRule saves a configuration revision. Keep the original savepoint in
# the server's history throughout staging, with room for apply bookkeeping.
SAVEPOINT_RETENTION=$($JQ -r '.retention // empty' <<< "$SAVEPOINT_RESULT")
if [[ ! "$SAVEPOINT_RETENTION" =~ ^[1-9][0-9]*$ ]] ||
  (( PLANNED_RULES + 2 >= SAVEPOINT_RETENTION )); then
  log_error "Savepoint retention (${SAVEPOINT_RETENTION:-unknown}) is insufficient for ${PLANNED_RULES} rules."
  log_error "Reduce --top-flows or increase configuration backup retention before trying again."
  exit 1
fi
log_ok "Savepoint created (revision: ${SAVEPOINT_REV})"

CHANGES_STARTED="true"
while IFS= read -r RULE_DATA; do
  if ! RESULT=$(api_call POST "/api/firewall/filter/addRule" "$RULE_DATA") ||
    ! $JQ -e '.result == "saved" and (.uuid | type == "string" and length > 0)' \
      <<< "$RESULT" >/dev/null 2>&1; then
    log_error "Rule creation failed; the incomplete policy will be reverted"
    exit 1
  fi
  log_ok "Rule staged: $($JQ -r '.uuid' <<< "$RESULT")"
done < "$RULES_JSON"

# ── Step 8: Apply changes, then obtain explicit confirmation ────────────────────

echo ""
log_info "Applying firewall configuration with a 60-second automatic rollback..."
APPLY_STARTED=$SECONDS
if ! APPLY_RESULT=$(api_call POST "/api/firewall/filter/apply/${SAVEPOINT_REV}" "{}") ||
  ! api_status_ok <<< "$APPLY_RESULT"; then
  log_error "Firewall apply failed; rollback will remain enabled"
  exit 1
fi
log_ok "Firewall rules applied; automatic rollback is still active"

# Leave time for the confirmation request to reach the firewall before its
# timer expires. Start the budget before apply, whose network call can be slow.
CONFIRM_TIMEOUT=$((45 - (SECONDS - APPLY_STARTED)))
log_warn "Verify required connectivity now. Confirm only if the full policy works."
if (( CONFIRM_TIMEOUT <= 0 )) ||
  ! read -r -t "$CONFIRM_TIMEOUT" -p "Type 'keep' to keep the applied rules: " KEEP ||
  [[ "$KEEP" != "keep" ]]; then
  log_warn "Applied rules were not confirmed; restoring the previous configuration"
  exit 1
fi
if (( SECONDS - APPLY_STARTED >= 45 )); then
  log_error "Confirmation arrived too late; restoring the previous configuration"
  exit 1
fi

if ! CANCEL_RESULT=$(API_MAX_TIMEOUT=10 api_call POST "/api/firewall/filter/cancelRollback/${SAVEPOINT_REV}" "{}") ||
  ! api_status_ok <<< "$CANCEL_RESULT"; then
  log_error "Could not confirm rollback cancellation; restoring the previous configuration"
  exit 1
fi
CHANGES_CONFIRMED="true"

# ── Summary ────────────────────────────────────────────────────────────────────

echo ""
log_ok "All ${PLANNED_RULES} firewall rules applied and explicitly confirmed"
echo "  ALLOW rules added: ${TOTAL_ALLOW_RULES}"
echo "  Existing rules remain in place; review ordering and duplicates in OPNsense."
echo "  → https://${OPNSENSE_HOST}:${OPNSENSE_PORT}/ui/firewall/automation"
