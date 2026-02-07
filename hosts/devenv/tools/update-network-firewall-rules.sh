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
SECRETS_API_SECRET_FILE="@secretsApiSecretFile@"

# ── Configuration (env vars override secrets, CLI flags override both) ─────────
OPNSENSE_HOST="${OPNSENSE_HOST:-$SECRETS_HOST}"
OPNSENSE_API_KEY="${OPNSENSE_API_KEY:-$SECRETS_API_KEY}"
OPNSENSE_API_SECRET="${OPNSENSE_API_SECRET:-}"
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
  echo "  secrets.opnsenseFirewall.keys.host      → Firewall host/IP"
  echo "  secrets.opnsenseFirewall.keys.port       → Management port"
  echo "  secrets.opnsenseFirewall.keys.apiKey     → API key"
  echo "  secrets.opnsenseFirewall.file            → Path to API secret file"
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

  if [[ "$OPNSENSE_VERIFY_TLS" != "true" ]]; then
    tls_flag="--insecure"
  fi

  local url="https://${OPNSENSE_HOST}:${OPNSENSE_PORT}${endpoint}"

  if [[ -n "$data" ]]; then
    $CURL -s $tls_flag -X "$method" \
      -u "${OPNSENSE_API_KEY}:${OPNSENSE_API_SECRET}" \
      -H "Content-Type: application/json" \
      -d "$data" \
      "$url"
  else
    $CURL -s $tls_flag -X "$method" \
      -u "${OPNSENSE_API_KEY}:${OPNSENSE_API_SECRET}" \
      -H "Content-Type: application/json" \
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

# Read API secret: prefer env/CLI, then secrets file, then prompt
if [[ -z "$OPNSENSE_API_SECRET" ]]; then
  if [[ -n "$SECRETS_API_SECRET_FILE" && -f "$SECRETS_API_SECRET_FILE" ]]; then
    OPNSENSE_API_SECRET=$($CAT "$SECRETS_API_SECRET_FILE" | $TR -d '\n')
    log_info "API secret loaded from secrets file: ${SECRETS_API_SECRET_FILE}"
  else
    if [[ -n "$SECRETS_API_SECRET_FILE" ]]; then
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

log_info "Testing API connectivity to ${OPNSENSE_HOST}..."

API_TEST=$(api_call GET "/api/core/firmware/status" 2>&1) || {
  log_error "Failed to connect to OPNsense API at ${OPNSENSE_HOST}:${OPNSENSE_PORT}"
  log_error "Check host, port, API key/secret, and network connectivity."
  exit 1
}

# Verify we got a valid JSON response
if ! echo "$API_TEST" | $JQ -e '.product_name // .status // .firmware' >/dev/null 2>&1; then
  log_error "Unexpected API response. Verify API credentials and endpoint."
  log_error "Response: $(echo "$API_TEST" | $HEAD -c 200)"
  exit 1
fi

log_ok "API connection established"

# ── Step 2: Discover interfaces ────────────────────────────────────────────────

log_info "Discovering firewall interfaces..."

INTERFACES_JSON=$(api_call GET "/api/diagnostics/interface/getInterfaceNames")

# Extract interface names into an array
INTERFACE_LIST=$($JQ -r 'to_entries[] | "\(.key):\(.value)"' <<< "$INTERFACES_JSON" 2>/dev/null || true)

if [[ -z "$INTERFACE_LIST" ]]; then
  # Fallback: try the interface statistics endpoint
  INTERFACES_JSON=$(api_call GET "/api/diagnostics/interface/getInterfaceStatistics")
  INTERFACE_LIST=$($JQ -r 'keys[]' <<< "$INTERFACES_JSON" 2>/dev/null || true)
fi

if [[ -z "$INTERFACE_LIST" ]]; then
  log_warn "Could not auto-discover interfaces, falling back to common names"
  INTERFACE_LIST="wan:WAN lan:LAN opt1:OPT1 opt2:OPT2"
fi

echo -e "  Found interfaces:"
echo "$INTERFACE_LIST" | while IFS=: read -r iface desc; do
  echo -e "    ${CYAN}${iface}${NC} (${desc:-$iface})"
done
echo ""

# ── Step 3: Fetch firewall logs ────────────────────────────────────────────────

log_info "Fetching firewall logs for the last ${LOG_DAYS} days..."
log_info "This may take a moment depending on log volume..."

# Calculate the date range
DATE_FROM=$($DATE -d "-${LOG_DAYS} days" '+%Y-%m-%dT00:00:00' 2>/dev/null || \
            $DATE -v-${LOG_DAYS}d '+%Y-%m-%dT00:00:00' 2>/dev/null || \
            echo "")

