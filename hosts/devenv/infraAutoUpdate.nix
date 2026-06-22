{
  self,
  config,
  lib,
  pkgs,
  ...
}:
let
  automationSecret = config.secrets.infraAutomation or {};
  automationKeys = automationSecret.keys or {};

  stateDir = "/var/lib/infratainer";
  checkoutDir = "${stateDir}/checkout";
  logDir = "/var/log/infratainer";
  runDir = "/run/infratainer";
  secretsDir = automationKeys.secretsDir or "${stateDir}/secrets";
  liveSecretsSource = "${self}/modules/secrets";
  liveTokenSource = "${liveSecretsSource}/infra-automation-token";
  liveDashboardWebhookSecretSource = "${liveSecretsSource}/infra-renovate-webhook-secret";
  hasLiveSecretsSource = builtins.pathExists liveSecretsSource;
  hasLiveTokenSource = builtins.pathExists liveTokenSource;
  hasLiveDashboardWebhookSecretSource = builtins.pathExists liveDashboardWebhookSecretSource;
  meshTopology = import "${self}/modules/profiles/meshNetwork/meshTopology.nix" { inherit lib; };
  exportedHosts = builtins.attrNames self.nixosConfigurations;
  deployHostIps = lib.filter (ip: ip != null) (
    map (
      host:
      let
        node = meshTopology.nodes.${host} or {};
      in
      if host != "devenv" && node ? endpoint then lib.head (lib.splitString ":" node.endpoint) else null
    ) exportedHosts
  );
  deployHostIpsString = lib.concatStringsSep " " deployHostIps;

  forgejoBaseUrl = automationKeys.forgejoBaseUrl or "https://git.ds.reinitialized.net";
  repoOwner = automationKeys.repoOwner or "reinitialized.net";
  repoName = automationKeys.repoName or "infrastructure";
  repoSlug = "${repoOwner}/${repoName}";
  repoCloneUrl = automationKeys.repoCloneUrl or "${forgejoBaseUrl}/${repoOwner}/${repoName}.git";
  defaultBranch = automationKeys.defaultBranch or "indev";
  issueLabels = automationKeys.issueLabels or "infra-auto-update";
  automationName = automationKeys.automationName or "Infratainer";
  forgejoUsername = automationKeys.forgejoUsername or automationName;
  gitAuthorName = automationKeys.gitAuthorName or automationName;
  gitAuthorEmail = automationKeys.gitAuthorEmail or "infratainer@reinitialized.net";
  renovateBranchPrefix = automationKeys.renovateBranchPrefix or "renovate/";
  githubTokenFile = toString (automationKeys.githubTokenFile or "");
  dashboardWebhookEnabled = automationKeys.dashboardWebhookEnabled or true;
  dashboardWebhookSecretFile = toString (
    automationKeys.dashboardWebhookSecretFile or "/run/secrets/infra-renovate-webhook-secret"
  );
  dashboardWebhookBindAddress = automationKeys.dashboardWebhookBindAddress or "10.255.0.1";
  dashboardWebhookPort = automationKeys.dashboardWebhookPort or 1044;
  dashboardWebhookUrl =
    automationKeys.dashboardWebhookUrl
      or "http://${dashboardWebhookBindAddress}:${toString dashboardWebhookPort}/renovate-dashboard";
  tokenFile =
    if automationSecret ? file && automationSecret.file != null
    then toString automationSecret.file
    else "/run/secrets/infra-automation-token";
  runtimeDirSetup = ''
    prepare_runtime_dirs() {
      local mkdir_error
      mkdir_error="$(mktemp)"

      if mkdir -p "$state_dir" "$log_dir" "$run_dir" "''${extra_runtime_dirs[@]}" 2>"$mkdir_error"; then
        rm -f "$mkdir_error"
        return 0
      fi

      cat >&2 <<EOF
Could not prepare Infratainer runtime directories as user $(id -un).

These commands are intended to run through the devenv systemd units, which
execute as rnetadmin after NixOS creates the managed state directories:

  sudo systemctl start infra-renovate.service
  sudo journalctl -u infra-renovate.service -e --no-pager

For the full update flow, run infra-promote.service after Renovate creates PRs,
then infra-deploy.service after PRs have merged.

Original mkdir error:
EOF
      cat "$mkdir_error" >&2
      rm -f "$mkdir_error"
      return 1
    }
  '';

  dashboardWebhookPy = pkgs.writeText "infra-renovate-dashboard-webhook.py" ''
    import hashlib
    import hmac
    import http.server
    import json
    import os
    import re
    import subprocess
    import sys

    BIND_ADDRESS = os.environ["RENOVATE_DASHBOARD_WEBHOOK_BIND"]
    PORT = int(os.environ["RENOVATE_DASHBOARD_WEBHOOK_PORT"])
    SECRET_FILE = os.environ["RENOVATE_DASHBOARD_WEBHOOK_SECRET_FILE"]
    REPOSITORY = os.environ["RENOVATE_DASHBOARD_WEBHOOK_REPOSITORY"]
    ISSUE_TITLE = os.environ["RENOVATE_DASHBOARD_WEBHOOK_ISSUE_TITLE"]
    BOT_USERNAME = os.environ["RENOVATE_DASHBOARD_WEBHOOK_BOT_USERNAME"].lower()
    SYSTEMCTL = os.environ.get("RENOVATE_DASHBOARD_WEBHOOK_SYSTEMCTL", "systemctl")
    SERVICE = os.environ.get("RENOVATE_DASHBOARD_WEBHOOK_SERVICE", "infra-renovate.service")
    MAX_BODY_BYTES = 1024 * 1024
    CHECKED_COMMAND_RE = re.compile(
        r" - \[x\] <!-- (?:(?:[a-zA-Z]+)-branch=[^\s]+|"
        r"rebase-all-open-prs|approve-all-pending-prs|"
        r"create-all-rate-limited-prs|create-config-migration-pr) -->"
    )


    def log(message):
        print(message, flush=True)


    def read_secret():
        with open(SECRET_FILE, "rb") as secret_file:
            secret = secret_file.readline().strip()
        if not secret:
            raise RuntimeError("webhook secret file is empty")
        return secret


    def signature_values(headers):
        for header in ("X-Forgejo-Signature", "X-Gitea-Signature"):
            value = headers.get(header)
            if value:
                yield value.strip().lower()

        value = headers.get("X-Hub-Signature-256")
        if value:
            yield value.strip().lower()

        value = headers.get("X-Hub-Signature")
        if value:
            yield value.strip().lower()


    def valid_signature(headers, body):
        secret = read_secret()
        sha256 = hmac.new(secret, body, hashlib.sha256).hexdigest()
        sha1 = hmac.new(secret, body, hashlib.sha1).hexdigest()
        accepted = {
            sha256,
            "sha256=" + sha256,
            sha1,
            "sha1=" + sha1,
        }

        return any(
            hmac.compare_digest(candidate, expected)
            for candidate in signature_values(headers)
            for expected in accepted
        )


    def get_sender(payload):
        sender = payload.get("sender") or {}
        return (sender.get("username") or sender.get("login") or "").lower()


    def should_start_renovate(headers, payload):
        event = (
            headers.get("X-Forgejo-Event")
            or headers.get("X-Gitea-Event")
            or headers.get("X-GitHub-Event")
            or ""
        ).lower()
        if event not in ("issue", "issues"):
            return False, "ignored non-issue event"

        action = (payload.get("action") or "").lower()
        if action not in ("edited", "updated"):
            return False, "ignored issue action"

        sender = get_sender(payload)
        if sender and sender == BOT_USERNAME:
            return False, "ignored bot-authored dashboard update"

        repository = payload.get("repository") or {}
        full_name = repository.get("full_name") or repository.get("fullName")
        if full_name and full_name != REPOSITORY:
            return False, "ignored different repository"

        issue = payload.get("issue") or {}
        if issue.get("title") != ISSUE_TITLE:
            return False, "ignored different issue"

        body = issue.get("body") or ""
        if not CHECKED_COMMAND_RE.search(body):
            return False, "ignored dashboard edit without a checked Renovate command"

        return True, "dashboard command detected"


    class Handler(http.server.BaseHTTPRequestHandler):
        server_version = "infra-renovate-dashboard-webhook"

        def log_message(self, fmt, *args):
            sys.stdout.write("%s - %s\n" % (self.address_string(), fmt % args))
            sys.stdout.flush()

        def respond(self, status, message):
            body = (message + "\n").encode()
            self.send_response(status)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            if self.path == "/healthz":
                self.respond(200, "ok")
            else:
                self.respond(404, "not found")

        def do_POST(self):
            if self.path != "/renovate-dashboard":
                self.respond(404, "not found")
                return

            try:
                content_length = int(self.headers.get("Content-Length", "0"))
            except ValueError:
                self.respond(400, "invalid content length")
                return

            if content_length <= 0 or content_length > MAX_BODY_BYTES:
                self.respond(413, "invalid payload size")
                return

            body = self.rfile.read(content_length)

            try:
                if not valid_signature(self.headers, body):
                    self.respond(401, "invalid signature")
                    return
            except Exception as err:
                log("signature validation failed: %s" % err)
                self.respond(500, "signature validation failed")
                return

            try:
                payload = json.loads(body.decode("utf-8"))
            except json.JSONDecodeError:
                self.respond(400, "invalid json")
                return

            should_start, reason = should_start_renovate(self.headers, payload)
            if not should_start:
                log(reason)
                self.respond(202, reason)
                return

            result = subprocess.run(
                [SYSTEMCTL, "start", SERVICE],
                text=True,
                capture_output=True,
            )
            if result.returncode != 0:
                log("failed to start %s: %s" % (SERVICE, result.stderr.strip()))
                self.respond(500, "failed to start renovate")
                return

            log("started %s after Dependency Dashboard checkbox edit" % SERVICE)
            self.respond(202, "renovate started")


    def main():
        httpd = http.server.ThreadingHTTPServer((BIND_ADDRESS, PORT), Handler)
        log("listening on http://%s:%s/renovate-dashboard" % (BIND_ADDRESS, PORT))
        httpd.serve_forever()


    if __name__ == "__main__":
        main()
  '';

  dashboardWebhook = pkgs.writeShellApplication {
    name = "infra-renovate-dashboard-webhook";
    runtimeInputs = [
      pkgs.python3
      pkgs.systemd
    ];
    text = ''
      exec ${pkgs.python3}/bin/python3 ${dashboardWebhookPy}
    '';
  };

  dashboardWebhookEnsure = pkgs.writeShellApplication {
    name = "infra-renovate-dashboard-webhook-ensure";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.jq
    ];
    text = ''
      token_file="${tokenFile}"
      secret_file="${dashboardWebhookSecretFile}"
      forgejo_base="${forgejoBaseUrl}"
      repo_owner="${repoOwner}"
      repo_name="${repoName}"
      webhook_url="${dashboardWebhookUrl}"
      api_root="''${forgejo_base%/}/api/v1"

      read_first_line() {
        local file="$1"
        local description="$2"

        if [ ! -r "$file" ]; then
          echo "$description is not readable: $file" >&2
          return 1
        fi

        local value
        value="$(head -n 1 "$file" | tr -d '\r\n')"
        if [ -z "$value" ]; then
          echo "$description is empty: $file" >&2
          return 1
        fi

        printf '%s\n' "$value"
      }

      api() {
        local method="$1"
        local path="$2"
        local payload_file="''${3-}"

        if [ -n "$payload_file" ]; then
          curl --fail-with-body -sS \
            -X "$method" \
            -H "Authorization: token $token" \
            -H "Content-Type: application/json" \
            --data-binary "@$payload_file" \
            "$api_root$path"
        else
          curl --fail-with-body -sS \
            -X "$method" \
            -H "Authorization: token $token" \
            -H "Content-Type: application/json" \
            "$api_root$path"
        fi
      }

      token="$(read_first_line "$token_file" "Forgejo automation token")"
      read_first_line "$secret_file" "dashboard webhook secret" >/dev/null
      hooks="$(api GET "/repos/$repo_owner/$repo_name/hooks")"
      hook_id="$(
        jq -r --arg url "$webhook_url" '
          .[]?
          | select((.config.url // .config.URL // "") == $url)
          | .id
        ' <<< "$hooks" | head -n 1
      )"

      payload_file="$(mktemp)"
      trap 'rm -f "$payload_file"' EXIT
      jq -n \
        --arg url "$webhook_url" \
        --rawfile secret "$secret_file" \
        '{
          active: true,
          type: "forgejo",
          events: ["issues"],
          branch_filter: "",
          config: {
            url: $url,
            content_type: "json",
            http_method: "post",
            secret: ($secret | split("\n")[0])
          }
        }' > "$payload_file"

      if [ -n "$hook_id" ]; then
        api PATCH "/repos/$repo_owner/$repo_name/hooks/$hook_id" "$payload_file" >/dev/null
      else
        api POST "/repos/$repo_owner/$repo_name/hooks" "$payload_file" >/dev/null
      fi

      echo "Forgejo Dependency Dashboard webhook is configured for $webhook_url"
    '';
  };

  infraUpdateReport = import "${self}/library/infraUpdateReport.nix" {
    inherit config pkgs;
  };

  infraRenovate = pkgs.writeShellApplication {
    name = "infra-renovate";
    runtimeInputs = [
      infraUpdateReport
      pkgs.coreutils
      pkgs.git
      pkgs.renovate
    ];
    text = ''
      export PATH="/run/wrappers/bin:/run/current-system/sw/bin:$PATH"

      state_dir="${stateDir}"
      checkout_dir="${checkoutDir}"
      log_dir="${logDir}"
      run_dir="${runDir}"
      token_file="${tokenFile}"
      repo_clone_url="${repoCloneUrl}"
      default_branch="${defaultBranch}"
      repo_slug="${repoSlug}"
      forgejo_base="${forgejoBaseUrl}"
      api_root="''${forgejo_base%/}/api/v1"
      forgejo_username="${forgejoUsername}"
      git_author_name="${gitAuthorName}"
      git_author_email="${gitAuthorEmail}"
      github_token_file="${githubTokenFile}"
      extra_runtime_dirs=("$state_dir/renovate-cache" "$state_dir/renovate-home")

      ${runtimeDirSetup}
      prepare_runtime_dirs

      read_token() {
        if [ ! -r "$token_file" ]; then
          echo "Token file is not readable: $token_file" >&2
          return 1
        fi
        head -n 1 "$token_file" | tr -d '\r\n'
      }

      init_git_auth() {
        {
          printf '%s\n' '#!/usr/bin/env bash'
          printf '%s\n' "case \"\$1\" in"
          printf '%s\n' "  *Username*) printf \"%s\\n\" \"$forgejo_username\" ;;"
          printf '%s\n' "  *) printf \"%s\\n\" \"\$GIT_PASSWORD\" ;;"
          printf '%s\n' 'esac'
        } > "$run_dir/git-askpass"
        chmod 700 "$run_dir/git-askpass"
        export GIT_ASKPASS="$run_dir/git-askpass"
        export GIT_TERMINAL_PROMPT=0
      }

      init_github_auth() {
        local github_token

        if [ -z "$github_token_file" ]; then
          return 0
        fi
        if [ ! -r "$github_token_file" ]; then
          echo "GitHub token file is configured but not readable: $github_token_file" >&2
          return 1
        fi

        github_token="$(head -n 1 "$github_token_file" | tr -d '\r\n')"
        if [ -z "$github_token" ]; then
          echo "GitHub token file is empty: $github_token_file" >&2
          return 1
        fi

        export GITHUB_COM_TOKEN="$github_token"
      }

      ensure_checkout() {
        if [ -e "$checkout_dir" ] && [ ! -d "$checkout_dir/.git" ]; then
          echo "$checkout_dir exists but is not a git checkout" >&2
          return 1
        fi

        if [ ! -d "$checkout_dir/.git" ]; then
          git clone --origin origin "$repo_clone_url" "$checkout_dir"
        fi

        git -C "$checkout_dir" fetch --prune origin
        git -C "$checkout_dir" checkout "$default_branch" 2>/dev/null || git -C "$checkout_dir" checkout -B "$default_branch" "origin/$default_branch"
        git -C "$checkout_dir" reset --hard "origin/$default_branch"
        git -C "$checkout_dir" clean -fdx
      }

      token="$(read_token)"
      if [ -z "$token" ]; then
        echo "Token file is empty: $token_file" >&2
        exit 1
      fi
      export GIT_PASSWORD="$token"
      init_git_auth
      init_github_auth

      log_file="$log_dir/renovate-$(date +%Y%m%d%H%M%S).log"
      if ! ensure_checkout > "$log_file" 2>&1; then
        infra-update-report --source infra-renovate --status failure --log-file "$log_file" --message "Failed to prepare the managed checkout."
        exit 1
      fi

      if RENOVATE_TOKEN="$token" \
        RENOVATE_PLATFORM="forgejo" \
        RENOVATE_ENDPOINT="$api_root/" \
        RENOVATE_AUTODISCOVER="false" \
        RENOVATE_BASE_DIR="$state_dir/renovate-cache" \
        RENOVATE_GIT_AUTHOR="$git_author_name <$git_author_email>" \
        RENOVATE_ALLOWED_COMMANDS='["^nix flake update nixpkgsStable$"]' \
        HOME="$state_dir/renovate-home" \
        LOG_LEVEL="''${LOG_LEVEL:-info}" \
        renovate "$repo_slug" >> "$log_file" 2>&1; then
        echo "Renovate completed successfully. Log: $log_file"
      else
        infra-update-report --source infra-renovate --status failure --log-file "$log_file" --message "Renovate failed while creating dependency update PRs."
        exit 1
      fi
    '';
  };

  infraPromote = pkgs.writeShellApplication {
    name = "infra-promote";
    runtimeInputs = [
      infraUpdateReport
      pkgs.bash
      pkgs.coreutils
      pkgs.curl
      pkgs.git
      pkgs.jq
      pkgs.nix
    ];
    text = ''
      export PATH="/run/wrappers/bin:/run/current-system/sw/bin:$PATH"

      state_dir="${stateDir}"
      checkout_dir="${checkoutDir}"
      log_dir="${logDir}"
      run_dir="${runDir}"
      token_file="${tokenFile}"
      repo_clone_url="${repoCloneUrl}"
      default_branch="${defaultBranch}"
      secrets_dir="${secretsDir}"
      forgejo_base="${forgejoBaseUrl}"
      api_root="''${forgejo_base%/}/api/v1"
      forgejo_username="${forgejoUsername}"
      repo_owner="${repoOwner}"
      repo_name="${repoName}"
      renovate_branch_prefix="${renovateBranchPrefix}"
      auto_label="infra-auto-merge"
      manual_label="manual-update"
      extra_runtime_dirs=()

      ${runtimeDirSetup}
      prepare_runtime_dirs

      read_token() {
        if [ ! -r "$token_file" ]; then
          echo "Token file is not readable: $token_file" >&2
          return 1
        fi
        head -n 1 "$token_file" | tr -d '\r\n'
      }

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

      init_git_auth() {
        {
          printf '%s\n' '#!/usr/bin/env bash'
          printf '%s\n' "case \"\$1\" in"
          printf '%s\n' "  *Username*) printf \"%s\\n\" \"$forgejo_username\" ;;"
          printf '%s\n' "  *) printf \"%s\\n\" \"\$GIT_PASSWORD\" ;;"
          printf '%s\n' 'esac'
        } > "$run_dir/git-askpass"
        chmod 700 "$run_dir/git-askpass"
        export GIT_ASKPASS="$run_dir/git-askpass"
        export GIT_TERMINAL_PROMPT=0
      }

      require_secrets_dir() {
        if [ ! -d "$secrets_dir" ]; then
          echo "Secrets directory is missing: $secrets_dir" >&2
          return 1
        fi

        set -- "$secrets_dir"/*.nix
        if [ ! -e "$1" ]; then
          echo "Secrets directory has no host modules: $secrets_dir/*.nix" >&2
          return 1
        fi
      }

      ensure_checkout() {
        if [ -e "$checkout_dir" ] && [ ! -d "$checkout_dir/.git" ]; then
          echo "$checkout_dir exists but is not a git checkout" >&2
          return 1
        fi

        if [ ! -d "$checkout_dir/.git" ]; then
          git clone --origin origin "$repo_clone_url" "$checkout_dir"
        fi

        git -C "$checkout_dir" fetch --prune origin
        git -C "$checkout_dir" checkout "$default_branch" 2>/dev/null || git -C "$checkout_dir" checkout -B "$default_branch" "origin/$default_branch"
        git -C "$checkout_dir" reset --hard "origin/$default_branch"
        git -C "$checkout_dir" clean -fdx
      }

      has_label() {
        local issue_json="$1"
        local label="$2"
        jq -e --arg label "$label" '.labels[]? | select(.name == $label)' <<< "$issue_json" >/dev/null
      }

      has_manual_approval() {
        local number="$1"
        local head_sha="$2"
        local reviews

        if ! reviews="$(api GET "/repos/$repo_owner/$repo_name/pulls/$number/reviews" 2>/dev/null)"; then
          echo "Could not read reviews for manual Renovate PR #$number; leaving it open." >&2
          return 1
        fi

        jq -e --arg automation "$forgejo_username" --arg head "$head_sha" '
          def login: (.user.login // .reviewer.login // .poster.login // "");
          def state: ((.state // .State // "") | ascii_upcase);
          def active_review: (((.dismissed // false) | not) and ((.stale // false) | not));
          def commit_matches:
            ((has("commit_id") | not) or (.commit_id == null) or (.commit_id == "") or (.commit_id == $head));
          def submitted_at: (.submitted_at // .updated_at // .created_at // "");
          def latest_review_states:
            [
              .[]?
              | select(login != "")
              | select(active_review)
              | select(commit_matches)
              | {
                  login: (login | ascii_downcase),
                  state: state,
                  submitted_at: submitted_at
                }
            ]
            | sort_by(.login, .submitted_at)
            | group_by(.login)
            | map(.[-1]);

          ($automation | ascii_downcase) as $automation_login
          | latest_review_states as $reviews
          | (($reviews | map(select(.state == "APPROVED" and .login != $automation_login)) | length) > 0)
            and (($reviews | map(select(.state == "REQUEST_CHANGES" or .state == "CHANGES_REQUESTED" or .state == "REQUESTED_CHANGES")) | length) == 0)
        ' <<< "$reviews" >/dev/null
      }

      comment_pr() {
        local number="$1"
        local body="$2"
        local payload
        payload="$(jq -n --arg body "$body" '{body: $body}')"
        api POST "/repos/$repo_owner/$repo_name/issues/$number/comments" "$payload" >/dev/null
      }

      merge_pr() {
        local number="$1"
        local pr_title="$2"
        local merge_title="Auto-merge Renovate PR #$number"
        local merge_message="Validated by infra-promote before merge.

$pr_title"
        local payload

        payload="$(jq -n --arg title "$merge_title" --arg message "$merge_message" '{Do: "merge", MergeTitleField: $title, MergeMessageField: $message}')"
        if api POST "/repos/$repo_owner/$repo_name/pulls/$number/merge" "$payload" >/dev/null 2>&1; then
          return 0
        fi

        payload="$(jq -n --arg title "$merge_title" --arg message "$merge_message" '{do: "merge", merge_title_field: $title, merge_message_field: $message}')"
        if api POST "/repos/$repo_owner/$repo_name/pulls/$number/merge" "$payload" >/dev/null 2>&1; then
          return 0
        fi

        payload="$(jq -n --arg title "$merge_title" --arg message "$merge_message" '{Do: "merge", MergeTitleField: $title, MergeMessageField: $message}')"
        api PUT "/repos/$repo_owner/$repo_name/pulls/$number/merge" "$payload" >/dev/null 2>&1
      }

      validate_pr() {
        local number="$1"
        local head_ref="$2"
        local log_file="$3"

        {
          echo "Validating PR #$number from $head_ref"
          git -C "$checkout_dir" fetch origin "$head_ref"
          git -C "$checkout_dir" checkout --detach FETCH_HEAD

          cd "$checkout_dir"
          require_secrets_dir
          export INFRA_SECRETS_DIR="$secrets_dir"
          nix flake show path:. --no-write-lock-file --impure
          nix build --impure --no-link \
            path:.#nixosConfigurations.devenv.config.system.build.toplevel \
            path:.#nixosConfigurations.rp1.config.system.build.toplevel \
            path:.#nixosConfigurations.apps1.config.system.build.toplevel \
            path:.#nixosConfigurations.apps2.config.system.build.toplevel \
            path:.#nixosConfigurations.apps3.config.system.build.toplevel \
            path:.#nixosConfigurations.db1.config.system.build.toplevel
          bash -n hosts/devenv/tools/update-network-firewall-rules.sh
        } > "$log_file" 2>&1
      }

      token="$(read_token)"
      if [ -z "$token" ]; then
        echo "Token file is empty: $token_file" >&2
        exit 1
      fi
      export GIT_PASSWORD="$token"
      init_git_auth

      if ! ensure_checkout; then
        infra-update-report --source infra-promote --status failure --message "Failed to prepare the managed checkout."
        exit 1
      fi

      pulls="$(api GET "/repos/$repo_owner/$repo_name/pulls?state=open&limit=100")"
      mapfile -t pull_rows < <(jq -c '.[]?' <<< "$pulls")

      for pull in "''${pull_rows[@]}"; do
        number="$(jq -r '.number' <<< "$pull")"
        title="$(jq -r '.title' <<< "$pull")"
        head_ref="$(jq -r '.head.ref // empty' <<< "$pull")"
        head_sha="$(jq -r '.head.sha // empty' <<< "$pull")"
        approved_manual=false

        if [ -z "$head_ref" ] || [[ "$head_ref" != "$renovate_branch_prefix"* ]]; then
          continue
        fi

        issue="$(api GET "/repos/$repo_owner/$repo_name/issues/$number")"

        if has_label "$issue" "$manual_label"; then
          if has_manual_approval "$number" "$head_sha"; then
            approved_manual=true
            echo "Manual Renovate PR #$number has an approving review; validating before merge: $title"
          else
            infra-update-report \
              --source "renovate-pr-$number" \
              --status "manual-review" \
              --message "Renovate PR #$number is waiting for a current approving review before Infratainer validates and merges it: $title"
            continue
          fi
        elif ! has_label "$issue" "$auto_label"; then
          echo "Skipping Renovate PR #$number without $auto_label label: $title"
          continue
        fi

        log_file="$log_dir/promote-pr-$number-$(date +%Y%m%d%H%M%S).log"
        if validate_pr "$number" "$head_ref" "$log_file"; then
          if merge_pr "$number" "$title"; then
            if [ "$approved_manual" = true ]; then
              comment_pr "$number" "infra-promote found a current approving review, validated this manual-update PR, and merged it automatically. Validation log: $log_file"
            else
              comment_pr "$number" "infra-promote validated this PR and merged it automatically. Validation log: $log_file"
            fi
            echo "Merged Renovate PR #$number"
          else
            excerpt="$(tail -c 12000 "$log_file")"
            comment_pr "$number" "infra-promote validation passed, but the Forgejo merge API failed. Recent validation log:
\`\`\`text
$excerpt
\`\`\`"
            infra-update-report --source "renovate-pr-$number" --status failure --log-file "$log_file" --message "Validation passed for PR #$number, but merge failed: $title"
            exit 1
          fi
        else
          excerpt="$(tail -c 12000 "$log_file")"
          comment_pr "$number" "infra-promote validation failed. Recent validation log:
\`\`\`text
$excerpt
\`\`\`"
          infra-update-report --source "renovate-pr-$number" --status failure --log-file "$log_file" --message "Validation failed for Renovate PR #$number: $title"
          exit 1
        fi
      done
    '';
  };

  infraDeploy = pkgs.writeShellApplication {
    name = "infra-deploy";
    runtimeInputs = [
      infraUpdateReport
      pkgs.coreutils
      pkgs.git
      pkgs.openssh
    ];
    text = ''
      export PATH="/run/wrappers/bin:/run/current-system/sw/bin:$PATH"

      state_dir="${stateDir}"
      checkout_dir="${checkoutDir}"
      log_dir="${logDir}"
      run_dir="${runDir}"
      token_file="${tokenFile}"
      repo_clone_url="${repoCloneUrl}"
      default_branch="${defaultBranch}"
      secrets_dir="${secretsDir}"
      forgejo_username="${forgejoUsername}"
      deploy_host_ips="${deployHostIpsString}"
      extra_runtime_dirs=()

      ${runtimeDirSetup}
      prepare_runtime_dirs

      read_token() {
        if [ ! -r "$token_file" ]; then
          echo "Token file is not readable: $token_file" >&2
          return 1
        fi
        head -n 1 "$token_file" | tr -d '\r\n'
      }

      init_git_auth() {
        {
          printf '%s\n' '#!/usr/bin/env bash'
          printf '%s\n' "case \"\$1\" in"
          printf '%s\n' "  *Username*) printf \"%s\\n\" \"$forgejo_username\" ;;"
          printf '%s\n' "  *) printf \"%s\\n\" \"\$GIT_PASSWORD\" ;;"
          printf '%s\n' 'esac'
        } > "$run_dir/git-askpass"
        chmod 700 "$run_dir/git-askpass"
        export GIT_ASKPASS="$run_dir/git-askpass"
        export GIT_TERMINAL_PROMPT=0
      }

      require_secrets_dir() {
        if [ ! -d "$secrets_dir" ]; then
          echo "Secrets directory is missing: $secrets_dir" >&2
          return 1
        fi

        set -- "$secrets_dir"/*.nix
        if [ ! -e "$1" ]; then
          echo "Secrets directory has no host modules: $secrets_dir/*.nix" >&2
          return 1
        fi
      }

      ensure_checkout() {
        if [ -e "$checkout_dir" ] && [ ! -d "$checkout_dir/.git" ]; then
          echo "$checkout_dir exists but is not a git checkout" >&2
          return 1
        fi

        if [ ! -d "$checkout_dir/.git" ]; then
          git clone --origin origin "$repo_clone_url" "$checkout_dir"
        fi

        git -C "$checkout_dir" fetch --prune origin
        git -C "$checkout_dir" checkout "$default_branch" 2>/dev/null || git -C "$checkout_dir" checkout -B "$default_branch" "origin/$default_branch"
        git -C "$checkout_dir" reset --hard "origin/$default_branch"
        git -C "$checkout_dir" clean -fdx
      }

      seed_known_hosts() {
        local ssh_dir="$HOME/.ssh"
        mkdir -p "$ssh_dir"
        chmod 700 "$ssh_dir"
        touch "$ssh_dir/known_hosts"
        chmod 600 "$ssh_dir/known_hosts"

        local host
        for host in $deploy_host_ips; do
          if ! ssh-keygen -F "$host" -f "$ssh_dir/known_hosts" >/dev/null; then
            ssh-keyscan -T 10 -H "$host" >> "$ssh_dir/known_hosts" 2>/dev/null
          fi
        done
      }

      token="$(read_token)"
      if [ -z "$token" ]; then
        echo "Token file is empty: $token_file" >&2
        exit 1
      fi
      export GIT_PASSWORD="$token"
      init_git_auth

      log_file="$log_dir/deploy-$(date +%Y%m%d%H%M%S).log"
      if ! ensure_checkout > "$log_file" 2>&1; then
        infra-update-report --source infra-deploy --status failure --log-file "$log_file" --message "Failed to prepare the managed checkout."
        exit 1
      fi

      if ! require_secrets_dir >> "$log_file" 2>&1; then
        infra-update-report --source infra-deploy --status failure --log-file "$log_file" --message "Failed to prepare live secrets for managed checkout $checkout_dir."
        exit 1
      fi

      if ! seed_known_hosts >> "$log_file" 2>&1; then
        infra-update-report --source infra-deploy --status failure --log-file "$log_file" --message "Failed to seed SSH known_hosts for fleet deployment."
        exit 1
      fi

      if INFRA_SECRETS_DIR="$secrets_dir" FLAKE_PATH="$checkout_dir" UPDATE_INFRA_SKIP_HOSTS="devenv" updateInfra >> "$log_file" 2>&1; then
        echo "Fleet deployment completed successfully. Log: $log_file"
      else
        infra-update-report --source infra-deploy --status failure --log-file "$log_file" --message "Fleet deployment failed from managed checkout $checkout_dir."
        exit 1
      fi
    '';
  };
in
{
  imports = [
    "${self}/modules/profiles/infraUpdateReport.nix"
  ];

  assertions = [
    {
      assertion = !(lib.hasPrefix "/nix/store/" tokenFile);
      message = "secrets.infraAutomation.file must point to a runtime secret path such as /run/secrets/infra-automation-token, not a Nix store path.";
    }
    {
      assertion = !dashboardWebhookEnabled || !(lib.hasPrefix "/nix/store/" dashboardWebhookSecretFile);
      message = "secrets.infraAutomation.keys.dashboardWebhookSecretFile must point to a runtime secret path such as /run/secrets/infra-renovate-webhook-secret, not a Nix store path.";
    }
  ];

  services.infraUpdateReport.enable = true;

  environment.systemPackages = [
    infraDeploy
    infraPromote
    infraRenovate
  ] ++ lib.optionals dashboardWebhookEnabled [
    dashboardWebhook
    dashboardWebhookEnsure
  ];

  systemd.tmpfiles.rules = [
    "d ${stateDir} 0750 rnetadmin rnetadmin -"
    "d ${secretsDir} 0750 rnetadmin rnetadmin -"
    "d ${logDir} 0750 rnetadmin rnetadmin -"
    "d ${runDir} 0700 rnetadmin rnetadmin -"
  ];

  system.activationScripts.infratainerSecrets = {
    deps = [
      "groups"
      "users"
    ];
    text = ''
      secrets_dir=${lib.escapeShellArg secretsDir}
      source_dir=${lib.escapeShellArg liveSecretsSource}
      token_file=${lib.escapeShellArg tokenFile}
      webhook_secret_file=${lib.escapeShellArg dashboardWebhookSecretFile}
      persistent_token="$secrets_dir/infra-automation-token"
      persistent_webhook_secret="$secrets_dir/infra-renovate-webhook-secret"

      ${pkgs.coreutils}/bin/install -d -o rnetadmin -g rnetadmin -m 0750 "$secrets_dir"

      ${lib.optionalString hasLiveSecretsSource ''
        copied_modules=0
        for secret_module in "$source_dir"/*.nix; do
          [ -e "$secret_module" ] || continue
          ${pkgs.coreutils}/bin/install -o rnetadmin -g rnetadmin -m 0640 "$secret_module" "$secrets_dir/$(${pkgs.coreutils}/bin/basename "$secret_module")"
          copied_modules=1
        done

        if [ "$copied_modules" -eq 0 ]; then
          echo "warning: no Infratainer secret modules found in $source_dir"
        fi
      ''}
      ${lib.optionalString hasLiveTokenSource ''
        ${pkgs.coreutils}/bin/install -o root -g rnetadmin -m 0640 ${lib.escapeShellArg liveTokenSource} "$persistent_token"
      ''}
      ${lib.optionalString (dashboardWebhookEnabled && hasLiveDashboardWebhookSecretSource) ''
        ${pkgs.coreutils}/bin/install -o root -g rnetadmin -m 0640 ${lib.escapeShellArg liveDashboardWebhookSecretSource} "$persistent_webhook_secret"
      ''}
      ${pkgs.coreutils}/bin/install -d -o root -g rnetadmin -m 0750 "$(${pkgs.coreutils}/bin/dirname "$token_file")"
      if [ -r "$persistent_token" ]; then
        ${pkgs.coreutils}/bin/install -o root -g rnetadmin -m 0640 "$persistent_token" "$token_file"
      elif [ ! -r "$token_file" ]; then
        echo "warning: Infratainer token is not readable at $token_file or $persistent_token"
      fi
      ${lib.optionalString dashboardWebhookEnabled ''
        ${pkgs.coreutils}/bin/install -d -o root -g rnetadmin -m 0750 "$(${pkgs.coreutils}/bin/dirname "$webhook_secret_file")"
        if [ -r "$persistent_webhook_secret" ]; then
          ${pkgs.coreutils}/bin/install -o root -g rnetadmin -m 0640 "$persistent_webhook_secret" "$webhook_secret_file"
        else
          if [ -r "$webhook_secret_file" ]; then
            ${pkgs.coreutils}/bin/install -o root -g rnetadmin -m 0640 "$webhook_secret_file" "$persistent_webhook_secret"
          else
            secret_tmp="$(${pkgs.coreutils}/bin/mktemp)"
            ${pkgs.openssl}/bin/openssl rand -hex 32 > "$secret_tmp"
            ${pkgs.coreutils}/bin/install -o root -g rnetadmin -m 0640 "$secret_tmp" "$persistent_webhook_secret"
            ${pkgs.coreutils}/bin/rm -f "$secret_tmp"
          fi

          ${pkgs.coreutils}/bin/install -o root -g rnetadmin -m 0640 "$persistent_webhook_secret" "$webhook_secret_file"
        fi
      ''}
    '';
  };

  systemd.services.infra-renovate = {
    description = "Create dependency update PRs with Renovate";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    unitConfig.OnFailure = "infra-update-report@%n.service";
    serviceConfig = {
      Type = "oneshot";
      User = "rnetadmin";
      Group = "rnetadmin";
      WorkingDirectory = stateDir;
      ExecStart = "${infraRenovate}/bin/infra-renovate";
      TimeoutStartSec = "2h";
    };
  };

  systemd.services.infra-renovate-dashboard-webhook = lib.mkIf dashboardWebhookEnabled {
    description = "Trigger Renovate from Dependency Dashboard issue checkbox edits";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    unitConfig.OnFailure = "infra-update-report@%n.service";
    environment = {
      RENOVATE_DASHBOARD_WEBHOOK_BIND = dashboardWebhookBindAddress;
      RENOVATE_DASHBOARD_WEBHOOK_PORT = toString dashboardWebhookPort;
      RENOVATE_DASHBOARD_WEBHOOK_SECRET_FILE = dashboardWebhookSecretFile;
      RENOVATE_DASHBOARD_WEBHOOK_REPOSITORY = repoSlug;
      RENOVATE_DASHBOARD_WEBHOOK_ISSUE_TITLE = "Dependency Dashboard";
      RENOVATE_DASHBOARD_WEBHOOK_BOT_USERNAME = forgejoUsername;
      RENOVATE_DASHBOARD_WEBHOOK_SYSTEMCTL = "${pkgs.systemd}/bin/systemctl";
      RENOVATE_DASHBOARD_WEBHOOK_SERVICE = "infra-renovate.service";
    };
    serviceConfig = {
      Type = "simple";
      User = "rnetadmin";
      Group = "rnetadmin";
      SupplementaryGroups = [ "wheel" ];
      ExecStart = "${dashboardWebhook}/bin/infra-renovate-dashboard-webhook";
      Restart = "on-failure";
      RestartSec = "10s";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
      ];
    };
  };

  systemd.services.infra-renovate-dashboard-webhook-ensure = lib.mkIf dashboardWebhookEnabled {
    description = "Ensure Forgejo Dependency Dashboard webhook registration";
    wantedBy = [ "multi-user.target" ];
    wants = [
      "network-online.target"
      "infra-renovate-dashboard-webhook.service"
    ];
    after = [
      "network-online.target"
      "infra-renovate-dashboard-webhook.service"
    ];
    unitConfig.OnFailure = "infra-update-report@%n.service";
    serviceConfig = {
      Type = "oneshot";
      User = "rnetadmin";
      Group = "rnetadmin";
      ExecStart = "${dashboardWebhookEnsure}/bin/infra-renovate-dashboard-webhook-ensure";
      TimeoutStartSec = "2min";
    };
  };

  systemd.timers.infra-renovate = {
    description = "Run Renovate dependency discovery";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "01:00";
      RandomizedDelaySec = "10min";
      Persistent = true;
    };
  };

  systemd.services.infra-promote = {
    description = "Validate and auto-merge eligible Renovate PRs";
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "infra-renovate.service"
    ];
    unitConfig.OnFailure = "infra-update-report@%n.service";
    serviceConfig = {
      Type = "oneshot";
      User = "rnetadmin";
      Group = "rnetadmin";
      WorkingDirectory = stateDir;
      ExecStart = "${infraPromote}/bin/infra-promote";
      TimeoutStartSec = "8h";
    };
  };

  systemd.timers.infra-promote = {
    description = "Validate and merge eligible Renovate PRs";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "01:45";
      RandomizedDelaySec = "10min";
      Persistent = true;
    };
  };

  systemd.services.infra-deploy = {
    description = "Deploy the merged infrastructure flake from the managed checkout";
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "infra-promote.service"
    ];
    unitConfig.OnFailure = "infra-update-report@%n.service";
    serviceConfig = {
      Type = "oneshot";
      User = "rnetadmin";
      Group = "rnetadmin";
      WorkingDirectory = stateDir;
      ExecStart = "${infraDeploy}/bin/infra-deploy";
      TimeoutStartSec = "6h";
    };
  };

  systemd.timers.infra-deploy = {
    description = "Deploy merged infrastructure updates";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "02:30";
      RandomizedDelaySec = "10min";
      Persistent = true;
    };
  };

  systemd.services.nixos-upgrade = {
    environment.INFRA_SECRETS_DIR = secretsDir;
    unitConfig.OnFailure = "infra-update-report@%n.service";
  };
}
