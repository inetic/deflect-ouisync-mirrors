#!/bin/bash

set -e

######################################################################
http_port=8080
default_container_name=ouisync-web

function print_help() {
    echo "script for serving web site shared over Ouisync"
    echo "usage: $(basename $0) [--container-name name] [--get-token access] [--start] [--create] [--import token] [--upload dir] [--serve]"
    echo "options:"
    echo "  --container-name name    name of the docker container where to perform commands"
    echo "  --start                  start the container and Ouisync inside it"
    echo "  --create                 create a new repository"
    echo "  --upload dir             upload content of dir into the repository"
    echo "  --get-token acces        get access token of a previously created repository. access must be 'blind','read' or 'write'"
    echo "  --import token           import an existing repository"
    echo "  --serve                  start serving content of the repository over http on port $http_port"
}

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h|--help) print_help; exit ;;
        --container-name)
            container_name=$2; shift
            if [ -z "$container_name" ]; then
                echo "--container-name must not be empty"
                print_help
                exit 1
            fi
            ;;
        --get-token)
            do_get_token="yes"
            get_token_type=$2; shift
            if [ "$get_token_type" != "blind" -a "$get_token_type" != "read" -a "$get_token_type" != "write" ]; then
                echo "--get-token requires one of 'blind', 'read' or 'write' arguments"
                print_help
                exit 1
            fi
            ;;
        --start) do_start="yes" ;;
        --create) do_create="yes" ;;
        --import)
            do_import="yes"
            import_token=$2; shift
            if [[ ! "$import_token" =~ ^https:// ]]; then
                echo "--import requires a valid token (got '$import_token')"
                print_help
                exit 1
            fi
            ;;
        --upload)
            do_upload="yes"
            upload_src_dir=$2; shift
            if [ ! -d "$upload_src_dir" ]; then
                echo "--upload requires a valid directory (got '$upload_src_dir')"
                print_help
                exit 1
            fi
            ;;
        --serve) do_serve="yes" ;;
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
        listen $http_port;
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
