#!/bin/bash

set -e

######################################################################
default_container_name=ouisync-mirrors

function print_help() {
    echo "Utility to mirror directories using Ouisync"
    echo
    echo "Usage: $(basename $0) [--host host] [--container-name name] ([--get-token ...] | [--primary ...] | [--mirror ...])"
    echo
    echo "Options:"
    echo "  --host <HOST>"
    echo
    echo "      IP or ~/.ssh/config entry of a server running docker where the commands shall run"
    echo
    echo "  --container-name <NAME>"
    echo
    echo "      Name of the docker container where to perform commands. Defaults to $default_container_name"
    echo
    echo "  --primary <STORE> <IN_DIR>"
    echo
    echo "      Makes this script act as a \"primary\" server, meaning that content of <IN_DIR> will"
    echo "      be mirrored into \"mirror\" servers. <STOREDIR> needs to point to a directory"
    echo "      where ouisync will store the repository databases."
    echo
    echo "  --mirror <TOKEN> <OUT_DIR>"
    echo
    echo "      Makes this script act as a \"mirror\" server, meaning that content of a repository"
    echo "      represented by <TOKEN> will be mirrored into the <OUT_DIR> directory."
}

function error() {
    echo "Error: $@"
    echo ""
    print_help
    exit 1
}

container_name=${container_name:=$default_container_name}
image_name=ouisync-mirrors
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

function enter(
    dock exec -it $container_name bash
)

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

function run_container_detached (
    dock build -t $image_name - < ./Dockerfile
    
    # Flags to allow mounting inside the container
    # https://stackoverflow.com/a/49021109/273348
    fuse_mounting_flags="--device /dev/fuse --cap-add SYS_ADMIN --security-opt apparmor:unconfined"

    dock run \
        --detach \
        --net=host \
        "$@" \
        $fuse_mounting_flags \
        --name $container_name $image_name \
        sleep infinity
)

function start_primary_container (
    local store_dir=$1
    local watch_dir=$2

    if [ ! -d "$store_dir" ]; then
        error "Store dir is not a valid directory ($store_dir)"
    fi

    if [ ! -d "$watch_dir" ]; then
        error "Watch dir is not a valid directory ($watch_dir)"
    fi

    run_container_detached \
        -v $store_dir:/opt/.local/share/ouisync \
        -v $watch_dir:/watch_dir:ro
)

function start_mirror_container (
    local out_dir=$1

    # TODO: Check if token is valid

    if [ ! -d "$out_dir" ]; then
        error "Out dir is not a valid directory ($out_dir)"
    fi

    run_container_detached -v $out_dir:/out_dir:rw
)

function start_ouisync (
    # Start ouisync in the background
    exe sh -c 'nohup ouisync start &'

    # Wait for ouisync to start
    exe sh -c 'while [ ! -f /opt/.config/ouisync/local_control_port.conf ]; do sleep 0.2; done'

    # Bind ouisync to IPv4 and IPv6 on random ports
    exe ouisync bind quic/0.0.0.0:0 quic/[::]:0
)

# Continuously `rsync` from `WATCH_DIR` into the repo
function start_watching (
    # TODO: Use something like lsyncd
    local script=(
        "while true; do"
        "  rsync -rv --del --checksum --ignore-times /watch_dir/ ~/ouisync/www;"
        "  sleep 1;"
        "done"
    )
    exe bash -c "${script[*]}&"
)

# Continuously `rsync` from the repo into `OUT_DIR`
function start_updating (
    # TODO: Use something like lsyncd
    local script=(
        "while true; do"
        "  rsync -rv --del --checksum --ignore-times ~/ouisync/www/ /out_dir;"
        "  sleep 1;"
        "done"
    )
    exe bash -c "${script[*]}&"
)

function is_valid_token (
    local token=$1
    if [[ ! "$token" =~ ^https://ouisync.net/r# ]]; then
        return 1
    fi
)

function import_ouisync_repo (
    local token=$1
    if ! is_valid_token "$token"; then
        error "The token is invalid ($token)"
    fi
    exe ouisync create $repo_name --token $token
    enable_repo_defaults $repo_name
)

function get_repo_token (
    local token_type=$1
    if [ "$token_type" != "blind" -a "$token_type" != "read" -a "$token_type" != "write" ]; then
        error "Invalid value for --get-token ($token_type). Valid values are 'blind', 'read' or 'write'."
    fi
    exe ouisync share $repo_name --mode $token_type
)

function create_repo_if_doesnt_exist (
    if [ -z "$(exe ls /opt/.local/share/ouisync/$repo_name.ouisyncdb)" ]; then
        exe ouisync create $repo_name
    else
        echo "Repo already exists, reusing."
    fi
    enable_repo_defaults $repo_name
)

function act_as_primary (
    store_dir=$1;
    watch_dir=$2;
    start_primary_container $store_dir $watch_dir
    start_ouisync
    create_repo_if_doesnt_exist
    start_watching $watch_dir
)

function act_as_mirror (
    token=$1;
    out_dir=$2;
    start_mirror_container $out_dir
    start_ouisync
    import_ouisync_repo $token
    start_updating
)

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h|--help)
            print_help
            exit
            ;;
        --host|-H)
            host=$2; shift
            if [ -z "$host" ]; then
                error "--host must not be empty"
            fi
            docker_host="--host ssh://$host"
            ;;
        --container-name|-c)
            container_name=$2; shift
            if [ -z "$container_name" ]; then
                error "--container-name must not be empty"
            fi
            ;;
        --primary|-p)
            store_dir=$2; shift
            watch_dir=$2; shift
            act_as_primary $store_dir $watch_dir
            ;;
        --mirror|-m)
            token=$2; shift
            out_dir=$2; shift
            act_as_mirror $token $out_dir
            ;;
        --get-token)
            token_type=$2; shift
            get_repo_token $token_type
            ;;
        *) error "Unknown argument: $1" ;;
    esac
    shift
done
