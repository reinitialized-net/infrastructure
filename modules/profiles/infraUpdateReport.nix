{
  self,
  lib,
  config,
  pkgs,
  ...
}:
let
  infraUpdateReport = import "${self}/library/infraUpdateReport.nix" {
    inherit config pkgs;
  };
in
{
  imports = [
    "${self}/modules/profiles/secrets.nix"
  ];

  options.services.infraUpdateReport.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Enable the Forgejo issue reporter for automated infrastructure update failures.";
  };

  config = lib.mkIf config.services.infraUpdateReport.enable {
    environment.systemPackages = [
      infraUpdateReport
    ];

    systemd.services."infra-update-report@" = {
      description = "Report infrastructure update failure for %I";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${infraUpdateReport}/bin/infra-update-report --source %I --status failure --log-unit %I";
      };
    };
  };
}
