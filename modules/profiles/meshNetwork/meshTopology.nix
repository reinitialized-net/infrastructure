{ lib }: let
  # Central mesh network topology definition
  # Define all nodes in one place to avoid duplication across host configs
  
  meshSubnet = "10.255.0.0/24";
  
  # All mesh network nodes
  # Each node has: nodeId, hostname, endpoint (optional), publicKey
  nodes = {
    devenv = {
      nodeId = 1;
      hostname = "devenv";
      endpoint = "10.1.200.2:51820";
      publicKey = "a02vEIEtLx7VvLXUptVOI6Cc6KO8YgftR8BrDAXamxI=";
    };
    rp1 = {
      nodeId = 2;
      hostname = "rp1";
      endpoint = "10.1.12.2:51820";
      publicKey = "JOnePxD+oQUZpnHB9thbalLHr4hAuZ/CnMH2Pprgxkw=";
    };
    apps1 = {
      nodeId = 3;
      hostname = "apps1";
      endpoint = "10.1.11.2:51820";
      publicKey = "tcRfFOQke76a5ipKraCRu4jbh6qJNfyfd2g0YhbsR0A=";
    };
    apps2 = {
      nodeId = 4;
      hostname = "apps2";
      endpoint = "10.1.11.3:51820";
      publicKey = "IifQOSQL9gZyWoQKErF8yzCyvjuJSaq5MhDV6D3kT10=";
    };
    apps3 = {
      nodeId = 5;
      hostname = "apps3";
      endpoint = "10.1.11.4:51820";
      publicKey = "OZEQjnEW/yhOLbVbBIcaQiiTojkuqTnO7n+oEqRbNDI=";
    };

    gs1 = {
      nodeId = 6;
      hostname = "gs1";
      endpoint = "10.1.11.6:51820";
      publicKey = "PL2fD0SDmoNX7L2ysYa7EbiHrpOmYSoZkSehb6q2qQU=";
    };

    db1 = {
      nodeId = 11;
      hostname = "db1";
      endpoint = "10.1.11.11:51820";
      publicKey = "Cv3Ees9qRCDg+MGHTPxBYOb46BT9Dc7hpGVAKTJ/J3o=";
    };
  };
  
  # Convert node definition to peer format
  nodeToPeer = node: {
    inherit (node) nodeId publicKey;
    endpoint = if node ? endpoint then node.endpoint else null;
    persistentKeepalive = 25;
  };
  
in {
  inherit meshSubnet nodes;
  
  # Function to get all peers for a given nodeId
  # Returns list of peers excluding the node itself
  getPeersForNode = nodeId: let
    # Filter out the current node and convert remaining nodes to peer format
    otherNodes = lib.filterAttrs (name: node: node.nodeId != nodeId) nodes;
  in lib.mapAttrsToList (name: node: nodeToPeer node) otherNodes;
  
  # Function to get node config by nodeId
  getNodeByNodeId = nodeId: let
    matchingNodes = lib.filterAttrs (name: node: node.nodeId == nodeId) nodes;
  in if matchingNodes == {} then null else lib.head (lib.attrValues matchingNodes);
  
  # Function to get node config by hostname
  getNodeByHostname = hostname: 
    if nodes ? ${hostname} then nodes.${hostname} else null;
}
