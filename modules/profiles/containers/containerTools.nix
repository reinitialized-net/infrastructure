{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Helper function to create a script with package substitution
  makeToolScript =
    name: scriptPath: substitutions:
    let
      # Read the script file
      scriptContent = builtins.readFile scriptPath;
      # Replace @package@ style placeholders with actual paths
      replacedContent = lib.replaceStrings (map (key: "@${key}@") (
        builtins.attrNames substitutions
      )) (builtins.attrValues substitutions) scriptContent;
    in
    pkgs.writeScriptBin name replacedContent;

  containerServicesFile = pkgs.writeText "docker-migration-services.json" (
    builtins.toJSON (
      lib.mapAttrs (name: container: {
        unit = "${lib.removeSuffix ".service" container.serviceName}.service";
        dependsOn = container.dependsOn;
      }) config.virtualisation.oci-containers.containers
    )
  );

  dockerConfig = pkgs.writeTextDir "config.json" "{}";

  migrationCommand = makeToolScript "docker-migration-command" ./tools/docker-migration-command.py {
    python = "${pkgs.python3}";
    docker = "${config.virtualisation.docker.package}";
    systemd = "${pkgs.systemd}";
    openssh = "${pkgs.openssh}";
    coreutils = "${pkgs.coreutils}";
    containerServicesFile = "${containerServicesFile}";
    dockerConfig = "${dockerConfig}";
  };

  migrationSshConfig = pkgs.writeText "docker-migration-ssh-config" ''
    Host *
      IdentityFile /var/lib/docker-volume-migration/identity
      IdentitiesOnly yes
      BatchMode yes
      StrictHostKeyChecking accept-new
      UserKnownHostsFile /var/lib/docker-volume-migration/known_hosts
  '';

  # Load and process each tool script with required package substitutions
  toolScripts = with pkgs; [
    (makeToolScript "migrate-volumes" ./tools/migrate-volumes.sh {
      docker = "${config.virtualisation.docker.package}";
      coreutils = "${coreutils}";
      gawk = "${gawk}";
      openssh = "${openssh}";
      gnugrep = "${gnugrep}";
      migrationCommand = "${migrationCommand}";
      migrationSshConfig = "${migrationSshConfig}";
      dockerConfig = "${dockerConfig}";
    })
  ];
in
{
  system.build.dockerMigrationCommand = migrationCommand;
  environment.systemPackages = toolScripts ++ [ migrationCommand ];
}
