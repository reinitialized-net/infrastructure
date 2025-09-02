#!/bin/bash

# Check if the correct number of arguments is provided
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <IP_ADDRESS> <FLAKE_OUTPUT>"
    exit 1
fi

IP_ADDRESS=$1
FLAKE_OUTPUT=$2

# Log into the NixOS machine and apply the flake
sshpass ssh -o StrictHostKeyChecking=no root@$IP_ADDRESS -i ~/.ssh/rnetadmin << EOF
    set -e
    echo "Updating NixOS system with the latest flake..."

    # Pull the latest flake from GitHub with the specified output
    sudo nix flake update --flake github:Reinitialized/infrastructure && sudo nixos-rebuild switch --flake github:Reinitialized/infrastructure#podmanVM$FLAKE_OUTPUT

    if [ $? -eq 0 ]; then
        echo "Rebuild successful."
    else
        echo "Rebuild failed."
        exit 1
    fi
EOF
