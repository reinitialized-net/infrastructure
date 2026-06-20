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
  hasLiveSecretsSource = builtins.pathExists liveSecretsSource;
  hasLiveTokenSource = builtins.pathExists liveTokenSource;
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
  tokenFile =
    if automationSecret ? file && automationSecret.file != null
    then toString automationSecret.file
    else "/run/secrets/infra-automation-token";

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

      mkdir -p "$state_dir" "$log_dir" "$run_dir" "$state_dir/renovate-cache" "$state_dir/renovate-home"

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
        HOME="$state_dir/renovate-home" \
        LOG_LEVEL="info" \
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

      mkdir -p "$state_dir" "$log_dir" "$run_dir"

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

        if [ -z "$head_ref" ] || [[ "$head_ref" != "$renovate_branch_prefix"* ]]; then
          continue
        fi

        issue="$(api GET "/repos/$repo_owner/$repo_name/issues/$number")"

        if has_label "$issue" "$manual_label"; then
          infra-update-report \
            --source "renovate-pr-$number" \
            --status "manual-review" \
            --message "Renovate PR #$number is intentionally left open for manual review: $title"
          continue
        fi

        if ! has_label "$issue" "$auto_label"; then
          echo "Skipping Renovate PR #$number without $auto_label label: $title"
          continue
        fi

        log_file="$log_dir/promote-pr-$number-$(date +%Y%m%d%H%M%S).log"
        if validate_pr "$number" "$head_ref" "$log_file"; then
          if merge_pr "$number" "$title"; then
            comment_pr "$number" "infra-promote validated this PR and merged it automatically. Validation log: $log_file"
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

      mkdir -p "$state_dir" "$log_dir" "$run_dir"

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

      if INFRA_SECRETS_DIR="$secrets_dir" FLAKE_PATH="$checkout_dir" updateInfra >> "$log_file" 2>&1; then
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
  ];

  services.infraUpdateReport.enable = true;

  environment.systemPackages = [
    infraDeploy
    infraPromote
    infraRenovate
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
      persistent_token="$secrets_dir/infra-automation-token"

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
      ${pkgs.coreutils}/bin/install -d -o root -g rnetadmin -m 0750 "$(${pkgs.coreutils}/bin/dirname "$token_file")"
      if [ -r "$persistent_token" ]; then
        ${pkgs.coreutils}/bin/install -o root -g rnetadmin -m 0640 "$persistent_token" "$token_file"
      elif [ ! -r "$token_file" ]; then
        echo "warning: Infratainer token is not readable at $token_file or $persistent_token"
      fi
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
