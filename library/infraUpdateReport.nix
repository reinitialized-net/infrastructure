{
  config,
  pkgs,
}:
let
  automationSecret = config.secrets.infraAutomation or {};
  automationKeys = automationSecret.keys or {};

  forgejoBaseUrl = automationKeys.forgejoBaseUrl or "https://git.ds.reinitialized.net";
  repoOwner = automationKeys.repoOwner or "reinitialized.net";
  repoName = automationKeys.repoName or "infrastructure";
  issueLabels = automationKeys.issueLabels or "infra-auto-update";
  tokenFile =
    if automationSecret ? file && automationSecret.file != null
    then toString automationSecret.file
    else "/run/secrets/infra-automation-token";
in
pkgs.writeShellApplication {
  name = "infra-update-report";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.curl
    pkgs.jq
    pkgs.systemd
  ];
  text = ''
    source="manual"
    status="failure"
    message=""
    log_unit=""
    log_file=""

    while [ "$#" -gt 0 ]; do
      case "$1" in
        --source)
          source="$2"
          shift 2
          ;;
        --status)
          status="$2"
          shift 2
          ;;
        --message)
          message="$2"
          shift 2
          ;;
        --log-unit)
          log_unit="$2"
          shift 2
          ;;
        --log-file)
          log_file="$2"
          shift 2
          ;;
        -h|--help)
          echo "Usage: infra-update-report --source NAME [--status STATUS] [--message TEXT] [--log-unit UNIT] [--log-file PATH]"
          exit 0
          ;;
        *)
          echo "Unknown option: $1" >&2
          exit 2
          ;;
      esac
    done

    if [ -z "$message" ] && [ ! -t 0 ]; then
      message="$(cat)"
    fi

    token_file="${tokenFile}"
    forgejo_base="${forgejoBaseUrl}"
    api_root="''${forgejo_base%/}/api/v1"
    repo_owner="${repoOwner}"
    repo_name="${repoName}"
    issue_labels="${issueLabels}"

    if [ ! -r "$token_file" ]; then
      echo "infra-update-report: token file is not readable: $token_file" >&2
      exit 0
    fi

    token="$(head -n 1 "$token_file" | tr -d '\r\n')"
    if [ -z "$token" ]; then
      echo "infra-update-report: token file is empty: $token_file" >&2
      exit 0
    fi

    api() {
      local method="$1"
      local path="$2"
      local data="''${3-}"
      if [ -n "$data" ]; then
        curl --fail-with-body -sS \
          -X "$method" \
          -H "Authorization: token $token" \
          -H "Content-Type: application/json" \
          --data "$data" \
          "$api_root$path"
      else
        curl --fail-with-body -sS \
          -X "$method" \
          -H "Authorization: token $token" \
          -H "Content-Type: application/json" \
          "$api_root$path"
      fi
    }

    log_excerpt=""
    if [ -n "$log_file" ] && [ -r "$log_file" ]; then
      log_excerpt="$(tail -c 12000 "$log_file")"
    elif [ -n "$log_unit" ]; then
      log_excerpt="$(journalctl -u "$log_unit" -n 120 --no-pager 2>/dev/null | tail -c 12000 || true)"
    fi

    host="$(cat /etc/hostname 2>/dev/null || echo unknown)"
    now="$(date -Is)"
    title="[infra-auto-update] $source: $status"
    body="Status: $status
Host: $host
Source: $source
Time: $now

$message

Recent logs:
\`\`\`text
$log_excerpt
\`\`\`"

    labels_response="$(api GET "/repos/$repo_owner/$repo_name/labels?limit=100" 2>/dev/null || printf '[]')"
    label_ids="$(jq -n --arg names "$issue_labels" --argjson labels "$labels_response" '
      ($names | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0))) as $wanted
      | [$labels[]? | select(.name as $name | $wanted | index($name)) | .id]
    ')"

    issues_response="$(api GET "/repos/$repo_owner/$repo_name/issues?state=open&limit=100" 2>/dev/null || printf '[]')"
    existing_number="$(jq -r --arg title "$title" '.[]? | select(.title == $title) | .number' <<< "$issues_response" | head -n 1)"

    if [ -n "$existing_number" ]; then
      payload="$(jq -n --arg title "$title" --arg body "$body" '{title: $title, body: $body}')"
      api PATCH "/repos/$repo_owner/$repo_name/issues/$existing_number" "$payload" >/dev/null
      echo "Updated Forgejo issue #$existing_number for $source"
    else
      payload="$(jq -n --arg title "$title" --arg body "$body" --argjson labels "$label_ids" '{title: $title, body: $body, labels: $labels}')"
      created="$(api POST "/repos/$repo_owner/$repo_name/issues" "$payload")"
      created_number="$(jq -r '.number // empty' <<< "$created")"
      echo "Created Forgejo issue #$created_number for $source"
    fi
  '';
}
