# extensions/firewall.nix
## Extends networking.firewall options
{ lib, config, ...}:
let
  inherit (lib) 
    mkOption 
    types;

  whitelistEntry = with types; submodule {
    options = {
      port = mkOption {
        type = int;
        description = "The port number to allow.";
      };
      protocol = mkOption {
        type = types.enum [ "tcp" "udp" ];
        description = "The protocol for the port.";
        default = "tcp";
      };
      ipType = mkOption {
        type = types.enum [ "ipv4" "ipv6" ];
        description = "The IP type for the rule.";
        default = "ipv4";
      };
      source = mkOption {
        type = types.listOf types.str;
        description = "List of source IP addresses or CIDR blocks allowed to access the port.";
        default = [ "0.0.0.0/0" ];
      };
    };
  };
in
{
  options = {
    networking.firewall.whitelist = mkOption {
      type = types.listOf whitelistEntry;
      description = "List of firewall whitelist entries to allow specific ports and protocols.";
      default = [ ];
    };
  };
  config = lib.mkIf (config.networking.firewall.enable) (
    lib.mkMerge [
      (lib.mkIf (config.networking.firewall.package == "nftables") {
        # Actions for nftables
        networking.firewall.extraInputRules = lib.concatMapStringsSep "\n"
          (entry: lib.concatMapStringsSep "\n"
            (addr: let ipPrefix = if entry.ipType == "ipv4" then "ip saddr" else "ip6 saddr"; in "${ipPrefix} ${addr} ${entry.protocol} dport ${toString entry.port} accept")
            entry.source
          )
          config.networking.firewall.whitelist;
      })
      (lib.mkIf (config.networking.firewall.package == "iptables") {
        # Actions for iptables
        networking.firewall.extraCommands = lib.concatMapStringsSep "\n"
          (entry: lib.concatMapStringsSep "\n"
            (addr: let ipPrefix = if entry.ipType == "ipv4" then "-4" else "-6"; in " -A INPUT ${ipPrefix} -p ${entry.protocol} -s ${addr} --dport ${toString entry.port} -j ACCEPT")
            entry.sourceAddresses
          )
          config.networking.firewall.whitelist;
      })
    ]
  );
}