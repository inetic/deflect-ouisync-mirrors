#!/bin/bash

set -e

######################################################################
default_container_name=ouisync-web

function print_help() {
    echo "Script for serving web site shared over Ouisync"
    echo "Usage: $0 --host <HOST> --commit <COMMIT> [--out <OUTPUT_DIRECTORY>]"
    echo "  HOST:             IP or entry in ~/.ssh/config of machine running Docker"
    echo "  COMMIT:           Commit from which to build"
    echo "  OUTPUT_DIRECTORY: Directory where artifacts will be stored"
}

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h) print_help; exit ;;
        --container-name) container_name=$2; shift ;;
        --get-token) do_get_token="yes"; get_token_type=$2; shift ;;
        start) do_start="yes" ;;
        create) do_create="yes" ;;
        import) do_import="yes"; import_token=$2; shift ;;
        upload) do_upload="yes"; upload_src_dir=$2; shift ;;
        serve) do_serve="yes" ;;
        *) echo "Unknown argument: $1"; print_help; exit 1 ;;
    esac
    shift
done

container_name=${container_name:=$default_container_name}
image_name=ouisync-web
repo_name=www

######################################################################
# Utility to run command inside the docker container
function exe() {
    docker exec $container_name "$@"
}

function exe_i() {
    docker exec -i $container_name "$@"
}

function enable_repo_defaults() {
    repo_name=$1
    # Mount the repo to $HOME/ouisync/$repo_name
    exe ouisync mount --name $repo_name
    # Enable announcing on the Bittorrent DHT.
    exe ouisync dht --name "$repo_name" true
    # Enable peer exchange.
    exe ouisync pex --name "$repo_name" true
    # Enable local discovery. Useful mainly for testing in our case.
    exe ouisync local-discovery true
}

######################################################################
# Start the container and ouisync inside it
if [ "$do_start" = "yes" ]; then
    docker build -t $image_name .
    
    # Flags to allow mounting inside the container
    # https://stackoverflow.com/a/49021109/273348
    fuse_mounting_flags="--device /dev/fuse --cap-add SYS_ADMIN --security-opt apparmor:unconfined"

    docker run \
        --detach \
        --net=host \
        $fuse_mounting_flags \
        --name $container_name $image_name \
        sh -c 'while true; do sleep 1; done'

    exe ouisync bind quic/0.0.0.0:0 quic/[::]:0
    # TODO: Ouisync should create this directory automatically
    exe mkdir -p /opt/.cache
    exe sh -c 'nohup ouisync start &'

    # Give the ouisync command some time to start
    # TODO: Ouisync should have some flag to tell us when it started
    sleep 1
fi

######################################################################
# Create the "www" repository
if [ "$do_create" = "yes" ]; then
    exe ouisync create --name $repo_name
    enable_repo_defaults $repo_name

    write_token=$(exe sh -c "ouisync share --name $repo_name --mode write | grep '^https:'")
    read_token=$( exe sh -c "ouisync share --name $repo_name --mode read  | grep '^https:'")
    blind_token=$(exe sh -c "ouisync share --name $repo_name --mode blind | grep '^https:'")

    echo "--------------------------------------------------------------------------"
    echo ""
    echo "Created repository '$repo_name'."
    echo ""
    echo "TOKENS:"
    echo "  WRITE: $write_token"
    echo "  READ:  $read_token"
    echo "  BLIND: $blind_token"
    echo ""
    echo "!!! Make sure the WRITE TOKEN is kept secret. Anyone who has the WRITE TOKEN"
    echo "!!! can modify the repository. For serving pages, only the READ TOKEN is"
    echo "!!! needed."
    echo ""
    echo "--------------------------------------------------------------------------"
fi

######################################################################
# Import repository from a token
if [ "$do_import" = "yes" ]; then
    exe ouisync create --name $repo_name --share-token $import_token
    enable_repo_defaults $repo_name
fi

######################################################################
# Get repository token 
if [ "$do_get_token" = "yes" ]; then
    exe ouisync share --name $repo_name --mode $get_token_type
fi

######################################################################
# Content of the nginx config file we want inside the serving container
nginx_config=$(cat << EOM
user root;

events {
	worker_connections 768;
}

http {
    server {
        listen 8080;
        location / {
            root /opt/ouisync/$repo_name;
        }
    }
}
EOM
)

######################################################################
# Upload content into the $repo_name repository
if [ "$do_upload" = "yes" ]; then
    # Append '/' to `$upload_src_dir`, otherwise rsync would copy the directory
    # as well as opposed to just its content.
    if [ "${upload_src_dir: -1}" != "/" ]; then
        upload_src_dir="$upload_src_dir/"
    fi

    # Ouisync doesn't support file/dir timestamps yet, so we can't rely
    # on those.
    no_timestamp_flags="--checksum --ignore-times"

    rsync -e 'docker exec -i' -rv $no_timestamp_flags \
        $upload_src_dir \
        $container_name:/opt/ouisync/$repo_name
fi

######################################################################
# Serve content of the repo
if [ "$do_serve" = "yes" ]; then
    echo "$nginx_config" | exe_i dd of=/etc/nginx/nginx.conf
    exe nginx
fi
