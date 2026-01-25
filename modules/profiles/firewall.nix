# extensions/firewall.nix
## Extends networking.firewall options
{ lib, config, pkgs, ...}:
let
  firewallEntry = with lib.types; submodule {
    options = {
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
  };
in
{
  options.networking.firewall.allowlist = lib.mkOption {
    type = lib.types.listOf firewallEntry;
    description = "Granular port allowlist with source IP restrictions.";
    default = [ ];
  };
  
  options.networking.firewall.denylist = lib.mkOption {
    type = lib.types.listOf firewallEntry;
    description = "Granular port denylist with source IP blocks. Takes priority over allowlist.";
    default = [ ];
  };
  config = lib.mkIf (config.networking.firewall.enable) (
    lib.mkMerge [
      (lib.mkIf (config.networking.firewall.package == pkgs.nftables) {
        # Actions for nftables
        # Denylist rules come first (higher priority)
        networking.firewall.extraInputRules = 
          (lib.concatMapStringsSep "\n"
            (entry: lib.concatMapStringsSep "\n"
              (addr: let
                protocolRules = if entry.ipType == "ipv46" then
                  "ip saddr ${addr} ${entry.protocol} dport ${toString entry.port} drop\nip6 saddr ${addr} ${entry.protocol} dport ${toString entry.port} drop"
                else if entry.ipType == "ipv4" then
                  "ip saddr ${addr} ${entry.protocol} dport ${toString entry.port} drop"
                else
                  "ip6 saddr ${addr} ${entry.protocol} dport ${toString entry.port} drop";
                finalRules = if entry.protocol == "tcp_udp" then
                  lib.concatMapStringsSep "\n"
                    (proto: if entry.ipType == "ipv46" then
                      "ip saddr ${addr} ${proto} dport ${toString entry.port} drop\nip6 saddr ${addr} ${proto} dport ${toString entry.port} drop"
                    else if entry.ipType == "ipv4" then
                      "ip saddr ${addr} ${proto} dport ${toString entry.port} drop"
                    else
                      "ip6 saddr ${addr} ${proto} dport ${toString entry.port} drop")
                    ["tcp" "udp"]
                else
                  protocolRules;
              in finalRules)
              entry.source
            )
            config.networking.firewall.denylist) + "\n" +
          (lib.concatMapStringsSep "\n"
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
            config.networking.firewall.allowlist);
      })
      (lib.mkIf (config.networking.firewall.package == pkgs.iptables) {
        # Actions for iptables
        # Denylist rules come first (higher priority)
        networking.firewall.extraCommands = 
          (lib.concatMapStringsSep "\n"
            (entry: lib.concatMapStringsSep "\n"
              (addr: let
                protocolRules = if entry.ipType == "ipv46" then
                  " -A INPUT -4 -p ${entry.protocol} -s ${addr} --dport ${toString entry.port} -j DROP\n -A INPUT -6 -p ${entry.protocol} -s ${addr} --dport ${toString entry.port} -j DROP"
                else if entry.ipType == "ipv4" then
                  " -A INPUT -4 -p ${entry.protocol} -s ${addr} --dport ${toString entry.port} -j DROP"
                else
                  " -A INPUT -6 -p ${entry.protocol} -s ${addr} --dport ${toString entry.port} -j DROP";
                finalRules = if entry.protocol == "tcp_udp" then
                  lib.concatMapStringsSep "\n"
                    (proto: if entry.ipType == "ipv46" then
                      " -A INPUT -4 -p ${proto} -s ${addr} --dport ${toString entry.port} -j DROP\n -A INPUT -6 -p ${proto} -s ${addr} --dport ${toString entry.port} -j DROP"
                    else if entry.ipType == "ipv4" then
                      " -A INPUT -4 -p ${proto} -s ${addr} --dport ${toString entry.port} -j DROP"
                    else
                      " -A INPUT -6 -p ${proto} -s ${addr} --dport ${toString entry.port} -j DROP")
                    ["tcp" "udp"]
                else
                  protocolRules;
              in finalRules)
              entry.source
            )
            config.networking.firewall.denylist) + "\n" +
          (lib.concatMapStringsSep "\n"
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
              entry.source
            )
            config.networking.firewall.allowlist);
      })
    ]
  );
}