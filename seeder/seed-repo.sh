#!/bin/bash

set -e

export DIR=/home/ubuntu/seeder

token_arg=$1

if [ -z "$token_arg" ]; then
    echo "Missing token argument"
    echo ""
    echo "Usage $0 <TOKEN>"
    exit 1
fi

# This needs to run as the ubuntu user or nginx won't be able to access the
# mounted folder. TODO: Perhaps there is a better way to do it.
function run_as_ubuntu_user {(
    export HOME=$1
    local token=$2

    cd $HOME
    
    # Create directory where Ouisync will create ouisync.sock.
    # TODO: Ouisync should attempt to create this directory if it doesn't exist
    mkdir -p .cache
    
    local repo_name="www"
    local log=$HOME/ouisync.log

    ouisync create --name $repo_name --share-token $token &> $log
    ouisync mount --name $repo_name &>> $log

    # Bind socket and start P2P machinery
    ouisync bind quic/0.0.0.0:0 quic/[::]:0 &>> $log

    # Enable announcing on the Bittorrent DHT.
    ouisync dht --name "$repo_name" true &>> $log
    
    # Enable peer exchange.
    ouisync pex --name "$repo_name" true &>> $log
    
    # Enable local discovery. Useful mainly for testing in our case.
    ouisync local-discovery true &>> $log

    echo "--------------------------------------------------------------------------"
    echo "Starting ouisync. Once synced, the files to serve will be in $HOME/ouisync/$repo_name"
    echo "from where nginx will serve them (see nginx.conf)."
    echo "--------------------------------------------------------------------------"
    
    # Starts ouisync, this blocks.
    ouisync start &>> $log
)}

export -f run_as_ubuntu_user
su ubuntu -c "bash -c 'run_as_ubuntu_user $DIR $token_arg'"

