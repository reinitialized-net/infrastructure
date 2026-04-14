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
    # Single group (primary group only)
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
    # Multiple groups (first is primary, rest are extraGroups)
    (lib.makeUser {
      username = "multigroup";
      group = [ "primarygroup" "secondary" "tertiary" ];
      extraGroups = [ "wheel" ];
      extraUserAttrs = {
        description = "User with multiple groups";
      };
    })
  ];
  ```

  # Arguments

  - `username`: The username to create (required)
  - `uid`: Optional UID for the user
  - `group`: Optional group name or list of group names (defaults to username)
  - `gid`: Optional GID for the primary group
  - `homePermissions`: Permissions for home directory (default: "0700")
  - `homeDirectory`: Custom home directory path (default: /home/${username})
  - `dataPath`: Path under /mnt/data (default: /mnt/data/${username})
  - `extraUserAttrs`: Additional attributes to pass to users.users.<name>
  - `extraGroups`: Additional groups the user should be a member of (default: [])
  - `extraGroupAttrs`: Additional attributes to pass to users.groups.<primary group>
*/
{ 
  username,
  uid ? null,
  group ? username,
  extraGroups ? [],
  gid ? null,
  homePermissions ? "0700",
  homeDirectory ? "/home/${username}",
  dataPath ? "/mnt/data/${username}",
  extraUserAttrs ? {},
  extraGroupAttrs ? {},
}:
{ lib, config, ... }:
let
  groupsList = if builtins.isList group then group else [ group ];
  primaryGroup = builtins.head groupsList;

  # Remove extraGroups from extraUserAttrs to handle it explicitly and avoid conflict
  # with the module system's merging logic.
  cleanedExtraUserAttrs = lib.filterAttrs (n: v: n != "extraGroups") extraUserAttrs;

  # Helper to unwrap mkDefault values
  unwrap = x:
    if builtins.isAttrs x && x ? _type && x._type == "override" then
      x.content
    else
      x;

  # Contributions to extraGroups from different sources
  extraGroupsFromGroup = if builtins.isList group then builtins.tail group else [];
  extraGroupsFromArg = extraGroups;
  extraGroupsFromAttrs = extraUserAttrs.extraGroups or [];

  # Combine extraGroups, preserving mkDefault wrapper if any source has it
  combinedExtraGroups = lib.mkDefault (
    (unwrap extraGroupsFromGroup) ++
    (unwrap extraGroupsFromArg) ++
    (unwrap extraGroupsFromAttrs)
  );

  userConfig = (
    {
      group = primaryGroup;
      home = homeDirectory;
      createHome = false;
    } // (if uid != null then { inherit uid; } else {})
      // (if (builtins.hasAttr "isSystemUser" cleanedExtraUserAttrs || builtins.hasAttr "isNormalUser" cleanedExtraUserAttrs) then {} else { isNormalUser = lib.mkDefault true; })
      // cleanedExtraUserAttrs
  ) // {
    extraGroups = combinedExtraGroups;
  };

  groupConfig = lib.genAttrs groupsList (g: 
    if g == primaryGroup 
    then ({} // (if gid != null then { inherit gid; } else {}) // extraGroupAttrs)
    else {}
  );

  # systemd-tmpfiles rules to create and set permissions
  tmpfilesRules = [
    # Create the directory on /mnt/data with correct ownership and permissions
    "d ${dataPath} ${homePermissions} ${username} ${primaryGroup} -"
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
