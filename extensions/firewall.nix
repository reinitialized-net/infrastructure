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
        type = types.enum [ "tcp" "udp" "tcp_udp" ];
        description = "The protocol for the port.";
        default = "tcp";
      };
      ipType = mkOption {
        type = types.enum [ "ipv4" "ipv6" "ipv46" ];
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
            (addr: let
              protocolRules = if entry.ipType == "ipv46" then
                "ip saddr ${addr} ${entry.protocol} dport ${toString entry.port} accept\nip6 saddr ${addr} ${entry.protocol} dport ${toString entry.port} accept"
              else if entry.ipType == "ipv4" then
                "ip saddr ${addr} ${entry.protocol} dport ${toString entry.port} accept"
              else
                "ip6 saddr ${addr} ${entry.protocol} dport ${toString entry.port} accept";
              finalRules = if entry.protocol == "tcp_udp" then
                lib.concatMapStringsSep "\n"
                  (proto: if entry.ipType == "ipv46" then
                    "ip saddr ${addr} ${proto} dport ${toString entry.port} accept\nip6 saddr ${addr} ${proto} dport ${toString entry.port} accept"
                  else if entry.ipType == "ipv4" then
                    "ip saddr ${addr} ${proto} dport ${toString entry.port} accept"
                  else
                    "ip6 saddr ${addr} ${proto} dport ${toString entry.port} accept")
                  ["tcp" "udp"]
              else
                protocolRules;
            in finalRules)
            entry.source
          )
          config.networking.firewall.whitelist;
      })
      (lib.mkIf (config.networking.firewall.package == "iptables") {
        # Actions for iptables
        networking.firewall.extraCommands = lib.concatMapStringsSep "\n"
          (entry: lib.concatMapStringsSep "\n"
            (addr: let
              protocolRules = if entry.ipType == "ipv46" then
                " -A INPUT -4 -p ${entry.protocol} -s ${addr} --dport ${toString entry.port} -j ACCEPT\n -A INPUT -6 -p ${entry.protocol} -s ${addr} --dport ${toString entry.port} -j ACCEPT"
              else if entry.ipType == "ipv4" then
                " -A INPUT -4 -p ${entry.protocol} -s ${addr} --dport ${toString entry.port} -j ACCEPT"
              else
                " -A INPUT -6 -p ${entry.protocol} -s ${addr} --dport ${toString entry.port} -j ACCEPT";
              finalRules = if entry.protocol == "tcp_udp" then
                lib.concatMapStringsSep "\n"
                  (proto: if entry.ipType == "ipv46" then
                    " -A INPUT -4 -p ${proto} -s ${addr} --dport ${toString entry.port} -j ACCEPT\n -A INPUT -6 -p ${proto} -s ${addr} --dport ${toString entry.port} -j ACCEPT"
                  else if entry.ipType == "ipv4" then
                    " -A INPUT -4 -p ${proto} -s ${addr} --dport ${toString entry.port} -j ACCEPT"
                  else
                    " -A INPUT -6 -p ${proto} -s ${addr} --dport ${toString entry.port} -j ACCEPT")
                  ["tcp" "udp"]
              else
                protocolRules;
            in finalRules)
            entry.sourceAddresses
          )
          config.networking.firewall.whitelist;
      })
    ]
  );
}