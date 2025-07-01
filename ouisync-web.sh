#!/bin/bash

set -e

######################################################################
http_port=8080
default_container_name=ouisync-web

function print_usage() {
    echo "Usage: $(basename $0) [--host host] [--container-name name] [--get-token access] [--start] [--create] [--import token] [--upload dir] [--serve]"
    echo "Options:"
    echo "  --host host              IP or ~/.ssh/config entry of a server running docker where the commands shall run"
    echo "  --container-name name    Name of the docker container where to perform commands. Defaults to $default_container_name"
    echo "  --start                  Start the container and Ouisync inside it"
    echo "  --create                 Create a new repository"
    echo "  --upload dir             Upload content of dir into the repository"
    echo "  --get-token acces        Get access token of a previously created repository. Must be 'blind','read' or 'write'"
    echo "  --import token           Import an existing repository"
    echo "  --serve                  Start serving content of the repository over http on port $http_port"
}

function error() {
    echo "Error: $@"
    echo ""
    print_usage
    exit 1
}

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h|--help)
            echo "Script for serving web site shared over Ouisync"
            echo ""
            print_usage
            exit
            ;;
        --host)
            host=$2; shift
            if [ -z "$host" ]; then
                error "--host must not be empty"
            fi
            docker_host="--host ssh://$host"
            ;;
        --container-name)
            container_name=$2; shift
            if [ -z "$container_name" ]; then
                error "--container-name must not be empty"
            fi
            ;;
        --get-token)
            do_get_token="yes"
            get_token_type=$2; shift
            if [ "$get_token_type" != "blind" -a "$get_token_type" != "read" -a "$get_token_type" != "write" ]; then
                error "Invalid value for --get-token"
            fi
            ;;
        --start) do_start="yes" ;;
        --create) do_create="yes" ;;
        --import)
            do_import="yes"
            import_token=$2; shift
            if [[ ! "$import_token" =~ ^https://ouisync.net/r# ]]; then
                error "--import requires a valid token (got '$import_token')"
            fi
            ;;
        --upload)
            do_upload="yes"
            upload_src_dir=$2; shift
            if [ ! -d "$upload_src_dir" ]; then
                error "--upload requires a valid directory (got '$upload_src_dir')"
            fi
            ;;
        --serve) do_serve="yes" ;;
        *) error "Unknown argument: $1" ;;
    esac
    shift
done

container_name=${container_name:=$default_container_name}
image_name=ouisync-web
repo_name=www

######################################################################
# Utility to run command inside the docker container
function dock() {
    docker $docker_host "$@"
}

function exe() {
    dock exec $container_name "$@"
}

function exe_i() {
    dock exec -i $container_name "$@"
}

function enable_repo_defaults() {
    repo_name=$1
    # Tell ouisync where to mount repositories
    exe ouisync mount-dir /opt/ouisync
    # Mount the repo to <mount-dir>/$repo_name
    exe ouisync mount "$repo_name"
    # Enable announcing on the Bittorrent DHT
    exe ouisync dht "$repo_name" true
    # Enable peer exchange
    exe ouisync pex "$repo_name" true
    # Enable local discovery. Useful mainly for testing in our case
    exe ouisync local-discovery true
}

######################################################################
# Start the container and ouisync inside it
if [ "$do_start" = "yes" ]; then
    dock build -t $image_name - < ./Dockerfile
    
    # Flags to allow mounting inside the container
    # https://stackoverflow.com/a/49021109/273348
    fuse_mounting_flags="--device /dev/fuse --cap-add SYS_ADMIN --security-opt apparmor:unconfined"

    dock run \
        --detach \
        --net=host \
        $fuse_mounting_flags \
        --name $container_name $image_name \
        sleep infinity

    # Start ouisync in the background
    exe sh -c 'nohup ouisync start &'

    # Wait for ouisync to start
    exe sh -c 'while [ ! -f /opt/.config/ouisync/local_control_port.conf ]; do sleep 0.2; done'

    # Bind ouisync to IPv4 and IPv6 on random ports
    exe ouisync bind quic/0.0.0.0:0 quic/[::]:0
fi

######################################################################
# Create the "www" repository
if [ "$do_create" = "yes" ]; then
    exe ouisync create $repo_name
    enable_repo_defaults $repo_name
fi

######################################################################
# Import repository from a token
if [ "$do_import" = "yes" ]; then
    exe ouisync create $repo_name --token $import_token
    enable_repo_defaults $repo_name
fi

######################################################################
# Get repository token 
if [ "$do_get_token" = "yes" ]; then
    exe ouisync share $repo_name --mode $get_token_type
fi

######################################################################
# Upload content into the $repo_name repository
if [ "$do_upload" = "yes" ]; then
    # Append '/' to `$upload_src_dir`, otherwise rsync would copy the directory
    # itself as opposed to its content.
    if [ "${upload_src_dir: -1}" != "/" ]; then
        upload_src_dir="$upload_src_dir/"
    fi

    # Ouisync doesn't support file/dir timestamps yet, so we can't rely
    # on those.
    no_timestamp_flags="--checksum --ignore-times"

    rsync -e "docker $docker_host exec -i" -rv $no_timestamp_flags \
        $upload_src_dir \
        $container_name:/opt/ouisync/$repo_name
fi

######################################################################
# Serve content of the repo

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

if [ "$do_serve" = "yes" ]; then
    echo "$nginx_config" | exe_i dd of=/etc/nginx/nginx.conf
    exe nginx
fi
