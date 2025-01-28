#!/bin/bash

set -e

export HOME=/home/ubuntu/creator
cd $HOME

# Create directory where Ouisync will create ouisync.sock.
# TODO: Ouisync should attempt to create this directory if it doesn't exist
mkdir -p .cache

repo_name="www"
log=$HOME/ouisync.log

ouisync bind quic/0.0.0.0:0 quic/[::]:0 &> $log
ouisync create --name $repo_name 2>&1 >> $log
ouisync mount --name $repo_name 2>&1 > $log

# Enable announcing on the Bittorrent DHT.
ouisync dht --name "$repo_name" true 2>&1> $log

# Enable peer exchange.
ouisync pex --name "$repo_name" true 2>&1 > $log

# Enable local discovery. Useful mainly for testing in our case.
ouisync local-discovery true 2>&1 > $log

echo "--------------------------------------------------------------------------"
echo "Starting Ouisync, the repository will be mounted at $HOME/ouisync/$repo_name"
echo "while this session is running. Put any files that you want to serve there."
echo ""
echo "TOKENS:"
echo "  WRITE: $(ouisync share --name $repo_name --mode write | grep '^https:')"
echo "  READ:  $(ouisync share --name $repo_name --mode read | grep '^https:')"
echo "  BLIND: $(ouisync share --name $repo_name --mode blind | grep '^https:')"
echo ""
echo "!!! Make sure the WRITE TOKEN is kept secret         !!!"
echo "!!! The 451 deflect seeder only needs the READ TOKEN !!!"
echo ""
echo "Ouisync log can be found at $log"
echo "--------------------------------------------------------------------------"

# Starts ouisync, this blocks.
ouisync start 2>&1 > $log

