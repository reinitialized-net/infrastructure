# extensions/firewall.nix
## Extends networking.firewall options
##
## Rule priority logic:
## 1. Denylist takes priority over allowlist by default
## 2. Exception: When denylist contains 0.0.0.0/0 (or ::/0 for IPv6), specific
##    allowlist sources for the same port/protocol are processed first
## 3. Denylist entries can specify `exclude` to exempt specific IPs from the block
##
## This allows patterns like:
##   denylist: port 443 from 0.0.0.0/0 (deny all)
##   allowlist: port 443 from 10.0.0.0/8 (but allow internal)
##
##   denylist: port 22 from 10.0.0.0/8, exclude [ "10.1.11.2" "10.1.11.3" ]
##
{ lib, config, pkgs, ...}:
let
  cfg = config.networking.firewall;
  
  # Base entry options shared by allowlist and denylist
  baseEntryOptions = with lib.types; {
    port = lib.mkOption {
      type = int;
      description = "The port number to allow or deny.";
    };
    protocol = lib.mkOption {
      type = types.enum [ "tcp" "udp" "tcp_udp" ];
      description = "The protocol for the port.";
      default = "tcp";
    };
    ipType = lib.mkOption {
      type = types.enum [ "ipv4" "ipv6" "ipv46" ];
      description = "The IP type for the rule.";
      default = "ipv4";
    };
    source = lib.mkOption {
      type = types.listOf types.str;
      description = "List of source IP addresses or CIDR blocks for the rule.";
      default = [ "0.0.0.0/0" ];
    };
  };

  allowlistEntry = lib.types.submodule {
    options = baseEntryOptions;
  };

  denylistEntry = lib.types.submodule {
    options = baseEntryOptions // {
      exclude = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        description = "List of source IP addresses or CIDR blocks to exclude from this deny rule (will be allowed).";
        default = [ ];
      };
    };
  };

  # Check if an entry has a catch-all source (0.0.0.0/0 or ::/0)
  hasCatchAll = entry: 
    builtins.any (addr: addr == "0.0.0.0/0" || addr == "::/0") entry.source;

  # Normalize protocol to list for comparison
  normalizeProtocol = proto: if proto == "tcp_udp" then [ "tcp" "udp" ] else [ proto ];
  
  # Check if two entries match on port and have overlapping protocols
  entriesMatch = a: b:
    a.port == b.port && 
    builtins.any (p: builtins.elem p (normalizeProtocol b.protocol)) (normalizeProtocol a.protocol);

  # Find denylist entries that are catch-all for a given port/protocol
  catchAllDenylistForEntry = entry:
    builtins.filter (deny: hasCatchAll deny && entriesMatch entry deny) cfg.denylist;

  # Split allowlist: entries that override catch-all denylists vs others
  allowlistOverrides = builtins.filter (entry: 
    (catchAllDenylistForEntry entry) != [] && 
    !(hasCatchAll entry)  # Only specific sources can override
  ) cfg.allowlist;

  allowlistNormal = builtins.filter (entry:
    (catchAllDenylistForEntry entry) == [] || hasCatchAll entry
  ) cfg.allowlist;

  # Helper to generate nftables rule for a single address
  mkNftRule = action: entry: addr: let
    mkProtoRule = proto: ipType:
      if ipType == "ipv46" then
        "ip saddr ${addr} ${proto} dport ${toString entry.port} ${action}\nip6 saddr ${addr} ${proto} dport ${toString entry.port} ${action}"
      else if ipType == "ipv4" then
        "ip saddr ${addr} ${proto} dport ${toString entry.port} ${action}"
      else
        "ip6 saddr ${addr} ${proto} dport ${toString entry.port} ${action}";
    protocols = if entry.protocol == "tcp_udp" then [ "tcp" "udp" ] else [ entry.protocol ];
  in lib.concatMapStringsSep "\n" (proto: mkProtoRule proto entry.ipType) protocols;

  # Helper to generate iptables rule for a single address
  mkIptRule = action: entry: addr: let
    mkProtoRule = proto: ipType:
      if ipType == "ipv46" then
        " -A INPUT -4 -p ${proto} -s ${addr} --dport ${toString entry.port} -j ${action}\n -A INPUT -6 -p ${proto} -s ${addr} --dport ${toString entry.port} -j ${action}"
      else if ipType == "ipv4" then
        " -A INPUT -4 -p ${proto} -s ${addr} --dport ${toString entry.port} -j ${action}"
      else
        " -A INPUT -6 -p ${proto} -s ${addr} --dport ${toString entry.port} -j ${action}";
    protocols = if entry.protocol == "tcp_udp" then [ "tcp" "udp" ] else [ entry.protocol ];
  in lib.concatMapStringsSep "\n" (proto: mkProtoRule proto entry.ipType) protocols;

  # Generate rules for a list of entries
  mkNftRules = action: entries:
    lib.concatMapStringsSep "\n"
      (entry: lib.concatMapStringsSep "\n" (mkNftRule action entry) entry.source)
      entries;

  mkIptRules = action: entries:
    lib.concatMapStringsSep "\n"
      (entry: lib.concatMapStringsSep "\n" (mkIptRule action entry) entry.source)
      entries;

  # Generate exclusion rules (ACCEPT before DROP) for denylist entries with exclude
  denylistExclusions = builtins.filter (entry: entry.exclude != []) cfg.denylist;
  
  mkNftExcludeRules = lib.concatMapStringsSep "\n"
    (entry: lib.concatMapStringsSep "\n" (mkNftRule "accept" entry) entry.exclude)
    denylistExclusions;

  mkIptExcludeRules = lib.concatMapStringsSep "\n"
    (entry: lib.concatMapStringsSep "\n" (mkIptRule "ACCEPT" entry) entry.exclude)
    denylistExclusions;

  # Combine rules in priority order:
  # 1. Denylist exclusions (specific IPs exempted from deny rules)
  # 2. Allowlist overrides (specific sources that override catch-all denies)
  # 3. Denylist (including catch-all rules)
  # 4. Normal allowlist (entries without catch-all deny conflicts)
  nftRules = lib.concatStringsSep "\n" (builtins.filter (s: s != "") [
    mkNftExcludeRules
    (mkNftRules "accept" allowlistOverrides)
    (mkNftRules "drop" cfg.denylist)
    (mkNftRules "accept" allowlistNormal)
  ]);

  iptRules = lib.concatStringsSep "\n" (builtins.filter (s: s != "") [
    mkIptExcludeRules
    (mkIptRules "ACCEPT" allowlistOverrides)
    (mkIptRules "DROP" cfg.denylist)
    (mkIptRules "ACCEPT" allowlistNormal)
  ]);

in
{
  options.networking.firewall.allowlist = lib.mkOption {
    type = lib.types.listOf allowlistEntry;
    description = "Granular port allowlist with source IP restrictions.";
    default = [ ];
  };
  
  options.networking.firewall.denylist = lib.mkOption {
    type = lib.types.listOf denylistEntry;
    description = ''
      Granular port denylist with source IP blocks.
      
      Takes priority over allowlist by default. However, if a denylist entry
      uses 0.0.0.0/0 (catch-all), specific allowlist sources for the same
      port/protocol will be processed first, allowing targeted overrides.
      
      Use the `exclude` option to exempt specific IPs from a deny rule:
        { port = 22; source = [ "10.0.0.0/8" ]; exclude = [ "10.1.11.2" ]; }
    '';
    default = [ ];
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (lib.mkIf (cfg.package == pkgs.nftables) {
        # Actions for nftables
        # Rule order: allowlist overrides → denylist → normal allowlist
        networking.firewall.extraInputRules = nftRules;
      })
      (lib.mkIf (cfg.package == pkgs.iptables) {
        # Actions for iptables
        # Rule order: allowlist overrides → denylist → normal allowlist
        networking.firewall.extraCommands = iptRules;
      })
    ]
  );
}