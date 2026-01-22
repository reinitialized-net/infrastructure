{}: 
/**
  Creates a user with their home directory bind mounted from /mnt/data 
  and ensures proper permissions are set.

  This function handles:
  - User creation with specified attributes
  - Bind mounting home directory from /mnt/data
  - Setting correct ownership and permissions via systemd-tmpfiles
  - Dependencies to ensure /mnt/data is mounted first

  # Example

  ```nix
  imports = [
    (lib.makeUser {
      username = "myapp";
      uid = 1001;
      group = "myapp";
      gid = 1001;
      homePermissions = "0700";
      extraUserAttrs = {
        extraGroups = [ "docker" ];
        shell = pkgs.bashInteractive;
      };
    })
  ];
  ```

  # Arguments

  - `username`: The username to create (required)
  - `uid`: Optional UID for the user
  - `group`: Optional group name (defaults to username)
  - `gid`: Optional GID for the group
  - `homePermissions`: Permissions for home directory (default: "0700")
  - `homeDirectory`: Custom home directory path (default: /home/${username})
  - `dataPath`: Path under /mnt/data (default: /mnt/data/${username})
  - `extraUserAttrs`: Additional attributes to pass to users.users.<name>
  - `extraGroupAttrs`: Additional attributes to pass to users.groups.<name>
*/
{ 
  username,
  uid ? null,
  group ? username,
  gid ? null,
  homePermissions ? "0700",
  homeDirectory ? "/home/${username}",
  dataPath ? "/mnt/data/${username}",
  extraUserAttrs ? {},
  extraGroupAttrs ? {},
}:
{ lib, config, ... }:
let
  userConfig = {
    isNormalUser = lib.mkDefault true;
    inherit group;
    home = homeDirectory;
    createHome = false;  # We'll create via tmpfiles
  } // (if uid != null then { inherit uid; } else {})
    // extraUserAttrs;

  groupConfig = {
    ${group} = ({} // (if gid != null then { inherit gid; } else {})
      // extraGroupAttrs);
  };

  # systemd-tmpfiles rules to create and set permissions
  tmpfilesRules = [
    # Create the directory on /mnt/data with correct ownership and permissions
    "d ${dataPath} ${homePermissions} ${username} ${group} -"
  ];
in
{
  assertions = [
    {
      assertion = config.fileSystems."/mnt/data".fsType or null != null;
      message = "makeUser requires /mnt/data to be configured (use modules/profiles/mountData.nix)";
    }
  ];

  users.users.${username} = userConfig;
  users.groups = groupConfig;

  # Create and set permissions on the data directory
  systemd.tmpfiles.rules = tmpfilesRules;

  # Bind mount from /mnt/data to home directory
  fileSystems.${homeDirectory} = {
    device = dataPath;
    depends = [ "/mnt/data" ];
    fsType = "none";
    options = [ "bind" ];
  };
}
