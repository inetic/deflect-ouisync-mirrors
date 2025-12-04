#!/bin/bash

set -e

######################################################################
default_container_name=ouisync-mirrors

function print_help (
    echo "Utility for mirroring directories using Ouisync"
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
    echo
    echo "  --get-token <TYPE>"
    echo
    echo "      The the the token of a repository running in the container. Token <TYPE> must be"
    echo "      'blind', 'read' or 'write'."
)

function error (
    echo "Error: $@"
    echo ""
    print_help
    exit 1
)

container_name=${container_name:=$default_container_name}
image_name=ouisync-mirrors
repo_name=mirror_repo

container_home=/opt
container_ouisync_dir=$container_home/.local/share/org.equalitie.ouisync
container_ouisync_config_dir=$container_ouisync_dir/configs
container_ouisync_store_dir=$container_ouisync_dir/repositories

######################################################################
# Utility to run command inside the docker container
function dock (
    docker $docker_host "$@"
)

function exe (
    dock exec $container_name "$@"
)

function exe_i (
    dock exec -i $container_name "$@"
)

# For debugging
function enter(
    dock exec -it $container_name bash
)

function enable_repo_defaults(
    repo_name=$1
    # Tell ouisync where to mount repositories
    exe ouisync mount-dir $container_home/ouisync
    # Mount the repo to <mount-dir>/$repo_name
    exe ouisync mount "$repo_name"
    # Enable announcing on the Bittorrent DHT
    exe ouisync dht "$repo_name" true
    # Enable peer exchange
    exe ouisync pex "$repo_name" true
    # Enable local discovery. Useful mainly for testing in our case
    exe ouisync local-discovery true
)

function run_container_detached (
    dock build -t $image_name - < ./Dockerfile
    
    local run_args=(
        --detach
        "$@"
        # It's preferable to let Ouisync choose TCP or UDP port number
        --net=host
        # Flags to allow mounting inside the container
        # https://stackoverflow.com/a/49021109/273348
        --device /dev/fuse --cap-add SYS_ADMIN --security-opt apparmor:unconfined
        --name $container_name
        $image_name
    )

    dock run ${run_args[@]} sleep infinity
)

function start_primary_container (
    local store_dir=$1
    local in_dir=$2

    if [ ! -d "$store_dir" ]; then
        error "Store dir is not a valid directory ($store_dir)"
    fi

    if [ ! -d "$in_dir" ]; then
        error "Watch dir is not a valid directory ($in_dir)"
    fi

    run_container_detached \
        -v $store_dir:$container_ouisync_store_dir \
        -v $in_dir:/in_dir:ro
)

function start_mirror_container (
    local out_dir=$1

    if [ ! -d "$out_dir" ]; then
        error "Out dir is not a valid directory ($out_dir)"
    fi

    run_container_detached -v $out_dir:/out_dir:rw
)

function start_ouisync (
    # Start ouisync in the background
    exe sh -c '(nohup ouisync start || echo "Ouisync stopped") &'

    # Wait for ouisync to start
    exe sh -c "while [ ! -f $container_ouisync_config_dir/local_endpoint.conf ]; do sleep 0.2; done"

    # Bind ouisync to IPv4 and IPv6 on random ports
    exe ouisync bind quic/0.0.0.0:0 quic/[::]:0
)

# Whenever there is a change in `IN_DIR` `rsync` its content into the repo mounted directory
function start_updating_from (
    local lsyncd_config=(
        "sync {"
        "    default.rsync,"
        "    source    = '/in_dir/',"
        "    target    = '$container_home/ouisync/$repo_name/',"
        "    delay     = 1,"
        "    rsync     = {"
        #        Ouisync doesn't yet support timestamps so fallback to comparing checksums
        "        checksum     = true,"
        "        ignore_times = true,"
        "        _extra       = {"
        "            '--omit-dir-times',"
        "        },"
        "    },"
        "}"
    )
    local config_file=$(exe mktemp /tmp/lsyncd_config.XXXXXXXX)
    echo -e "${lsyncd_config[@]/%/'\n'}" | exe_i dd of=$config_file
    exe lsyncd $config_file
)

# Continuously `rsync` from the repo into `OUT_DIR`
function start_updating_into (
    # TODO: Ouisync mounted directories don't currently support inotify so we
    # need to fallback to periodical `rsync`.
    local script=(
        "while true; do"
        #  Ouisync doesn't yet support timestamps so fallback to comparing checksums
        "  rsync -rv --del --checksum --ignore-times $container_home/ouisync/$repo_name/ /out_dir;"
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
    if [ -z "$(exe ls $container_ouisync_store_dir/$repo_name.ouisyncdb 2> /dev/null)" ]; then
        exe ouisync create $repo_name
    else
        echo "Repo already exists, reusing."
    fi
    enable_repo_defaults $repo_name
)

function act_as_primary (
    store_dir=$1;
    host_in_dir=$2;
    start_primary_container $store_dir $host_in_dir
    start_ouisync
    create_repo_if_doesnt_exist
    start_updating_from
)

function act_as_mirror (
    token=$1;
    host_out_dir=$2;
    start_mirror_container $host_out_dir
    start_ouisync
    import_ouisync_repo $token
    start_updating_into
)

if [[ "$#" -eq 0 ]]; then
    error "No arguments"
    exit
fi

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
            in_dir=$2; shift
            act_as_primary $store_dir $in_dir
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
