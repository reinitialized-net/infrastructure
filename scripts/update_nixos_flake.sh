#!/bin/bash

# Check if the correct number of arguments is provided
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <IP_ADDRESS> <PASSWORD> <FLAKE_OUTPUT>"
    exit 1
fi

IP_ADDRESS=$1
PASSWORD=$2
FLAKE_OUTPUT=$3

# Log into the NixOS machine and apply the flake
sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no root@$IP_ADDRESS << EOF
    set -e
    echo "Updating NixOS system with the latest flake..."

    # Pull the latest flake from GitHub with the specified output
    nixos-rebuild switch --flake github:Reinitialized/infrastructure#$FLAKE_OUTPUT

    if [ $? -eq 0 ]; then
        echo "Rebuild successful."
    else
        echo "Rebuild failed."
        exit 1
    fi
EOF
