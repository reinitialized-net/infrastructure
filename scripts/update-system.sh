#!/bin/bash

# Check if the correct number of arguments is provided
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <IP_ADDRESS> <FLAKE_OUTPUT>"
    exit 1
fi

IP_ADDRESS=$1
FLAKE_OUTPUT=$2

# nixos-rebuild switch --use-remote-sudo --flake path:./#${FLAKE_OUTPUT} --target-host rnetadmin@${IP_ADDRESS}

# Copy the local repository to the remote host
rsync -avz --delete "$(pwd)/" rnetadmin@${IP_ADDRESS}:/tmp/infrastructure

# Log into the NixOS machine and apply the flake from the copied repo
sshpass ssh -o StrictHostKeyChecking=no rnetadmin@$IP_ADDRESS -i ~/.ssh/rnetadmin << EOF
    set -e
    echo "Updating NixOS system with the local flake copy..."

    cd /tmp/infrastructure
    sudo nixos-rebuild switch --flake path:.#$FLAKE_OUTPUT

    if [ $? -eq 0 ]; then
        echo "Rebuild successful."
    else
        echo "Rebuild failed."
        exit 1
    fi
EOF