# Fetch logs using the filter log API with pagination
LOG_FILE="$TMPDIR/firewall_logs.json"
TOTAL_ROWS=0
PAGE=0
ROWS_PER_PAGE=5000

echo -n "  Fetching logs"
while true; do
  OFFSET=$((PAGE * ROWS_PER_PAGE))
  
  # Use the filter log search endpoint
  LOG_RESPONSE=$(api_call POST "/api/diagnostics/firewall/log" \
    "{\"current\":$((PAGE + 1)),\"rowCount\":${ROWS_PER_PAGE},\"sort\":{},\"searchPhrase\":\"\"}")

  # Check if we got valid data
  ROW_COUNT=$(echo "$LOG_RESPONSE" | $JQ '.rows | length' 2>/dev/null || echo "0")

  if [[ "$ROW_COUNT" -eq 0 ]]; then
    break
  fi

  # Append rows to our log file
  echo "$LOG_RESPONSE" | $JQ '.rows[]' >> "$LOG_FILE" 2>/dev/null || true
  TOTAL_ROWS=$((TOTAL_ROWS + ROW_COUNT))

  echo -n "."

  # If we got fewer rows than requested, we've reached the end
  if [[ "$ROW_COUNT" -lt "$ROWS_PER_PAGE" ]]; then
    break
  fi

  PAGE=$((PAGE + 1))

  # Safety limit - don't fetch more than 50 pages
  if [[ $PAGE -ge 50 ]]; then
    log_warn "Reached page limit (${TOTAL_ROWS} entries fetched)"
    break
  fi
done

echo ""
log_ok "Fetched ${TOTAL_ROWS} log entries"

if [[ "$TOTAL_ROWS" -eq 0 ]]; then
  log_error "No firewall log entries found. Check that logging is enabled in OPNsense."
  exit 1
fi

# ── Step 4: Analyze traffic patterns per interface ─────────────────────────────

log_info "Analyzing traffic patterns..."

RULES_FILE="$TMPDIR/proposed_rules.txt"
RULES_JSON="$TMPDIR/proposed_rules.json"
echo "[]" > "$RULES_JSON"

# Extract unique traffic patterns: interface, action, direction, protocol, src, dst, dstport
# Filter to only PASSED traffic (these are what we want to allow)
$JQ -r 'select(.action == "pass") | [.interface // "unknown", .dir // "in", .proto // "tcp", .src // "any", .dst // "any", .dstport // "any"] | @tsv' \
  "$LOG_FILE" 2>/dev/null | \
  $SORT | $UNIQ -c | $SORT -rn | $HEAD -n "$TOP_FLOWS" \
  > "$TMPDIR/traffic_summary.tsv" || true

# Collect unique interfaces from the logs
LOG_INTERFACES=$($AWK '{print $2}' "$TMPDIR/traffic_summary.tsv" | $SORT -u)

if [[ -z "$LOG_INTERFACES" ]]; then
  log_warn "No passed traffic found in logs. Attempting broader analysis..."
  
  # Try with all actions
  $JQ -r '[.interface // "unknown", .dir // "in", .proto // "tcp", .src // "any", .dst // "any", .dstport // "any", .action // "unknown"] | @tsv' \
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

# Convert proposed rules to OPNsense API format and apply
APPLY_ERRORS=0

for iface in $LOG_INTERFACES; do
  log_info "Processing interface: ${iface}"

  # Extract rules for this interface
  IFACE_RULES_FILE="$TMPDIR/iface_${iface}_rules.json"

  # Build rule JSON array for this interface
  RULE_SEQ=1
  echo "[" > "$IFACE_RULES_FILE"

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

    # Create the rule via API
    RULE_DATA=$($JQ -n \
      --arg action "pass" \
      --arg direction "$DIRECTION" \
      --arg interface "$iface" \
      --arg protocol "$($TR '[:upper:]' '[:lower:]' <<< "$proto")" \
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
          "enabled": "1"
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
    --arg interface "$iface" \
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

APPLY_RESULT=$(api_call POST "/api/firewall/filter/apply" "{}" 2>&1) || true

if echo "$APPLY_RESULT" | $JQ -e '.status == "ok"' >/dev/null 2>&1; then
  log_ok "Firewall rules applied successfully"
else
  log_warn "Apply returned unexpected response: $(echo "$APPLY_RESULT" | $HEAD -c 200)"
  log_warn "Please verify rules in OPNsense web UI"
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
echo "  → Review rules in OPNsense: https://${OPNSENSE_HOST}:${OPNSENSE_PORT}/ui/firewall/filter"
